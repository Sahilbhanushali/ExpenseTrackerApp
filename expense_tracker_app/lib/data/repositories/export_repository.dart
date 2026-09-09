import 'dart:io';

import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart' hide Transaction;

import '../../core/utils/money.dart';
import '../datasources/app_database.dart';
import '../models/transaction.dart';
import 'transaction_repository.dart';

/// Port of export.py's export_csv()/backup zip — CSV of transactions, and
/// sharing the raw SQLite + config files, replacing /export and /backup.
/// A restore that failed for a reason worth telling the user about.
class RestoreException implements Exception {
  final String message;
  const RestoreException(this.message);
  @override
  String toString() => message;
}

class ExportRepository {
  final TransactionRepository _txnRepo;
  ExportRepository([TransactionRepository? txnRepo])
    : _txnRepo = txnRepo ?? TransactionRepository();

  Future<File> exportCsv({String? month}) async {
    var rows = await _txnRepo.allRows();
    if (month != null) {
      rows = rows.where((r) => r.date.startsWith(month)).toList();
    }
    final buffer = StringBuffer('date,category,amount,note,type\n');
    for (final r in rows) {
      final note = (r.note ?? '').replaceAll(',', ';');
      // The CSV stays in rupees — it's opened in Excel by humans, so
      // "9737.39" is the useful representation, not "973739" paise.
      buffer.writeln(
        '${r.date},${r.category},'
        '${paiseToRupees(r.amountPaise).toStringAsFixed(2)},'
        '$note,${r.type.name}',
      );
    }

    final dir = await getTemporaryDirectory();
    final suffix = month ?? 'all';
    final file = File(join(dir.path, 'expenses_$suffix.csv'));
    await file.writeAsString(buffer.toString());
    return file;
  }

  /// Imports rows written by exportCsv() — "date,category,amount,note,type".
  /// Skips the header and any row that doesn't parse cleanly. Returns how
  /// many transactions were added.
  Future<int> importCsv(File file) async {
    final lines = await file.readAsLines();
    var imported = 0;
    for (final line in lines.skip(1)) {
      if (line.trim().isEmpty) continue;
      final fields = line.split(',');
      if (fields.length < 5) continue;

      final date = fields[0].trim();
      final category = fields[1].trim();
      final amountPaise = parseRupeesToPaise(fields[2].trim());
      final note = fields[3].trim();
      final typeStr = fields[4].trim();
      if (amountPaise == null || date.isEmpty || category.isEmpty) continue;

      TxnType? type;
      for (final t in TxnType.values) {
        if (t.name == typeStr) type = t;
      }
      if (type == null) continue;

      await _txnRepo.add(
        Transaction(
          date: date,
          category: category,
          amountPaise: amountPaise,
          note: note.isEmpty ? null : note,
          type: type,
          createdAt: DateTime.now().toIso8601String(),
        ),
      );
      imported++;
    }
    return imported;
  }

  Future<File> dbFilePath() async {
    final path = join(await getDatabasesPath(), AppDatabase.dbName);
    return File(path);
  }

  /// Replaces the live database with a previously exported one.
  ///
  /// A backup nobody can restore isn't a backup, which is what "share the
  /// .db file" amounted to on its own. The picked file is validated first,
  /// and the current database is kept aside until the swap succeeds, so a
  /// wrong file can't destroy the real data.
  ///
  /// Older backups are migrated on reopen, same as an app upgrade.
  /// Throws [RestoreException] with a message fit to show the user.
  Future<void> restoreFromFile(File backup) async {
    if (!await _looksLikeSpendoDatabase(backup)) {
      throw const RestoreException(
        "That file isn't a Spendo backup. Pick the expenses.db file you "
        'exported.',
      );
    }

    final live = await dbFilePath();
    final rollback = File('${live.path}.rollback');
    await AppDatabase.instance.close();

    if (await live.exists()) await live.copy(rollback.path);
    try {
      await backup.copy(live.path);
      // Forces a real open, so a corrupt file (or a failing migration) is
      // caught here, while the rollback copy still exists.
      final db = await AppDatabase.instance.database;
      await db.query('txns', limit: 1);
    } catch (_) {
      await AppDatabase.instance.close();
      if (await rollback.exists()) await rollback.copy(live.path);
      throw const RestoreException(
        "That backup couldn't be opened. Your existing data is unchanged.",
      );
    } finally {
      if (await rollback.exists()) await rollback.delete();
    }
  }

  /// Opens the candidate read-only and checks it carries our tables, so a
  /// random .db from another app can't be restored over real data.
  Future<bool> _looksLikeSpendoDatabase(File candidate) async {
    if (!await candidate.exists()) return false;
    Database? probe;
    try {
      probe = await openDatabase(candidate.path, readOnly: true);
      final rows = await probe.rawQuery(
        "SELECT name FROM sqlite_master WHERE type = 'table'",
      );
      final names = rows.map((r) => r['name'] as String).toSet();
      return names.contains('txns') && names.contains('accounts');
    } catch (_) {
      return false;
    } finally {
      await probe?.close();
    }
  }

  Future<File> configFilePath() async {
    final dir = await getApplicationDocumentsDirectory();
    return File(join(dir.path, 'config.json'));
  }
}
