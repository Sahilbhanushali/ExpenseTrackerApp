package com.expensebot.expense_tracker_app

import io.flutter.embedding.android.FlutterFragmentActivity

// local_auth's Android plugin requires a FragmentActivity host to show the
// biometric prompt — a plain FlutterActivity crashes when authenticate() is
// called.
class MainActivity : FlutterFragmentActivity()
