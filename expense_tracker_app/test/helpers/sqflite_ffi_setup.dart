import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Routes sqflite through the FFI (pure-Dart sqlite3) backend so
/// DB-backed repositories can run in `flutter test` without a device.
/// Call once per test file, in a `setUpAll`.
void initFfiSqflite() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
}
