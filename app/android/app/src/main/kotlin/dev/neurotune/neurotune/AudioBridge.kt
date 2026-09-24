package dev.neurotune.neurotune

import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioTrack
import android.media.MediaPlayer
import android.os.Handler
import android.os.HandlerThread
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.io.FileInputStream

/**
 * Stereo PCM playback. [latencyMs] is the AudioTrack buffer delay
 * (bufferSizeInFrames / sampleRate), an estimate of output latency,
 * not a measured delay at the ear.
 */
class AudioBridge(private val activity: FlutterActivity) {
    private val thread = HandlerThread("neurotune-pcm").also { it.start() }
    private val handler = Handler(thread.looper)
    private var track: AudioTrack? = null
    private var testPlayer: MediaPlayer? = null

    fun register(messenger: BinaryMessenger) {
        MethodChannel(messenger, "dev.neurotune/audio").setMethodCallHandler { call, result ->
            when (call.method) {
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
                "startTest" -> startTest(call.argument<String>("path"), result)
                "stopTest" -> {
                    handler.post {
                        stopTest()
                        activity.runOnUiThread { result.success(null) }
                    }
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
    }

    private fun start(rate: Int, result: MethodChannel.Result) {
        handler.post {
            stopTest()
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

    private fun startTest(path: String?, result: MethodChannel.Result) {
        handler.post {
            var player: MediaPlayer? = null
            try {
                require(path != null) { "Testljudfil saknas." }
                stopTest()
                stopTrack()
                val candidate = MediaPlayer()
                player = candidate
                candidate.setAudioAttributes(
                    AudioAttributes.Builder()
                        .setUsage(AudioAttributes.USAGE_MEDIA)
                        .setContentType(AudioAttributes.CONTENT_TYPE_MUSIC)
                        .build(),
                )
                FileInputStream(path).use { candidate.setDataSource(it.fd) }
                candidate.isLooping = true
                candidate.prepare()
                candidate.start()
                testPlayer = candidate
                activity.runOnUiThread { result.success(null) }
            } catch (error: Exception) {
                runCatching { player?.release() }
                activity.runOnUiThread {
                    result.error("STEREO_TEST_FAILED", error.message ?: "Testljudet kunde inte spelas upp.", null)
                }
            }
        }
    }

    private fun stopTest() {
        testPlayer?.release()
        testPlayer = null
    }

    private fun stopTrack() {
        track?.pause()
        track?.flush()
        track?.release()
        track = null
    }

}
