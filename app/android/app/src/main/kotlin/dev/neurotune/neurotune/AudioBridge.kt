package dev.neurotune.neurotune

import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioTrack
import android.media.MediaPlayer
import android.os.Handler
import android.os.HandlerThread
import android.os.SystemClock
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
    // Confined to the audio handler. Only one bounded packet may be pending.
    private var pendingWrite: PendingWrite? = null
    private var maxWriteBytes = 0
    private val drain = Runnable { drainWrite() }

    private class PendingWrite(val bytes: ByteArray, val result: MethodChannel.Result) {
        var offset = 0
        var lastProgressMs = SystemClock.elapsedRealtime()
    }

    fun register(messenger: BinaryMessenger) {
        MethodChannel(messenger, "dev.neurotune/audio").setMethodCallHandler { call, result ->
            when (call.method) {
                "start" -> start(call.argument<Int>("sampleRate") ?: 48000, result)
                "write" -> {
                    val bytes = call.arguments as ByteArray
                    handler.post { enqueueWrite(bytes, result) }
                }
                "stop" -> {
                    handler.post {
                        stopTrack()
                        activity.runOnUiThread { result.success(null) }
                    }
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
            try {
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
                    .setBufferSizeInBytes(maxOf(minBuffer, rate * BYTES_PER_FRAME * BUFFER_MS / 1000))
                    .setTransferMode(AudioTrack.MODE_STREAM)
                    .build()
                track = created
                created.play()
                maxWriteBytes = rate * BYTES_PER_FRAME / 5 // At most 200 ms.
                activity.runOnUiThread { result.success(null) }
            } catch (error: Exception) {
                runCatching { stopTrack() }
                activity.runOnUiThread { result.error("AUDIO_START_FAILED", error.message, null) }
            }
        }
    }

    private fun enqueueWrite(bytes: ByteArray, result: MethodChannel.Result) {
        val error = when {
            track == null -> "Audio output is stopped"
            bytes.size > maxWriteBytes || bytes.size % BYTES_PER_FRAME != 0 -> "Invalid PCM packet size"
            pendingWrite != null -> "Audio output already has a pending packet"
            else -> null
        }
        if (error != null) {
            activity.runOnUiThread { result.error("AUDIO_WRITE_FAILED", error, null) }
            return
        }
        pendingWrite = PendingWrite(bytes, result)
        drainWrite()
    }

    private fun drainWrite() {
        val pending = pendingWrite ?: return
        try {
            val current = checkNotNull(track)
            if (pending.offset < pending.bytes.size) {
                val written = current.write(
                    pending.bytes, pending.offset, pending.bytes.size - pending.offset,
                    AudioTrack.WRITE_NON_BLOCKING,
                )
                check(written >= 0) { "AudioTrack.write failed: $written" }
                if (written > 0) {
                    pending.offset += written
                    pending.lastProgressMs = SystemClock.elapsedRealtime()
                }
            }
            if (pending.offset == pending.bytes.size) {
                pendingWrite = null
                // Backpressure: acknowledge only after AudioTrack accepts the packet.
                activity.runOnUiThread { pending.result.success(null) }
            } else {
                check(SystemClock.elapsedRealtime() - pending.lastProgressMs < WRITE_STALL_MS) {
                    "Audio output stopped accepting PCM data"
                }
                // A full output buffer must not prevent stop/dispose from running.
                handler.postDelayed(drain, 10)
            }
        } catch (error: Exception) {
            pendingWrite = null
            activity.runOnUiThread { pending.result.error("AUDIO_WRITE_FAILED", error.message, null) }
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
        handler.removeCallbacks(drain)
        val pending = pendingWrite
        pendingWrite = null
        if (pending != null) {
            activity.runOnUiThread { pending.result.success(null) }
        }
        track?.pause()
        track?.flush()
        track?.release()
        track = null
    }

    /// Called when the Flutter engine goes away. Nothing will write or stop
    /// the track after that, so it is released here.
    fun dispose() {
        handler.removeCallbacksAndMessages(null)
        handler.post {
            stopTest()
            stopTrack()
        }
        thread.quitSafely()
    }

    private companion object {
        const val BYTES_PER_FRAME = 4
        const val WRITE_STALL_MS = 1000L

        /// Holds the controller's 150 ms lead plus one 50 ms write.
        const val BUFFER_MS = 250
    }
}
