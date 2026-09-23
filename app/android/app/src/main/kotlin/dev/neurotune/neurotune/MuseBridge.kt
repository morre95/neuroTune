package dev.neurotune.neurotune

import android.Manifest
import android.bluetooth.BluetoothManager
import android.content.pm.PackageManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import com.choosemuse.libmuse.Accelerometer
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
class MuseBridge(private val activity: FlutterActivity) {
    private val handler = Handler(Looper.getMainLooper())
    private val manager = MuseManagerAndroid.getInstance()
    private var muse: Muse? = null
    private var startResult: MethodChannel.Result? = null
    private var eegSink: EventChannel.EventSink? = null
    private var opticsSink: EventChannel.EventSink? = null
    private var originUs: Long? = null
    private val eeg = Array(4) { ArrayList<Double>() }
    private val accel = ArrayList<List<Double>>()
    private val gyro = ArrayList<List<Double>>()
    private val contact = ArrayList<List<Int>>()
    private var eegStart = 0.0
    private val lastAccel = doubleArrayOf(0.0, 0.0, 1.0)
    private val lastGyro = doubleArrayOf(0.0, 0.0, 0.0)
    private val lastContact = intArrayOf(1, 1, 1, 1)
    private val optics = arrayOf(ArrayList<Double>(), ArrayList<Double>())
    private var opticsStart = 0.0
    private var scanning = false

