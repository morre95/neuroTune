package dev.neurotune.neurotune

import android.Manifest
import android.bluetooth.BluetoothManager
import android.content.pm.PackageManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.util.Log
import com.choosemuse.libmuse.Accelerometer
import com.choosemuse.libmuse.Battery
import com.choosemuse.libmuse.ConnectionState
import com.choosemuse.libmuse.Eeg
import com.choosemuse.libmuse.Gyro
import com.choosemuse.libmuse.Muse
import com.choosemuse.libmuse.MuseArtifactPacket
import com.choosemuse.libmuse.MuseConnectionListener
import com.choosemuse.libmuse.MuseConnectionPacket
import com.choosemuse.libmuse.MuseDataListener
import com.choosemuse.libmuse.MuseDataPacket
import com.choosemuse.libmuse.MuseDataPacketType
import com.choosemuse.libmuse.MuseListener
import com.choosemuse.libmuse.MuseManagerAndroid
import com.choosemuse.libmuse.MuseModel
import com.choosemuse.libmuse.MusePreset
import com.choosemuse.libmuse.Optics
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

/// LibMuse 8.0.9 preset 1034: 4 EEG channels at 256 Hz and 8 optics channels at 64 Hz.
/// OPTICS3 and OPTICS4 are the 850 nm left and right outer channels, in microamps.
private enum class StartPhase { PERMISSIONS, SCANNING, CONNECTING }

class MuseBridge(private val activity: FlutterActivity) {
    private val handler = Handler(Looper.getMainLooper())
    private val manager = MuseManagerAndroid.getInstance()
    @Volatile private var muse: Muse? = null
    @Volatile private var disposed = false
    @Volatile private var generation = 0L
    private var methodChannel: MethodChannel? = null
    private val eventChannels = ArrayList<EventChannel>()
    private var startResult: MethodChannel.Result? = null
    private var eegSink: EventChannel.EventSink? = null
    private var opticsSink: EventChannel.EventSink? = null
    private var batterySink: EventChannel.EventSink? = null
    private var diagnosticSink: EventChannel.EventSink? = null
    private var batteryPercent: Int? = null
    private var connected = false
    /// Set by the first packet the bridge ever sees and never reset, so the
    /// timeline keeps running across reconnects. A session rebases this clock
    /// to its own start, which is later than the contact preview's.
    private var originUs: Long? = null
    private val eeg = Array(4) { ArrayList<Double>() }
    private val accel = ArrayList<List<Double>>()
    private val gyro = ArrayList<List<Double>>()
    private val contact = ArrayList<List<Int>>()
    private var eegStart = 0.0
    private val lastAccel = doubleArrayOf(0.0, 0.0, 1.0)
    private val lastGyro = doubleArrayOf(0.0, 0.0, 0.0)
    private val lastContact = intArrayOf(1, 1, 1, 1)
    private val optics = Array(8) { ArrayList<Double>() }
    private var opticsStart = 0.0
    /// Which stage of a start is running, so the shared timeout can report the
    /// stage that actually stalled.
    private var startPhase: StartPhase? = null
    private val scanning get() = startPhase == StartPhase.SCANNING

    private val museListener = object : MuseListener() {
        override fun museListChanged() {
            val expected = generation
            handler.post {
                if (!disposed && activeBridge === this@MuseBridge && generation == expected) onMuses()
            }
        }
    }

