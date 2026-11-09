package com.expensebot.expense_tracker_app

import com.expensebot.expense_tracker_app.guardian.GuardianChannel
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine

// local_auth's Android plugin requires a FragmentActivity host to show the
// biometric prompt — a plain FlutterActivity crashes when authenticate() is
// called.
class MainActivity : FlutterFragmentActivity() {
    private var guardian: GuardianChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        guardian = GuardianChannel(this).also {
            it.register(flutterEngine.dartExecutor.binaryMessenger)
        }
    }

    override fun onDestroy() {
        guardian?.dispose()
        guardian = null
        super.onDestroy()
    }
}
