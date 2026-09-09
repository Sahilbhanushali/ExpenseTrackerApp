import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:expense_tracker_app/data/repositories/export_repository.dart';

import 'helpers/sqflite_ffi_setup.dart';

/// Restore overwrites every transaction the user has. The failure modes that
/// matter are "restored the wrong file" and "restored a broken file and lost
/// everything", so both get a test.
void main() {
  setUpAll(initFfiSqflite);

  late Directory tmp;
  late ExportRepository repo;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('spendo_restore');
    databaseFactory.setDatabasesPath(tmp.path);
    repo = ExportRepository();
  });

  tearDown(() => tmp.delete(recursive: true));

  /// Writes a file that is not a Spendo database.
  Future<File> junkFile() async {
    final file = File('${tmp.path}/notes.txt');
    await file.writeAsString('this is not a database');
    return file;
  }

  test('a file that is not a Spendo backup is refused', () async {
    final junk = await junkFile();
    expect(() => repo.restoreFromFile(junk), throwsA(isA<RestoreException>()));
  });

  test('a missing file is refused rather than wiping the database', () async {
    expect(
      () => repo.restoreFromFile(File('${tmp.path}/nope.db')),
      throwsA(isA<RestoreException>()),
    );
  });

  test('a refused restore leaves the live database untouched', () async {
    // Seed the live database, then try to restore junk over it.
    final live = await repo.dbFilePath();
    final seeded = await openDatabase(
      live.path,
      version: 1,
      onCreate: (db, _) async {
        await db.execute('CREATE TABLE txns (id INTEGER PRIMARY KEY)');
        await db.execute('CREATE TABLE accounts (id INTEGER PRIMARY KEY)');
        await db.insert('txns', {'id': 7});
      },
    );
    await seeded.close();

    final junk = await junkFile();
    await expectLater(
      () => repo.restoreFromFile(junk),
      throwsA(isA<RestoreException>()),
    );

    final after = await openDatabase(live.path, readOnly: true);
    expect((await after.query('txns')).single['id'], 7);
    await after.close();
  });
}
