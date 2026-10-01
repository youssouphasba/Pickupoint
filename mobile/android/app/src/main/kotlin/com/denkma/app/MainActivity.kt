package com.denkma.app

import android.os.Bundle
import androidx.activity.enableEdgeToEdge
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterFragmentActivity() {
    private val phoneContactPicker = PhoneContactPicker(this)
    private var contactChannel: MethodChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.denkma.app/contact_picker")
        contactChannel = channel
        channel.setMethodCallHandler { call, result ->
                if (call.method == "pickPhone") phoneContactPicker.pick(result)
                else result.notImplemented()
            }
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        contactChannel?.setMethodCallHandler(null)
        contactChannel = null
        phoneContactPicker.dispose()
        super.cleanUpFlutterEngine(flutterEngine)
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        enableEdgeToEdge()
        super.onCreate(savedInstanceState)
    }

    override fun onDestroy() {
        phoneContactPicker.dispose()
        super.onDestroy()
    }
}
