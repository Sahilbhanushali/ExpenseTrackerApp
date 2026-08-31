import '../datasources/app_database.dart';
import '../models/reminder.dart';

class ReminderRepository {
  final AppDatabase _db;
  ReminderRepository([AppDatabase? db]) : _db = db ?? AppDatabase.instance;

  Future<int> add(Reminder reminder) async {
    final db = await _db.database;
    return db.insert('reminders', reminder.toMap()..remove('id'));
  }

  Future<void> update(Reminder reminder) async {
    final db = await _db.database;
    await db.update(
      'reminders',
      reminder.toMap()..remove('id'),
      where: 'id = ?',
      whereArgs: [reminder.id],
    );
  }

  Future<void> setActive(int id, bool active) async {
    final db = await _db.database;
    await db.update(
      'reminders',
      {'active': active ? 1 : 0},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> remove(int id) async {
    final db = await _db.database;
    await db.delete('reminders', where: 'id = ?', whereArgs: [id]);
  }

  Future<List<Reminder>> listAll() async {
    final db = await _db.database;
    final rows = await db.query('reminders', orderBy: 'date_time ASC');
    return rows.map(Reminder.fromMap).toList();
  }
}
