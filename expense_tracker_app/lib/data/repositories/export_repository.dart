import 'dart:io';

import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart' hide Transaction;

import '../models/transaction.dart';
import 'transaction_repository.dart';

/// Port of export.py's export_csv()/backup zip — CSV of transactions, and
/// sharing the raw SQLite + config files, replacing /export and /backup.
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
      buffer.writeln(
        '${r.date},${r.category},${r.amount},$note,${r.type.name}',
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
      final amount = double.tryParse(fields[2].trim());
      final note = fields[3].trim();
      final typeStr = fields[4].trim();
      if (amount == null || date.isEmpty || category.isEmpty) continue;

      TxnType? type;
      for (final t in TxnType.values) {
        if (t.name == typeStr) type = t;
      }
      if (type == null) continue;

      await _txnRepo.add(
        Transaction(
          date: date,
          category: category,
          amount: amount,
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
    final path = join(await getDatabasesPath(), 'expenses.db');
    return File(path);
  }

  Future<File> configFilePath() async {
    final dir = await getApplicationDocumentsDirectory();
    return File(join(dir.path, 'config.json'));
  }
}