    fun register(messenger: BinaryMessenger) {
        // The SDK singleton owns its Bluetooth receiver for the process.
        // Its documentation recommends application context for this lifetime.
        check(!disposed)
        activeBridge?.takeIf { it !== this }?.dispose()
        if (!contextConfigured) {
            manager.setContext(activity.applicationContext)
            contextConfigured = true
        }
        activeBridge = this
        manager.setMuseListener(museListener)
        methodChannel = MethodChannel(messenger, "dev.neurotune/muse").also { channel ->
            channel.setMethodCallHandler { call, result ->
                when (call.method) {
                    "start" -> start(result)
                    "stop" -> {
                        stop()
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
        }
        eventChannels += EventChannel(messenger, "dev.neurotune/muse_eeg").also {
            it.setStreamHandler(sinkHandler { eegSink = it })
        }
        eventChannels += EventChannel(messenger, "dev.neurotune/muse_optics").also {
            it.setStreamHandler(sinkHandler { opticsSink = it })
        }
        eventChannels += EventChannel(messenger, "dev.neurotune/muse_battery").also {
            it.setStreamHandler(sinkHandler { sink ->
                batterySink = sink
                sink?.success(batteryPercent)
            })
        }
        eventChannels += EventChannel(messenger, "dev.neurotune/muse_diagnostics").also {
            it.setStreamHandler(sinkHandler { diagnosticSink = it })
        }
    }

    fun onPermissions(grantResults: IntArray) {
        if (disposed || startResult == null || startPhase != StartPhase.PERMISSIONS) return
        val granted = grantResults.isNotEmpty() && grantResults.all { it == PackageManager.PERMISSION_GRANTED }
        if (!granted) {
            teardown()
            finishStart("BLUETOOTH_DENIED", "Bluetooth-behörighet saknas.")
            return
        }
        beginScan()
    }

    private fun start(result: MethodChannel.Result) {
        if (disposed || activeBridge !== this) {
            result.error("MUSE_DISPOSED", "Muse-anslutningen stängdes.", null)
            return
        }
        if (startResult != null) {
            result.error("MUSE_BUSY", "En anslutning pågår redan.", null)
            return
        }
        teardown()
        startResult = result
        if (!bluetoothEnabled()) {
            finishStart("BLUETOOTH_OFF", "Bluetooth är avstängt.")
            return
        }
        val permissions = requiredPermissions()
        val missing = permissions.any {
            activity.checkSelfPermission(it) != PackageManager.PERMISSION_GRANTED
        }
        if (missing) {
            // A dialog the user never answers must not strand startResult.
            startPhase = StartPhase.PERMISSIONS
            handler.postDelayed(startTimeout, PERMISSION_TIMEOUT_MS)
            activity.requestPermissions(permissions, REQUEST_PERMISSIONS)
            return
        }
        beginScan()
    }

    private fun beginScan() {
        startPhase = StartPhase.SCANNING
        manager.stopListening()
        manager.startListening()
        handler.removeCallbacks(startTimeout)
        handler.postDelayed(startTimeout, SCAN_TIMEOUT_MS)
        handler.removeCallbacks(scanPoll)
        handler.post(scanPoll)
    }

    /// LibMuse keeps a headband in its list for DEFAULT_REMOVE_FROM_LIST_AFTER
    /// (30 s) after it was last seen, and only calls museListChanged() when that
    /// list actually changes. Rediscovering a headband that is still listed from
    /// the previous session is not a change, so the callback alone never fires.
    /// getMuses() reads the live list, so poll it instead of waiting to be told.
    private val scanPoll = object : Runnable {
        override fun run() {
            if (!scanning || startResult == null) return
            onMuses()
            if (scanning && startResult != null) handler.postDelayed(this, SCAN_POLL_MS)
        }
    }

    private val startTimeout = Runnable {
        val stalled = startPhase
        teardown()
        when (stalled) {
            StartPhase.PERMISSIONS ->
                finishStart("BLUETOOTH_DENIED", "Bluetooth-behörigheten besvarades inte.")
            StartPhase.SCANNING ->
                finishStart("MUSE_NOT_FOUND", "Ingen Muse S Athena hittades.")
            else ->
                finishStart("MUSE_TIMEOUT", "Muse svarade inte på anslutningen.")
        }
    }

    private fun onMuses() {
        if (disposed || activeBridge !== this || !scanning || startResult == null) return
        val found = manager.muses.firstOrNull { it.model == MuseModel.MS_03 } ?: return
        startPhase = StartPhase.CONNECTING
        handler.removeCallbacks(startTimeout)
        manager.stopListening()
        connect(found)
    }

    private fun connect(headband: Muse) {
        muse = headband
        val connection = ++generation
        headband.unregisterAllListeners()
        headband.registerConnectionListener(object : MuseConnectionListener() {
            override fun receiveMuseConnectionPacket(packet: MuseConnectionPacket, muse: Muse) {
                handler.post { if (ownsConnection(muse, connection)) onConnection(packet) }
            }
        })
        val listener = dataListener(connection)
        headband.registerDataListener(listener, MuseDataPacketType.EEG)
        headband.registerDataListener(listener, MuseDataPacketType.ACCELEROMETER)
        headband.registerDataListener(listener, MuseDataPacketType.GYRO)
        headband.registerDataListener(listener, MuseDataPacketType.HSI_PRECISION)
        headband.registerDataListener(listener, MuseDataPacketType.OPTICS)
        headband.registerDataListener(listener, MuseDataPacketType.BATTERY)
        headband.registerDataListener(listener, MuseDataPacketType.ARTIFACTS)
        headband.setPreset(MusePreset.PRESET_1034)
        headband.runAsynchronously()
        handler.postDelayed(startTimeout, CONNECT_TIMEOUT_MS)
    }

    private fun onConnection(packet: MuseConnectionPacket) {
        when (packet.currentConnectionState) {
            ConnectionState.CONNECTED -> {
                connected = true
                handler.removeCallbacks(startTimeout)
                finishStart(null, null)
            }
            ConnectionState.DISCONNECTED -> {
                connected = false
                batteryPercent = null
                batterySink?.success(null)
                if (startResult != null) {
                    teardown()
                    finishStart("MUSE_DISCONNECTED", "Muse kopplades från innan sessionen började.")
                } else {
                    failStreams("Muse kopplades från.")
                }
            }
            ConnectionState.NEEDS_LICENSE -> {
                teardown()
                finishStart("MUSE_LICENSE", "LibMuse kräver en licens för det här headsetet.")
            }
            else -> Unit
        }
    }

    private fun ownsConnection(headband: Muse, expected: Long): Boolean =
        !disposed && activeBridge === this && generation == expected && muse === headband

    private fun postData(headband: Muse, expected: Long, action: () -> Unit) {
        if (disposed || generation != expected) return
        handler.post { if (connected && ownsConnection(headband, expected)) action() }
    }

    private fun dataListener(connection: Long): MuseDataListener {
        return object : MuseDataListener() {
            override fun receiveMuseArtifactPacket(packet: MuseArtifactPacket, muse: Muse) {
                if (disposed || generation != connection) return
                val values = mapOf(
                    "headband_on" to packet.headbandOn,
                    "blink" to packet.blink,
                    "jaw_clench" to packet.jawClench,
                )
                val timestamp = packet.timestamp
                postData(muse, connection) {
                    diagnosticSink?.success(mapOf(
                        "type" to "artifact",
                        "time_seconds" to sessionSeconds(timestamp),
                        "values" to values,
                    ))
                }
            }

            override fun receiveMuseDataPacket(packet: MuseDataPacket, muse: Muse) {
                if (disposed || generation != connection) return
                when (packet.packetType()) {
                    MuseDataPacketType.BATTERY -> {
                        val percentage = packet.getBatteryValue(Battery.CHARGE_PERCENTAGE_REMAINING)
                        val timestamp = packet.timestamp()
                        if (percentage.isFinite() && percentage in 0.0..100.0) {
                            postData(muse, connection) {
                                batteryPercent = kotlin.math.round(percentage).toInt()
                                batterySink?.success(batteryPercent)
                                diagnosticSink?.success(mapOf(
                                    "type" to "battery",
                                    "time_seconds" to sessionSeconds(timestamp),
                                    "values" to mapOf("percent" to percentage),
                                ))
                            }
                        }
                    }
                    MuseDataPacketType.EEG -> {
                        val values = DoubleArray(4) { index ->
                            packet.getEegChannelValue(EEG_CHANNELS[index])
                        }
                        val time = packet.timestamp()
                        postData(muse, connection) { addEeg(time, values) }
                    }
                    MuseDataPacketType.ACCELEROMETER -> {
                        val values = doubleArrayOf(
                            packet.getAccelerometerValue(Accelerometer.X),
                            packet.getAccelerometerValue(Accelerometer.Y),
                            packet.getAccelerometerValue(Accelerometer.Z),
                        )
                        postData(muse, connection) { values.copyInto(lastAccel) }
                    }
                    MuseDataPacketType.GYRO -> {
                        val values = doubleArrayOf(
                            packet.getGyroValue(Gyro.X),
                            packet.getGyroValue(Gyro.Y),
                            packet.getGyroValue(Gyro.Z),
                        )
                        postData(muse, connection) { values.copyInto(lastGyro) }
                    }
                    MuseDataPacketType.HSI_PRECISION -> {
                        val values = IntArray(4) { index ->
                            packet.getEegChannelValue(EEG_CHANNELS[index]).toInt()
                        }
                        postData(muse, connection) { values.copyInto(lastContact) }
                    }
                    MuseDataPacketType.OPTICS -> {
                        val values = DoubleArray(8) { index -> packet.getOpticsChannelValue(OPTICS_CHANNELS[index]) }
                        val time = packet.timestamp()
                        postData(muse, connection) { addOptics(time, values) }
                    }
                    else -> Unit
                }
            }
        }
    }

    private fun addEeg(timestampUs: Long, values: DoubleArray) {
        val seconds = sessionSeconds(timestampUs)
        if (eeg[0].isEmpty()) eegStart = seconds
        for (channel in values.indices) eeg[channel].add(values[channel])
        accel.add(lastAccel.toList())
        gyro.add(lastGyro.toList())
        contact.add(lastContact.toList())
        if (eeg[0].size >= EEG_CHUNK) emitEeg()
    }

    private fun emitEeg() {
        val sink = eegSink ?: return clearEeg()
        sink.success(
            mapOf(
                "channel_names" to listOf("EEG1", "EEG2", "EEG3", "EEG4"),
                "unit" to "uV",
                "sample_rate_hz" to EEG_RATE_HZ,
                "time_seconds" to eegStart,
                "eeg" to eeg.map { ArrayList(it) },
                "accel" to ArrayList(accel),
                "gyro" to ArrayList(gyro),
                "contact" to ArrayList(contact),
            ),
        )
        clearEeg()
    }

    private fun clearEeg() {
        eeg.forEach { it.clear() }
        accel.clear()
        gyro.clear()
        contact.clear()
    }

    private fun addOptics(timestampUs: Long, values: DoubleArray) {
        val seconds = sessionSeconds(timestampUs)
        if (optics[0].isEmpty()) opticsStart = seconds
        for (channel in values.indices) optics[channel].add(values[channel])
        if (optics[0].size >= OPTICS_CHUNK) emitOptics()
    }

    private fun emitOptics() {
        val sink = opticsSink ?: return clearOptics()
        sink.success(
            mapOf(
                "channel_names" to (1..8).map { "OPTICS$it" },
                "unit" to "uA",
                "sample_rate_hz" to OPTICS_RATE_HZ,
                "time_seconds" to opticsStart,
                "values" to optics.map { ArrayList(it) },
            ),
        )
        clearOptics()
    }

    private fun clearOptics() {
        optics.forEach { it.clear() }
    }

    private fun sessionSeconds(timestampUs: Long): Double {
        val origin = originUs ?: timestampUs.also { originUs = it }
        return (timestampUs - origin) / 1_000_000.0
    }

    private fun stop() {
        teardown()
        finishStart("MUSE_STOPPED", "Anslutningen avbröts.")
    }

    /// Returns the bridge to the state it had before the first start: no scan
    /// running, no pending timeout, no headband holding a BLE link and no
    /// samples left over from the previous session. The clock origin stays.
    private fun teardown() {
        generation++
        val previous = muse
        // Invalidate identity before SDK operations can dispatch late callbacks.
        muse = null
        connected = false
        batteryPercent = null
        startPhase = null
        handler.removeCallbacksAndMessages(null)
        cleanup("scan") { if (activeBridge === this) manager.stopListening() }
        cleanup("listeners") { previous?.unregisterAllListeners() }
        cleanup("disconnect") { previous?.disconnect() }
        cleanup("battery") { batterySink?.success(null) }
        clearEeg()
        clearOptics()
    }

    /** Main-thread lifecycle boundary, idempotent even after replacement. */
    fun dispose() {
        if (disposed) return
        disposed = true
        eegSink = null
        opticsSink = null
        batterySink = null
        diagnosticSink = null
        teardown()
        // Reply once while the old messenger still has its method handler.
        cleanup("pending_start") { finishStart("MUSE_DISPOSED", "Muse-anslutningen stängdes.") }
        if (activeBridge === this) {
            cleanup("manager_listener") { manager.setMuseListener(null) }
            activeBridge = null
        }
        cleanup("method_channel") { methodChannel?.setMethodCallHandler(null) }
        methodChannel = null
        eventChannels.forEach { channel -> cleanup("event_channel") { channel.setStreamHandler(null) } }
        eventChannels.clear()
    }

    private inline fun cleanup(resource: String, action: () -> Unit) {
        try { action() } catch (_: Exception) {
            // Do not let one SDK cleanup failure retain remaining resources.
            Log.w("NeuroTuneMuse", "cleanup_failed resource=$resource")
        }
    }

    private fun failStreams(message: String) {
        eegSink?.error("MUSE_DISCONNECTED", message, null)
        opticsSink?.error("MUSE_DISCONNECTED", message, null)
        eegSink = null
        opticsSink = null
    }

    private fun finishStart(code: String?, message: String?) {
        val result = startResult ?: return
        startResult = null
        if (code == null) result.success(null) else result.error(code, message, null)
    }

    private fun bluetoothEnabled(): Boolean {
        val manager = activity.getSystemService(BluetoothManager::class.java) ?: return false
        return manager.adapter?.isEnabled == true
    }

    private fun requiredPermissions(): Array<String> {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            arrayOf(Manifest.permission.BLUETOOTH_SCAN, Manifest.permission.BLUETOOTH_CONNECT)
        } else {
            arrayOf(Manifest.permission.ACCESS_FINE_LOCATION)
        }
    }

    private fun sinkHandler(assign: (EventChannel.EventSink?) -> Unit) =
        object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
                if (disposed) events.error("MUSE_DISPOSED", "Muse-anslutningen stängdes.", null)
                else assign(events)
            }
            override fun onCancel(arguments: Any?) = assign(null)
        }

    companion object {
        // Register/dispose run on the main thread; SDK callbacks may arrive elsewhere.
        @Volatile private var activeBridge: MuseBridge? = null
        private var contextConfigured = false
        const val REQUEST_PERMISSIONS = 0x4D55
        private const val SCAN_TIMEOUT_MS = 12_000L
        private const val SCAN_POLL_MS = 500L
        private const val CONNECT_TIMEOUT_MS = 20_000L
        private const val PERMISSION_TIMEOUT_MS = 120_000L
        private const val EEG_CHUNK = 128
        private const val OPTICS_CHUNK = 32
        private const val EEG_RATE_HZ = 256.0
        private const val OPTICS_RATE_HZ = 64.0
        private val EEG_CHANNELS = arrayOf(Eeg.EEG1, Eeg.EEG2, Eeg.EEG3, Eeg.EEG4)
        private val OPTICS_CHANNELS = arrayOf(Optics.OPTICS1, Optics.OPTICS2, Optics.OPTICS3, Optics.OPTICS4, Optics.OPTICS5, Optics.OPTICS6, Optics.OPTICS7, Optics.OPTICS8)
    }
}
