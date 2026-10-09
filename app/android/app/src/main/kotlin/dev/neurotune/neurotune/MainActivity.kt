package dev.neurotune.neurotune

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    private var museBridge: MuseBridge? = null
    private var audioBridge: AudioBridge? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger
        audioBridge = AudioBridge(this).also { it.register(messenger) }
        SessionBridge(this).register(messenger)
        museBridge = MuseBridge(this).also { it.register(messenger) }
    }

    /// The session lives in the engine, so the playback and the foreground
    /// service it holds open end with it.
    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        museBridge?.dispose()
        museBridge = null
        audioBridge?.dispose()
        audioBridge = null
        SessionService.stop(this)
        super.cleanUpFlutterEngine(flutterEngine)
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == MuseBridge.REQUEST_PERMISSIONS) {
            museBridge?.onPermissions(grantResults)
        }
    }
}
