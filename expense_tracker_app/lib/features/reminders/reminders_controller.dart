import 'package:flutter/foundation.dart';

import '../../core/utils/notification_service.dart';
import '../../data/models/reminder.dart';
import '../../data/repositories/reminder_repository.dart';

/// General-purpose custom reminders — freeform, not tied to any bill/loan.
class RemindersController extends ChangeNotifier {
  final ReminderRepository _repo;

  RemindersController({ReminderRepository? repo})
    : _repo = repo ?? ReminderRepository();

  List<Reminder> _reminders = [];
  List<Reminder> get reminders => _reminders;

  Future<void> init() => refresh();

  Future<void> refresh() async {
    _reminders = await _repo.listAll();
    notifyListeners();
  }

  Future<void> add({
    required String title,
    String? note,
    required DateTime dateTime,
    ReminderRepeat repeat = ReminderRepeat.none,
  }) async {
    final reminder = Reminder(
      title: title,
      note: note,
      dateTime: dateTime,
      repeat: repeat,
    );
    final id = await _repo.add(reminder);
    await NotificationService.instance.scheduleReminder(
      id: id,
      title: title,
      body: note,
      dateTime: dateTime,
      repeat: repeat,
    );
    await refresh();
  }

  Future<void> update(Reminder reminder) async {
    await _repo.update(reminder);
    if (reminder.active) {
      await NotificationService.instance.scheduleReminder(
        id: reminder.id!,
        title: reminder.title,
        body: reminder.note,
        dateTime: reminder.dateTime,
        repeat: reminder.repeat,
      );
    } else {
      await NotificationService.instance.cancelReminder(reminder.id!);
    }
    await refresh();
  }

  Future<void> remove(int id) async {
    await _repo.remove(id);
    await NotificationService.instance.cancelReminder(id);
    await refresh();
  }

  Future<void> toggleActive(Reminder reminder, bool active) async {
    await update(reminder.copyWith(active: active));
  }
}
