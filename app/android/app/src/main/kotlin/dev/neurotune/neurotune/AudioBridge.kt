package dev.neurotune.neurotune

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.ApplicationInfo
import android.media.AudioFocusRequest
import android.media.AudioManager
import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioTrack
import android.media.MediaPlayer
import android.os.Build
import android.os.Handler
import android.os.HandlerThread
import android.os.SystemClock
import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.EventChannel
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
    private val audioManager = activity.getSystemService(Context.AUDIO_SERVICE) as AudioManager
    private var focusRequest: AudioFocusRequest? = null
    private var legacyFocusListener: AudioManager.OnAudioFocusChangeListener? = null
    @Volatile private var focusEpoch = 0
    private var pausedHead = 0L
    private var eventSink: EventChannel.EventSink? = null
    private val noisyReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            if (intent?.action == AudioManager.ACTION_AUDIO_BECOMING_NOISY) {
                handler.post { if (track != null) interruptOutput("route_noisy") }
            }
        }
    }
    private var noisyRegistered = false
    private var testPlayer: MediaPlayer? = null
    // Confined to the audio handler. Only one bounded packet may be pending.
    private var pendingWrite: PendingWrite? = null
    private var maxWriteBytes = 0
    private val drain = Runnable { drainWrite() }
    private val debugAudio = activity.applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE != 0
    private var acceptedBytes = 0L
    private var outputStartedMs = 0L
    private var lastDebugMs = 0L
    private var lastDebugThreshold = -1

    private fun startupThreshold(current: AudioTrack?): Int = when {
        current == null -> 0
        Build.VERSION.SDK_INT >= 31 -> current.startThresholdInFrames
        Build.VERSION.SDK_INT >= 24 -> current.bufferCapacityInFrames
        else -> current.bufferSizeInFrames
    }

    // Counter-only debug diagnostics: no PCM, EEG, profile or account data.
    // Calls are confined to the PCM handler and periodic samples are throttled.
    private fun logOutput(event: String, force: Boolean = false) {
        if (!debugAudio) return
        val now = SystemClock.elapsedRealtime()
        if (!force && now - lastDebugMs < 1000) return
        lastDebugMs = now
        val current = track
        val head = current?.playbackHeadPosition?.toLong()?.and(0xffffffffL) ?: pausedHead
        val capacity = if (current != null && Build.VERSION.SDK_INT >= 24) current.bufferCapacityInFrames else current?.bufferSizeInFrames
        Log.d("NeuroTunePcm", "event=$event elapsedMs=${now - outputStartedMs} " +
            "acceptedBytes=$acceptedBytes queuedBytes=${acceptedBytes - head * BYTES_PER_FRAME} " +
            "headFrames=$head thresholdFrames=${startupThreshold(current)} " +
            "capacityFrames=$capacity bufferFrames=${current?.bufferSizeInFrames} " +
            "playState=${current?.playState} state=${current?.state} " +
            "underruns=${if (current != null && Build.VERSION.SDK_INT >= 24) current.underrunCount else null} " +
            "pendingBytes=${pendingWrite?.let { it.bytes.size - it.offset } ?: 0}")
    }

    private class PendingWrite(val bytes: ByteArray, val result: MethodChannel.Result) {
        var offset = 0
        var lastProgressMs = SystemClock.elapsedRealtime()
    }

    fun register(messenger: BinaryMessenger) {
        EventChannel(messenger, "dev.neurotune/audio_events").setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink) { eventSink = events }
                override fun onCancel(arguments: Any?) { eventSink = null }
            },
        )
        if (Build.VERSION.SDK_INT >= 33) {
            activity.registerReceiver(noisyReceiver, IntentFilter(AudioManager.ACTION_AUDIO_BECOMING_NOISY), Context.RECEIVER_NOT_EXPORTED)
        } else {
            @Suppress("DEPRECATION")
            activity.registerReceiver(noisyReceiver, IntentFilter(AudioManager.ACTION_AUDIO_BECOMING_NOISY))
        }
        noisyRegistered = true
        MethodChannel(messenger, "dev.neurotune/audio").setMethodCallHandler { call, result ->
            when (call.method) {
                "start" -> start(call.argument<Int>("sampleRate") ?: 48000, result)
                "write" -> {
                    val bytes = call.arguments as ByteArray
                    handler.post { enqueueWrite(bytes, result) }
                }
                "pauseAndCheckpoint" -> {
                    handler.post {
                        try {
                            val frames = pauseTrack()
                            activity.runOnUiThread { result.success(frames) }
                        } catch (error: Exception) {
                            activity.runOnUiThread { result.error("AUDIO_PAUSE_FAILED", error.message, null) }
                        }
                    }
                }
                "stop" -> {
                    handler.post {
                        try {
                            stopTrack()
                            activity.runOnUiThread { result.success(null) }
                        } catch (error: Exception) {
                            activity.runOnUiThread { result.error("AUDIO_STOP_FAILED", error.message, null) }
                        }
                    }
                }
                "startTest" -> startTest(call.argument<String>("path"), result)
                "stopTest" -> {
                    handler.post {
                        stopTest()
                        activity.runOnUiThread { result.success(null) }
                    }
                }
                "playedFrames" -> {
                    handler.post {
                        // Unsigned frame counter; a ten-minute stream cannot wrap.
                        val frames = track?.playbackHeadPosition?.toLong()?.and(0xffffffffL) ?: pausedHead
                        logOutput("head")
                        activity.runOnUiThread {
                            result.success(frames)
                        }
                    }
                }
                "startupThresholdFrames" -> {
                    handler.post {
                        val current = track
                        // Before API 31 the threshold is not configurable or
                        // observable; filling capacity safely primes the sink.
                        val frames = startupThreshold(current)
                        if (frames != lastDebugThreshold) {
                            lastDebugThreshold = frames
                            logOutput("threshold_changed", force = true)
                        }
                        activity.runOnUiThread { result.success(frames) }
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
                if (!requestFocus()) {
                    abandonFocus()
                    activity.runOnUiThread { result.error("AUDIO_FOCUS_DENIED", "Audio focus is unavailable", null) }
                    return@post
                }
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
                acceptedBytes = 0
                outputStartedMs = SystemClock.elapsedRealtime()
                lastDebugMs = 0
                lastDebugThreshold = -1
                created.play()
                logOutput("start", force = true)
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
                    acceptedBytes += written
                    logOutput("write", force = acceptedBytes == written.toLong())
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
            logOutput("write_failed", force = true)
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

    /** Confined to the audio handler: freeze the played head before flush.
     * Retain focus while paused so a transient loss can deliver a gain event. */
    private fun pauseTrack(): Long {
        handler.removeCallbacks(drain)
        val current = track
        logOutput("pause", force = true)
        track = null
        val pending = pendingWrite
        pendingWrite = null
        try {
            if (current != null) {
                current.pause()
                pausedHead = current.playbackHeadPosition.toLong().and(0xffffffffL)
            }
            return pausedHead
        } finally {
            if (pending != null) activity.runOnUiThread { pending.result.success(null) }
            if (current != null) {
                try { current.flush() } finally { current.release() }
            }
        }
    }

    private fun stopTrack() {
        try { pauseTrack() } finally {
            pausedHead = 0L
            abandonFocus()
        }
    }

    private fun emit(reason: String, available: Boolean) {
        val epoch = focusEpoch
        activity.runOnUiThread {
            if (epoch != focusEpoch) return@runOnUiThread
            eventSink?.success(mapOf("reason" to reason, "available" to available))
        }
    }

    private fun interruptOutput(reason: String) {
        try {
            pauseTrack()
            emit(reason, false)
        } catch (error: Exception) {
            activity.runOnUiThread { eventSink?.error("AUDIO_PAUSE_FAILED", error.message, null) }
        }
    }

    @Suppress("DEPRECATION")
    private fun requestFocus(): Boolean {
        val epoch = ++focusEpoch
        val listener = AudioManager.OnAudioFocusChangeListener { change ->
            // Ignore delayed callbacks belonging to a released output.
            handler.post {
                if (epoch == focusEpoch) {
                    when (change) {
                        AudioManager.AUDIOFOCUS_GAIN -> emit("focus_gain", true)
                        AudioManager.AUDIOFOCUS_LOSS -> interruptOutput("focus_loss")
                        AudioManager.AUDIOFOCUS_LOSS_TRANSIENT -> interruptOutput("focus_loss_transient")
                        AudioManager.AUDIOFOCUS_LOSS_TRANSIENT_CAN_DUCK -> interruptOutput("focus_loss_duck")
                    }
                }
            }
        }
        val result = if (Build.VERSION.SDK_INT >= 26) {
            val request = AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN)
                .setAudioAttributes(AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_MEDIA)
                    .setContentType(AudioAttributes.CONTENT_TYPE_MUSIC).build())
                .setWillPauseWhenDucked(true)
                .setOnAudioFocusChangeListener(listener, handler)
                .build()
            focusRequest = request
            audioManager.requestAudioFocus(request)
        } else {
            legacyFocusListener = listener
            audioManager.requestAudioFocus(listener, AudioManager.STREAM_MUSIC, AudioManager.AUDIOFOCUS_GAIN)
        }
        return result == AudioManager.AUDIOFOCUS_REQUEST_GRANTED
    }

    @Suppress("DEPRECATION")
    private fun abandonFocus() {
        ++focusEpoch
        val request = focusRequest
        focusRequest = null
        val listener = legacyFocusListener
        legacyFocusListener = null
        if (Build.VERSION.SDK_INT >= 26 && request != null) audioManager.abandonAudioFocusRequest(request)
        else if (listener != null) audioManager.abandonAudioFocus(listener)
    }

    /// Called when the Flutter engine goes away. Nothing will write or stop
    /// the track after that, so it is released here.
    fun dispose() {
        eventSink = null
        if (noisyRegistered) {
            activity.unregisterReceiver(noisyReceiver)
            noisyRegistered = false
        }
        handler.removeCallbacksAndMessages(null)
        handler.post {
            try { stopTest() } finally { runCatching { stopTrack() } }
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
