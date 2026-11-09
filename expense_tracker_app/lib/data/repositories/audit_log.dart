import 'dart:convert';

import 'package:sqflite/sqflite.dart';

/// Appends one entry to `audit_log`. Call it with the same executor as the
/// change itself (inside the same `db.transaction`) so the change and its
/// record are written together or not at all.
///
/// Records what changed, never why — and never anything beyond the row's
/// own columns.
Future<void> writeAudit(
  DatabaseExecutor ex, {
  required String entity,
  int? entityId,
  required String action,
  Map<String, Object?>? before,
  Map<String, Object?>? after,
}) async {
  await ex.insert('audit_log', {
    'entity': entity,
    'entity_id': entityId,
    'action': action,
    'before_json': before == null ? null : jsonEncode(before),
    'after_json': after == null ? null : jsonEncode(after),
    'at': DateTime.now().toIso8601String(),
  });
}
