import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

/// Best-effort local reminders for recurring bills — there's no server-side
/// JobQueue like bot.py's, so this schedules a notification near each bill's
/// day-of-month in case the app isn't opened that day. Auto-logging itself
/// still happens on app launch/resume (see RecurringController.checkDue).
class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  final _plugin = FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  Future<void> init() async {
    if (_initialized) return;
    tzdata.initializeTimeZones();
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosInit = DarwinInitializationSettings();
    await _plugin.initialize(
      const InitializationSettings(android: androidInit, iOS: iosInit),
    );
    await _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.requestNotificationsPermission();
    _initialized = true;
  }

  Future<void> scheduleRecurringReminder({
    required int billId,
    required int dayOfMonth,
    required String title,
    required String body,
  }) async {
    if (!_initialized) return;
    final next = _nextOccurrence(dayOfMonth);
    try {
      await _plugin.zonedSchedule(
        billId,
        title,
        body,
        next,
        const NotificationDetails(
          android: AndroidNotificationDetails(
            'recurring_bills',
            'Recurring bills',
            importance: Importance.defaultImportance,
          ),
          iOS: DarwinNotificationDetails(),
        ),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        matchDateTimeComponents: DateTimeComponents.dayOfMonthAndTime,
      );
    } catch (_) {
      // Best-effort only — a failed schedule shouldn't block the bill itself.
    }
  }

  /// Fires immediately — used for budget-threshold alerts, which need to
  /// reach the user even if the app isn't open to show the in-app snackbar.
  Future<void> showNow({
    required int id,
    required String title,
    required String body,
  }) async {
    if (!_initialized) return;
    try {
      await _plugin.show(
        id,
        title,
        body,
        const NotificationDetails(
          android: AndroidNotificationDetails(
            'budget_alerts',
            'Budget alerts',
            importance: Importance.high,
          ),
          iOS: DarwinNotificationDetails(),
        ),
      );
    } catch (_) {
      // Best-effort only.
    }
  }

  Future<void> cancel(int billId) async {
    if (!_initialized) return;
    await _plugin.cancel(billId);
  }

  tz.TZDateTime _nextOccurrence(int dayOfMonth) {
    final now = tz.TZDateTime.now(tz.local);
    var scheduled = tz.TZDateTime(tz.local, now.year, now.month, dayOfMonth, 9);
    if (scheduled.isBefore(now)) {
      scheduled = tz.TZDateTime(
        tz.local,
        now.year,
        now.month + 1,
        dayOfMonth,
        9,
      );
    }
    return scheduled;
  }
}
