import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../../data/models/reminder.dart';

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
    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    await android?.requestNotificationsPermission();
    // Android 12+ requires this as a separate, explicit grant (unlike
    // POST_NOTIFICATIONS above) — without it, every zonedSchedule call below
    // silently falls back to an inexact alarm that the OS can delay by
    // several minutes, so custom reminders wouldn't fire "on time" as
    // promised. Declaring SCHEDULE_EXACT_ALARM in the manifest alone does
    // not grant this; the user must approve it once here.
    if (await android?.canScheduleExactNotifications() == false) {
      await android?.requestExactAlarmsPermission();
    }
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

  /// Asks for POST_NOTIFICATIONS (Android 13+). False if refused, so the
  /// caller can send the user to system settings instead.
  Future<bool> requestPermission() async {
    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    try {
      return await android?.requestNotificationsPermission() ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Drops every scheduled and shown notification — used by "Reset all
  /// data" so deleted bills and reminders don't keep firing.
  Future<void> cancelAll() async {
    if (!_initialized) return;
    await _plugin.cancelAll();
  }

  /// Calendar reminders live in ids 500000–599999 (see `reminderId`). This
  /// schedules [wanted] and cancels any reminder in that range that isn't
  /// wanted any more — so each obligation has at most one reminder, and
  /// paid or removed ones stop.
  Future<void> syncCalendarReminders(
    List<({int id, DateTime at, String title, String body})> wanted,
  ) async {
    if (!_initialized) return;
    final keep = {for (final w in wanted) w.id};
    try {
      for (final p in await _plugin.pendingNotificationRequests()) {
        if (p.id >= 500000 && p.id < 600000 && !keep.contains(p.id)) {
          await _plugin.cancel(p.id);
        }
      }
      for (final w in wanted) {
        await _plugin.zonedSchedule(
          w.id,
          w.title,
          w.body,
          tz.TZDateTime.from(w.at, tz.local),
          const NotificationDetails(
            android: AndroidNotificationDetails(
              'obligation_reminders',
              'Dues and income reminders',
              importance: Importance.high,
            ),
            iOS: DarwinNotificationDetails(),
          ),
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          uiLocalNotificationDateInterpretation:
              UILocalNotificationDateInterpretation.absoluteTime,
        );
      }
    } catch (_) {
      // Best-effort: a failed schedule shouldn't break the calendar.
    }
  }

  Future<void> cancel(int billId) async {
    if (!_initialized) return;
    await _plugin.cancel(billId);
  }

  /// Custom reminder notification ids are offset well clear of bill/loan
  /// autoincrement ids (both start from 1) so the two id spaces never clash.
  int _reminderNotificationId(int reminderId) => reminderId + 100000;

  Future<void> scheduleReminder({
    required int id,
    required String title,
    String? body,
    required DateTime dateTime,
    required ReminderRepeat repeat,
  }) async {
    if (!_initialized) return;
    final notifId = _reminderNotificationId(id);
    final scheduled = tz.TZDateTime.from(dateTime, tz.local);
    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        'custom_reminders',
        'Reminders',
        importance: Importance.high,
      ),
      iOS: DarwinNotificationDetails(),
    );
    final matchComponents = switch (repeat) {
      ReminderRepeat.none => null,
      ReminderRepeat.daily => DateTimeComponents.time,
      ReminderRepeat.weekly => DateTimeComponents.dayOfWeekAndTime,
      ReminderRepeat.monthly => DateTimeComponents.dayOfMonthAndTime,
    };
    try {
      await _plugin.zonedSchedule(
        notifId,
        title,
        body,
        scheduled,
        details,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        matchDateTimeComponents: matchComponents,
      );
    } catch (_) {
      // The exact-alarm permission requested in init() may still be denied
      // — fall back to an inexact schedule rather than dropping the
      // reminder outright (the OS may then delay delivery by several
      // minutes).
      try {
        await _plugin.zonedSchedule(
          notifId,
          title,
          body,
          scheduled,
          details,
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          uiLocalNotificationDateInterpretation:
              UILocalNotificationDateInterpretation.absoluteTime,
          matchDateTimeComponents: matchComponents,
        );
      } catch (_) {
        // Best-effort only — a failed schedule shouldn't block saving the
        // reminder itself.
      }
    }
  }

  Future<void> cancelReminder(int id) async {
    if (!_initialized) return;
    await _plugin.cancel(_reminderNotificationId(id));
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
