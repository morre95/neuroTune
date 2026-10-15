package dev.neurotune.neurotune

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import android.os.PowerManager

/**
 * Keeps the process outside Android's background execution limits while a
 * session runs, so PCM playback and the Muse stream survive leaving the app and
 * the screen turning off. Playback itself stays in [AudioBridge]; this service
 * holds the notification and CPU wake lock for recording and streamed PCM.
 */
class SessionService : Service() {
    private var wakeLock: PowerManager.WakeLock? = null
    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        try {
            createChannel()
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
                startForeground(NOTIFICATION_ID, notification(), ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PLAYBACK)
            } else {
                startForeground(NOTIFICATION_ID, notification())
            }
            if (wakeLock == null) {
                wakeLock = (getSystemService(Context.POWER_SERVICE) as PowerManager)
                    .newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "neuroTune:session").apply {
                        setReferenceCounted(false)
                        acquire()
                    }
            }
            completeStarts(null)
        } catch (error: Exception) {
            completeStarts(error)
            stopSelf()
        }
        // The session lives in the Flutter isolate, so a restarted service would
        // have nothing to keep alive.
        return START_NOT_STICKY
    }

    override fun onDestroy() {
        completeStarts(IllegalStateException("Session service stopped"))
        val held = wakeLock
        wakeLock = null
        try { if (held?.isHeld == true) held.release() } finally { super.onDestroy() }
    }

    private fun createChannel() {
        val manager = getSystemService(NotificationManager::class.java)
        if (manager.getNotificationChannel(CHANNEL_ID) != null) return
        manager.createNotificationChannel(
            NotificationChannel(CHANNEL_ID, "Sessioner", NotificationManager.IMPORTANCE_LOW).apply {
                description = "Visas medan en neuroTune-session pågår."
                setShowBadge(false)
            },
        )
    }

    private fun notification(): Notification {
        val reopen = PendingIntent.getActivity(
            this,
            0,
            Intent(this, MainActivity::class.java),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        return Notification.Builder(this, CHANNEL_ID)
            .setContentTitle("neuroTune-session pågår")
            .setContentText("Ljud och mätning fortsätter i bakgrunden.")
            .setSmallIcon(android.R.drawable.ic_media_play)
            .setContentIntent(reopen)
            .setOngoing(true)
            .build()
    }

    companion object {
        private const val CHANNEL_ID = "neurotune-session"
        private const val NOTIFICATION_ID = 0x4E54

        private val pendingStarts = mutableListOf<(Exception?) -> Unit>()

        private fun completeStarts(error: Exception?) {
            val pending = pendingStarts.toList()
            pendingStarts.clear()
            pending.forEach { it(error) }
        }

        // Method-channel start joins the actual foreground/wake-lock acquisition,
        // needed before requesting focus from a background app on Android 15+.
        fun start(context: Context, ready: (Exception?) -> Unit) {
            pendingStarts.add(ready)
            try { context.startForegroundService(Intent(context, SessionService::class.java)) }
            catch (error: Exception) {
                pendingStarts.remove(ready)
                ready(error)
            }
        }

        fun stop(context: Context) {
            completeStarts(IllegalStateException("Session service start cancelled"))
            context.stopService(Intent(context, SessionService::class.java))
        }
    }
}