    fun register(messenger: BinaryMessenger) {
        manager.setContext(activity)
        MethodChannel(messenger, "dev.neurotune/muse").setMethodCallHandler { call, result ->
            when (call.method) {
                "start" -> start(result)
                "stop" -> {
                    stop()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
        EventChannel(messenger, "dev.neurotune/muse_eeg").setStreamHandler(sinkHandler { eegSink = it })
        EventChannel(messenger, "dev.neurotune/muse_optics").setStreamHandler(sinkHandler { opticsSink = it })
    }

    fun onPermissions(grantResults: IntArray) {
        val granted = grantResults.isNotEmpty() && grantResults.all { it == PackageManager.PERMISSION_GRANTED }
        if (!granted) {
            finishStart("BLUETOOTH_DENIED", "Bluetooth-behörighet saknas.")
            return
        }
        beginScan()
    }

    private fun start(result: MethodChannel.Result) {
        if (startResult != null) {
            result.error("MUSE_BUSY", "En anslutning pågår redan.", null)
            return
        }
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
            activity.requestPermissions(permissions, REQUEST_PERMISSIONS)
            return
        }
        beginScan()
    }

    private fun beginScan() {
        scanning = true
        manager.stopListening()
        manager.setMuseListener(object : MuseListener() {
            override fun museListChanged() {
                handler.post { onMuses() }
            }
        })
        manager.startListening()
        handler.postDelayed(scanTimeout, SCAN_TIMEOUT_MS)
    }

    private val scanTimeout = Runnable {
        if (startResult != null) {
            manager.stopListening()
            finishStart("MUSE_NOT_FOUND", "Ingen Muse S Athena hittades.")
        }
    }

    private fun onMuses() {
        if (!scanning || startResult == null) return
        val found = manager.muses.firstOrNull { it.model == MuseModel.MS_03 } ?: return
        scanning = false
        handler.removeCallbacks(scanTimeout)
        manager.stopListening()
        connect(found)
    }

    private fun connect(headband: Muse) {
        muse = headband
        headband.unregisterAllListeners()
        headband.registerConnectionListener(object : MuseConnectionListener() {
            override fun receiveMuseConnectionPacket(packet: MuseConnectionPacket, muse: Muse) {
                handler.post { onConnection(packet) }
            }
        })
        val listener = dataListener()
        headband.registerDataListener(listener, MuseDataPacketType.EEG)
        headband.registerDataListener(listener, MuseDataPacketType.ACCELEROMETER)
        headband.registerDataListener(listener, MuseDataPacketType.GYRO)
        headband.registerDataListener(listener, MuseDataPacketType.HSI_PRECISION)
        headband.registerDataListener(listener, MuseDataPacketType.OPTICS)
        headband.setPreset(MusePreset.PRESET_1034)
        headband.runAsynchronously()
    }

    private fun onConnection(packet: MuseConnectionPacket) {
        when (packet.currentConnectionState) {
            ConnectionState.CONNECTED -> finishStart(null, null)
            ConnectionState.DISCONNECTED -> {
                if (startResult != null) {
                    finishStart("MUSE_DISCONNECTED", "Muse kopplades från innan sessionen började.")
                } else {
                    failStreams("Muse kopplades från.")
                }
            }
            ConnectionState.NEEDS_LICENSE ->
                finishStart("MUSE_LICENSE", "LibMuse kräver en licens för det här headsetet.")
            else -> Unit
        }
    }

    private fun dataListener(): MuseDataListener {
        return object : MuseDataListener() {
            override fun receiveMuseArtifactPacket(packet: MuseArtifactPacket, muse: Muse) = Unit

            override fun receiveMuseDataPacket(packet: MuseDataPacket, muse: Muse) {
                when (packet.packetType()) {
                    MuseDataPacketType.EEG -> {
                        val values = DoubleArray(4) { index ->
                            packet.getEegChannelValue(EEG_CHANNELS[index])
                        }
                        val time = packet.timestamp()
                        handler.post { addEeg(time, values) }
                    }
                    MuseDataPacketType.ACCELEROMETER -> {
                        val values = doubleArrayOf(
                            packet.getAccelerometerValue(Accelerometer.X),
                            packet.getAccelerometerValue(Accelerometer.Y),
                            packet.getAccelerometerValue(Accelerometer.Z),
                        )
                        handler.post { values.copyInto(lastAccel) }
                    }
                    MuseDataPacketType.GYRO -> {
                        val values = doubleArrayOf(
                            packet.getGyroValue(Gyro.X),
                            packet.getGyroValue(Gyro.Y),
                            packet.getGyroValue(Gyro.Z),
                        )
                        handler.post { values.copyInto(lastGyro) }
                    }
                    MuseDataPacketType.HSI_PRECISION -> {
                        val values = IntArray(4) { index ->
                            packet.getEegChannelValue(EEG_CHANNELS[index]).toInt()
                        }
                        handler.post { values.copyInto(lastContact) }
                    }
                    MuseDataPacketType.OPTICS -> {
                        val left = packet.getOpticsChannelValue(Optics.OPTICS3)
                        val right = packet.getOpticsChannelValue(Optics.OPTICS4)
                        val time = packet.timestamp()
                        handler.post { addOptics(time, left, right) }
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

    private fun addOptics(timestampUs: Long, left: Double, right: Double) {
        val seconds = sessionSeconds(timestampUs)
        if (optics[0].isEmpty()) opticsStart = seconds
        optics[0].add(left)
        optics[1].add(right)
        if (optics[0].size >= OPTICS_CHUNK) emitOptics()
    }

    private fun emitOptics() {
        val sink = opticsSink ?: return clearOptics()
        sink.success(
            mapOf(
                "channel_names" to listOf("OPTICS3", "OPTICS4"),
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
        scanning = false
        handler.removeCallbacks(scanTimeout)
        manager.stopListening()
        muse?.disconnect()
        muse = null
        clearEeg()
        clearOptics()
        originUs = null
        finishStart("MUSE_STOPPED", "Anslutningen avbröts.")
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
            override fun onListen(arguments: Any?, events: EventChannel.EventSink) = assign(events)
            override fun onCancel(arguments: Any?) = assign(null)
        }

    companion object {
        const val REQUEST_PERMISSIONS = 0x4D55
        private const val SCAN_TIMEOUT_MS = 12_000L
        private const val EEG_CHUNK = 128
        private const val OPTICS_CHUNK = 32
        private const val EEG_RATE_HZ = 256.0
        private const val OPTICS_RATE_HZ = 64.0
        private val EEG_CHANNELS = arrayOf(Eeg.EEG1, Eeg.EEG2, Eeg.EEG3, Eeg.EEG4)
    }
}
