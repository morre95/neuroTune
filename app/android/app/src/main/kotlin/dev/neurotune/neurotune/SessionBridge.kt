package dev.neurotune.neurotune

import android.Manifest
import android.content.pm.PackageManager
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/// Starts and stops [SessionService] for the running session.
class SessionBridge(private val activity: FlutterActivity) {
    fun register(messenger: BinaryMessenger) {
        MethodChannel(messenger, "dev.neurotune/session").setMethodCallHandler { call, result ->
            when (call.method) {
                "start" -> {
                    requestNotifications()
                    SessionService.start(activity)
                    result.success(null)
                }
                "stop" -> {
                    SessionService.stop(activity)
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    /// The service runs whether or not this is granted; without it Android 13+
    /// only hides the ongoing notification, so the session does not wait for an
    /// answer.
    private fun requestNotifications() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) return
        if (activity.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) ==
            PackageManager.PERMISSION_GRANTED
        ) {
            return
        }
        activity.requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), REQUEST_NOTIFICATIONS)
    }

    companion object {
        const val REQUEST_NOTIFICATIONS = 0x4E4F
    }
}
