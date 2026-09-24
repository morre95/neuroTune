package dev.neurotune.neurotune

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    private var museBridge: MuseBridge? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger
        AudioBridge(this).register(messenger)
        SessionBridge(this).register(messenger)
        museBridge = MuseBridge(this).also { it.register(messenger) }
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
