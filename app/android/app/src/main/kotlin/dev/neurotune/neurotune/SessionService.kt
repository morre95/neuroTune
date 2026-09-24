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

/**
 * Keeps the process outside Android's background execution limits while a
 * session runs, so PCM playback and the Muse stream survive leaving the app and
 * the screen turning off. Playback itself stays in [AudioBridge]; this service
 * only holds the foreground notification that buys the process that exemption.
 */
class SessionService : Service() {
    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        createChannel()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            startForeground(NOTIFICATION_ID, notification(), ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PLAYBACK)
        } else {
            startForeground(NOTIFICATION_ID, notification())
        }
        // The session lives in the Flutter isolate, so a restarted service would
        // have nothing to keep alive.
        return START_NOT_STICKY
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

        fun start(context: Context) {
            context.startForegroundService(Intent(context, SessionService::class.java))
        }

        fun stop(context: Context) {
            context.stopService(Intent(context, SessionService::class.java))
        }
    }
}
