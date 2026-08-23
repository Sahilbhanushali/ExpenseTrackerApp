import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

/// SQLite schema — 1:1 port of expense_bot/db.py's SCHEMA, minus the
/// Telegram-only chat_id column (single local user, no chat scoping needed).
class AppDatabase {
  static const _dbName = 'expenses.db';
  static const _dbVersion = 7;

  static const allTables = [
    'txns',
    'recurring',
    'accounts',
    'transfers',
    'wishlist',
    'goals',
    'loans',
  ];

  AppDatabase._([this._pathOverride]);
  static final AppDatabase instance = AppDatabase._();

  /// A fresh, isolated in-memory database — for tests only. Each call opens
  /// its own instance so tests never share state.
  factory AppDatabase.forTesting() => AppDatabase._(':memory:');

  final String? _pathOverride;
  Database? _db;

  Future<Database> get database async {
    _db ??= await _open();
    return _db!;
  }

  Future<Database> _open() async {
    final path = _pathOverride ?? join(await getDatabasesPath(), _dbName);
    return openDatabase(
      path,
      version: _dbVersion,
      onCreate: _createSchema,
      onUpgrade: _upgradeSchema,
      // sqflite caches same-path connections as one shared instance by
      // default — every AppDatabase.forTesting() call uses the same
      // ':memory:' path, so tests would otherwise silently share state.
      singleInstance: _pathOverride == null,
    );
  }

  Future<void> _upgradeSchema(
    Database db,
    int oldVersion,
    int newVersion,
  ) async {
    if (oldVersion < 2) {
      await _createWishlistTable(db);
    }
    if (oldVersion < 3) {
      await db.execute(
        "ALTER TABLE recurring ADD COLUMN type TEXT NOT NULL DEFAULT 'expense'",
      );
    }
    if (oldVersion < 4) {
      await db.execute('ALTER TABLE txns ADD COLUMN goal_id INTEGER');
      await _createGoalsTable(db);
    }
    if (oldVersion < 5) {
      await db.execute(
        "ALTER TABLE accounts ADD COLUMN type TEXT NOT NULL DEFAULT 'cash'",
      );
    }
    if (oldVersion < 6) {
      await db.execute('ALTER TABLE accounts ADD COLUMN current_value REAL');
    }
    if (oldVersion < 7) {
      await _createLoansTable(db);
    }
  }

  Future<void> _createLoansTable(Database db) async {
    await db.execute('''
      CREATE TABLE loans (
        id                  INTEGER PRIMARY KEY AUTOINCREMENT,
        name                TEXT NOT NULL,
        principal           REAL NOT NULL,
        interest_amount     REAL NOT NULL DEFAULT 0,
        emi_amount          REAL NOT NULL,
        tenure_months       INTEGER NOT NULL,
        installments_paid   INTEGER NOT NULL DEFAULT 0,
        start_date          TEXT NOT NULL,
        note                TEXT,
        account             TEXT,
        active              INTEGER NOT NULL DEFAULT 1
      )
    ''');
  }

  Future<void> _createWishlistTable(Database db) async {
    await db.execute('''
      CREATE TABLE wishlist (
        id            INTEGER PRIMARY KEY AUTOINCREMENT,
        name          TEXT NOT NULL,
        price         REAL NOT NULL,
        note          TEXT,
        purchased     INTEGER NOT NULL DEFAULT 0,
        created_at    TEXT NOT NULL,
        purchased_at  TEXT
      )
    ''');
  }

  Future<void> _createGoalsTable(Database db) async {
    await db.execute('''
      CREATE TABLE goals (
        id          INTEGER PRIMARY KEY AUTOINCREMENT,
        name        TEXT NOT NULL,
        target      REAL NOT NULL,
        note        TEXT,
        created_at  TEXT NOT NULL
      )
    ''');
  }

  Future<void> _createSchema(Database db, int version) async {
    await db.execute('''
      CREATE TABLE txns (
        id            INTEGER PRIMARY KEY AUTOINCREMENT,
        date          TEXT NOT NULL,
        category      TEXT NOT NULL,
        amount        REAL NOT NULL,
        note          TEXT,
        type          TEXT NOT NULL CHECK (type IN ('expense', 'income', 'lent', 'borrowed')),
        created_at    TEXT NOT NULL,
        counterparty  TEXT,
        settled       INTEGER,
        account       TEXT,
        goal_id       INTEGER
      )
    ''');

    await db.execute('''
      CREATE TABLE recurring (
        id                      INTEGER PRIMARY KEY AUTOINCREMENT,
        amount                  REAL NOT NULL,
        category                TEXT NOT NULL,
        note                    TEXT,
        day_of_month            INTEGER NOT NULL,
        last_run_month          TEXT,
        active                  INTEGER NOT NULL DEFAULT 1,
        installments_remaining  INTEGER,
        loan_id                 INTEGER,
        type                    TEXT NOT NULL DEFAULT 'expense'
      )
    ''');

    await db.execute('''
      CREATE TABLE accounts (
        id              INTEGER PRIMARY KEY AUTOINCREMENT,
        name            TEXT NOT NULL,
        opening_balance REAL NOT NULL DEFAULT 0,
        is_default      INTEGER NOT NULL DEFAULT 0,
        created_at      TEXT NOT NULL,
        type            TEXT NOT NULL DEFAULT 'cash',
        current_value   REAL
      )
    ''');

    await db.execute('''
      CREATE TABLE transfers (
        id            INTEGER PRIMARY KEY AUTOINCREMENT,
        from_account  TEXT NOT NULL,
        to_account    TEXT NOT NULL,
        amount        REAL NOT NULL,
        note          TEXT,
        date          TEXT NOT NULL,
        created_at    TEXT NOT NULL
      )
    ''');

    await db.execute('CREATE INDEX idx_txns_date ON txns(date)');
    await db.execute('CREATE INDEX idx_txns_category ON txns(category)');
    await db.execute('CREATE INDEX idx_txns_type ON txns(type)');

    await _createWishlistTable(db);
    await _createGoalsTable(db);
    await _createLoansTable(db);
  }

  /// Wipes every row from every table, in place — used by Settings' "Reset
  /// all data". Leaves the schema (and config.json, handled separately by
  /// ConfigRepository) untouched.
  Future<void> resetAll() async {
    final db = await database;
    await db.transaction((txn) async {
      for (final table in allTables) {
        await txn.delete(table);
      }
    });
  }
}
