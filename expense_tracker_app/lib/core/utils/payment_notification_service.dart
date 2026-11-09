import 'dart:async';
import 'dart:io';

import 'package:notification_listener_service/notification_event.dart';
import 'package:notification_listener_service/notification_listener_service.dart';

/// Reads payment notifications from UPI apps and bank apps.
///
/// SMS misses a lot: UPI apps increasingly confirm a payment in-app and
/// never text you. Notifications close that gap — but notification access
/// is the broadest permission the app asks for, so this deliberately reads
/// only a fixed allowlist of payment apps. Everything else — chats, mail,
/// social — is dropped before it is even looked at, which is both the
/// privacy answer and the precision one.
class PaymentNotificationService {
  PaymentNotificationService._();
  static final PaymentNotificationService instance =
      PaymentNotificationService._();

  bool get isSupported => Platform.isAndroid;

  /// Package names whose notifications may be read. Anything not listed is
  /// ignored outright.
  static const paymentApps = <String, String>{
    'com.google.android.apps.nbu.paisa.user': 'Google Pay',
    'com.phonepe.app': 'PhonePe',
    'com.phonepe.simulator': 'PhonePe',
    'net.one97.paytm': 'Paytm',
    'in.org.npci.upiapp': 'BHIM',
    'in.amazon.mShop.android.shopping': 'Amazon Pay',
    'com.amazon.mShop.android.shopping': 'Amazon Pay',
    'com.dreamplug.androidapp': 'CRED',
    'money.jupiter.app': 'Jupiter',
    'com.fampay.in': 'FamPay',
    'com.freecharge.android': 'Freecharge',
    'com.mobikwik_new': 'MobiKwik',
    'com.snapwork.hdfc': 'HDFC Bank',
    'com.csam.icici.bank.imobile': 'ICICI Bank',
    'com.sbi.lotusintouch': 'SBI',
    'com.sbi.SBIFreedomPlus': 'SBI',
    'com.msf.kbank.mobile': 'Kotak',
    'com.axis.mobile': 'Axis Bank',
    'com.bankofbaroda.mconnect': 'Bank of Baroda',
    'com.idfcfirstbank.optimus': 'IDFC FIRST',
    'com.fss.pnbpsp': 'PNB',
    'com.canarabank.mobility': 'Canara Bank',
    'com.infrasofttech.indianbank': 'Indian Bank',
    'com.YESBANK': 'YES Bank',
    'com.rblbank.mobank': 'RBL Bank',
    // Play Store id of the slice app; com.slice.android is kept in case an
    // older build used it.
    'indwin.c3.shareapp': 'slice',
    'com.slice.android': 'slice',
  };

  static String? appName(String packageName) => paymentApps[packageName];

  Future<bool> isPermissionGranted() async {
    if (!isSupported) return false;
    try {
      return await NotificationListenerService.isPermissionGranted();
    } catch (_) {
      return false;
    }
  }

  /// Opens the system "Notification access" screen. Resolves true once the
  /// user has granted it there.
  Future<bool> requestPermission() async {
    if (!isSupported) return false;
    try {
      return await NotificationListenerService.requestPermission();
    } catch (_) {
      return false;
    }
  }

  /// Calls [onPayment] with the notification's text and the app it came
  /// from, for payment apps only.
  StreamSubscription<ServiceNotificationEvent>? listen(
    void Function(String body, String appName, DateTime postedAt) onPayment,
  ) {
    if (!isSupported) return null;
    try {
      return NotificationListenerService.notificationsStream.listen((event) {
        // A dismissal carries no new information, and an ongoing
        // notification is a progress bar rather than a completed payment.
        if (event.hasRemoved || event.onGoing) return;

        final name = appName(event.packageName);
        if (name == null) return;

        final body = [
          event.title,
          event.content,
        ].where((s) => s.trim().isNotEmpty).join('. ');
        if (body.trim().isEmpty) return;

        final posted = event.timestamp > 0
            ? DateTime.fromMillisecondsSinceEpoch(event.timestamp)
            : DateTime.now();
        onPayment(body, name, posted);
      }, onError: (_) {});
    } catch (_) {
      // The listener service can be unavailable on some OEM ROMs; SMS
      // import still covers those users.
      return null;
    }
  }
}
