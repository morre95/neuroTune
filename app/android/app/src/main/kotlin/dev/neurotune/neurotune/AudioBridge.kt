package dev.neurotune.neurotune

import android.content.Context
import android.media.AudioAttributes
import android.media.AudioDeviceCallback
import android.media.AudioDeviceInfo
import android.media.AudioFormat
import android.media.AudioManager
import android.media.AudioTrack
import android.os.Handler
import android.os.HandlerThread
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

/**
 * Stereo PCM playback. [latencyMs] is the AudioTrack buffer delay
 * (bufferSizeInFrames / sampleRate), an estimate of output latency,
 * not a measured delay at the ear.
 */
class AudioBridge(private val activity: FlutterActivity) : EventChannel.StreamHandler {
    private val thread = HandlerThread("neurotune-pcm").also { it.start() }
    private val handler = Handler(thread.looper)
    private var track: AudioTrack? = null
    private var events: EventChannel.EventSink? = null
    private val devices = object : AudioDeviceCallback() {
        override fun onAudioDevicesAdded(addedDevices: Array<out AudioDeviceInfo>) = emit()
        override fun onAudioDevicesRemoved(removedDevices: Array<out AudioDeviceInfo>) = emit()
    }

    fun register(messenger: BinaryMessenger) {
        MethodChannel(messenger, "dev.neurotune/audio").setMethodCallHandler { call, result ->
            when (call.method) {
                "hasStereoOutput" -> result.success(hasStereo())
                "start" -> start(call.argument<Int>("sampleRate") ?: 48000, result)
                "write" -> {
                    val bytes = call.arguments as ByteArray
                    handler.post { track?.write(bytes, 0, bytes.size) }
                    result.success(null)
                }
                "stop" -> {
                    handler.post { stopTrack() }
                    result.success(null)
                }
                "latencyMs" -> {
                    val current = track
                    if (current == null) {
                        result.success(null)
                    } else {
                        result.success(current.bufferSizeInFrames * 1000.0 / current.sampleRate)
                    }
                }
                else -> result.notImplemented()
            }
        }
        EventChannel(messenger, "dev.neurotune/audio_status").setStreamHandler(this)
    }

    private fun start(rate: Int, result: MethodChannel.Result) {
        handler.post {
            stopTrack()
            val minBuffer = AudioTrack.getMinBufferSize(rate, AudioFormat.CHANNEL_OUT_STEREO, AudioFormat.ENCODING_PCM_16BIT)
            val created = AudioTrack.Builder()
                .setAudioAttributes(
                    AudioAttributes.Builder()
                        .setUsage(AudioAttributes.USAGE_MEDIA)
                        .setContentType(AudioAttributes.CONTENT_TYPE_MUSIC)
                        .build(),
                )
                .setAudioFormat(
                    AudioFormat.Builder()
                        .setEncoding(AudioFormat.ENCODING_PCM_16BIT)
                        .setSampleRate(rate)
                        .setChannelMask(AudioFormat.CHANNEL_OUT_STEREO)
                        .build(),
                )
                .setBufferSizeInBytes(minBuffer * 2)
                .setTransferMode(AudioTrack.MODE_STREAM)
                .build()
            created.play()
            track = created
            activity.runOnUiThread { result.success(null) }
        }
    }

    private fun stopTrack() {
        track?.pause()
        track?.flush()
        track?.release()
        track = null
    }

    private fun hasStereo(): Boolean {
        val manager = activity.getSystemService(Context.AUDIO_SERVICE) as AudioManager
        return manager.getDevices(AudioManager.GET_DEVICES_OUTPUTS).any { device ->
            device.type == AudioDeviceInfo.TYPE_WIRED_HEADPHONES ||
                device.type == AudioDeviceInfo.TYPE_WIRED_HEADSET ||
                device.type == AudioDeviceInfo.TYPE_USB_HEADSET ||
                device.type == AudioDeviceInfo.TYPE_BLE_HEADSET ||
                device.type == AudioDeviceInfo.TYPE_BLUETOOTH_A2DP
        }
    }

    private fun emit() {
        events?.success(hasStereo())
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
        this.events = events
        val manager = activity.getSystemService(Context.AUDIO_SERVICE) as AudioManager
        manager.registerAudioDeviceCallback(devices, handler)
        emit()
    }

    override fun onCancel(arguments: Any?) {
        val manager = activity.getSystemService(Context.AUDIO_SERVICE) as AudioManager
        manager.unregisterAudioDeviceCallback(devices)
        events = null
    }
}

class MuseBridge {
    fun register(messenger: BinaryMessenger) {
        val message = "Hårdvaruläget är inte verifierat. Fysisk Muse S Athena och SDK krävs."
        MethodChannel(messenger, "dev.neurotune/muse").setMethodCallHandler { call, result ->
            when (call.method) {
                "start", "stop", "setNotch" -> result.error("HARDWARE_NOT_VERIFIED", message, null)
                else -> result.notImplemented()
            }
        }
        EventChannel(messenger, "dev.neurotune/muse_batches").setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
                    events.error("HARDWARE_NOT_VERIFIED", message, null)
                }

                override fun onCancel(arguments: Any?) = Unit
            },
        )
    }
}
