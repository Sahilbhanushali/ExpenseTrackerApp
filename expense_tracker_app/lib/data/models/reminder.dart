enum ReminderRepeat { none, daily, weekly, monthly }

ReminderRepeat reminderRepeatFromString(String value) => ReminderRepeat.values
    .firstWhere((r) => r.name == value, orElse: () => ReminderRepeat.none);

class Reminder {
  final int? id;
  final String title;
  final String? note;
  final DateTime dateTime;
  final ReminderRepeat repeat;
  final bool active;

  const Reminder({
    this.id,
    required this.title,
    this.note,
    required this.dateTime,
    this.repeat = ReminderRepeat.none,
    this.active = true,
  });

  Reminder copyWith({
    int? id,
    String? title,
    String? note,
    DateTime? dateTime,
    ReminderRepeat? repeat,
    bool? active,
  }) {
    return Reminder(
      id: id ?? this.id,
      title: title ?? this.title,
      note: note ?? this.note,
      dateTime: dateTime ?? this.dateTime,
      repeat: repeat ?? this.repeat,
      active: active ?? this.active,
    );
  }

  Map<String, Object?> toMap() {
    return {
      'id': id,
      'title': title,
      'note': note,
      'date_time': dateTime.toIso8601String(),
      'repeat': repeat.name,
      'active': active ? 1 : 0,
    };
  }

  factory Reminder.fromMap(Map<String, Object?> map) {
    return Reminder(
      id: map['id'] as int?,
      title: map['title'] as String,
      note: map['note'] as String?,
      dateTime: DateTime.parse(map['date_time'] as String),
      repeat: reminderRepeatFromString(map['repeat'] as String? ?? 'none'),
      active: (map['active'] as int? ?? 1) == 1,
    );
  }
}
