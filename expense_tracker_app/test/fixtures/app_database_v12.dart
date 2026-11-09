// Frozen copy of lib/data/datasources/app_database.dart at schema v12
// (commit e8c1866). Used only to build a genuine v12 database for the
// full upgrade test. Do not edit.
// ignore_for_file: type=lint, unused_field
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

/// Which table `loan_payments.loan_id` points at. Person-to-person loans
/// live in `txns`, EMI loans live in `loans` — two separate id sequences,
/// so a payment row is meaningless without knowing which one it belongs to.
abstract final class _LoanPaymentOwnerV12 {
  static const personLoan = 'person_loan';
  static const emiLoan = 'emi_loan';
}

/// SQLite schema — 1:1 port of expense_bot/db.py's SCHEMA, minus the
/// Telegram-only chat_id column (single local user, no chat scoping needed).
class AppDatabaseV12 {
  static const dbName = 'expenses.db';
  static const _dbVersion = 12;

  static const allTables = [
    'txns',
    'recurring',
    'accounts',
    'transfers',
    'wishlist',
    'goals',
    'loans',
    'loan_payments',
    'reminders',
    'pending_txns',
  ];

  AppDatabaseV12._([this._pathOverride]);
  static final AppDatabaseV12 instance = AppDatabaseV12._();

  /// A fresh, isolated database — for tests only. Each call opens its own
  /// instance so tests never share state. Pass a file [path] when a test
  /// needs the database to survive being closed and reopened (migrations).
  factory AppDatabaseV12.forTesting([String path = ':memory:']) =>
      AppDatabaseV12._(path);

  /// Closes the underlying connection so the same file can be reopened.
  Future<void> close() async {
    await _db?.close();
    _db = null;
  }

  final String? _pathOverride;
  Database? _db;

  Future<Database> get database async {
    _db ??= await _open();
    return _db!;
  }

  Future<Database> _open() async {
    final path = _pathOverride ?? join(await getDatabasesPath(), dbName);
    return openDatabase(
      path,
      version: _dbVersion,
      onCreate: _createSchema,
      onUpgrade: _upgradeSchema,
      // sqflite caches same-path connections as one shared instance by
      // default — every AppDatabaseV12.forTesting() call uses the same
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
    if (oldVersion < 8) {
      await _createLoanPaymentsTable(db);
      await _createRemindersTable(db);
    }
    if (oldVersion < 9) {
      await db.execute(
        "ALTER TABLE txns ADD COLUMN source TEXT NOT NULL DEFAULT 'manual'",
      );
      await db.execute('ALTER TABLE txns ADD COLUMN external_ref TEXT');
      await db.execute(
        'CREATE INDEX idx_txns_external_ref ON txns(external_ref)',
      );
      await _createPendingTxnsTable(db);
    }
    if (oldVersion < 10) {
      // Links an EMI installment expense back to its loan, so deleting or
      // undoing that expense can also roll back the loan's paid count
      // instead of leaving the two silently out of step.
      await db.execute('ALTER TABLE txns ADD COLUMN loan_id INTEGER');
      await db.execute('CREATE INDEX idx_txns_loan_id ON txns(loan_id)');

      // loan_payments previously keyed on a bare id that meant "txns.id"
      // for person-to-person loans but would have meant "loans.id" for
      // EMIs — two different tables sharing one id space. Existing rows are
      // all person-loan repayments (EMIs never wrote history), so they're
      // tagged as such.
      await db.execute(
        "ALTER TABLE loan_payments ADD COLUMN owner_type TEXT NOT NULL "
        "DEFAULT '${_LoanPaymentOwnerV12.personLoan}'",
      );
      await db.execute(
        'CREATE INDEX idx_loan_payments_owner '
        'ON loan_payments(owner_type, loan_id)',
      );

      // Account names are the join key used by txns.account and
      // transfers.from/to_account, so duplicates would make balances
      // ambiguous. Enforced in the schema, not just in the controller.
      //
      // Any pre-existing duplicate would make CREATE UNIQUE INDEX throw
      // during open — i.e. an app that won't start — so they're renamed
      // first rather than gambling on the data being clean.
      await _deduplicateAccountNames(db);
      await db.execute(
        'CREATE UNIQUE INDEX idx_accounts_name ON accounts(name)',
      );
    }
    if (oldVersion < 11) {
      await _convertAmountsToPaise(db);
    }
    if (oldVersion < 12) {
      await _createAccountIndexes(db);
    }
  }

  /// Balances and per-account history filter on these on every refresh.
  static Future<void> _createAccountIndexes(Database db) async {
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_txns_account ON txns(account)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_transfers_from ON transfers(from_account)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_transfers_to ON transfers(to_account)',
    );
  }

  /// Every money column moves from rupees-as-REAL to integer paise.
  ///
  /// Doubles can't hold 0.10 exactly, so totals drift as rows accumulate,
  /// and the app compounded that by rounding paise away on display — a
  /// ₹9,737.39 EMI rendered as "₹9,737". Values are rounded once, here, and
  /// are exact from then on.
  ///
  /// SQLite is dynamically typed, so an in-place UPDATE genuinely stores
  /// integers; rebuilding ten tables just to change the declared affinity
  /// would risk far more than it buys.
  Future<void> _convertAmountsToPaise(Database db) async {
    const columnsByTable = <String, List<String>>{
      'txns': ['amount'],
      'recurring': ['amount'],
      'accounts': ['opening_balance', 'current_value'],
      'transfers': ['amount'],
      'wishlist': ['price'],
      'goals': ['target'],
      'loans': ['principal', 'interest_amount', 'emi_amount'],
      'loan_payments': ['amount'],
      'pending_txns': ['amount'],
    };

    await db.transaction((txn) async {
      for (final entry in columnsByTable.entries) {
        for (final column in entry.value) {
          // NULL stays NULL (e.g. accounts.current_value is optional).
          await txn.execute(
            'UPDATE ${entry.key} SET $column = '
            'CAST(ROUND($column * 100) AS INTEGER) '
            'WHERE $column IS NOT NULL',
          );
        }
      }
    });
  }

  /// Renames duplicate account names ("Cash" → "Cash (2)") and repoints the
  /// rows that referenced them, so a unique index can be applied safely.
  /// Keeps the oldest row's name untouched.
  Future<void> _deduplicateAccountNames(Database db) async {
    final dupes = await db.rawQuery(
      'SELECT name FROM accounts GROUP BY name HAVING COUNT(*) > 1',
    );
    for (final row in dupes) {
      final name = row['name'] as String;
      final sharing = await db.query(
        'accounts',
        columns: ['id'],
        where: 'name = ?',
        whereArgs: [name],
        orderBy: 'id ASC',
      );
      // Skip the first — it keeps the original name.
      for (var i = 1; i < sharing.length; i++) {
        final id = sharing[i]['id'] as int;
        final newName = '$name (${i + 1})';
        await db.update(
          'accounts',
          {'name': newName},
          where: 'id = ?',
          whereArgs: [id],
        );
      }
    }
  }

  /// Auto-detected transactions (bank SMS, payment-app notifications) that
  /// weren't confident enough to log straight away. [external_ref] is the
  /// dedupe key — the same payment seen twice (SMS *and* a UPI app
  /// notification, or a re-scan of the inbox) must never become two rows.
  Future<void> _createPendingTxnsTable(Database db) async {
    await db.execute('''
      CREATE TABLE pending_txns (
        id            INTEGER PRIMARY KEY AUTOINCREMENT,
        external_ref  TEXT NOT NULL UNIQUE,
        source        TEXT NOT NULL,
        sender        TEXT,
        raw_body      TEXT NOT NULL,
        amount        INTEGER NOT NULL,
        direction     TEXT NOT NULL,
        merchant      TEXT,
        account_tail  TEXT,
        category      TEXT NOT NULL,
        occurred_at   TEXT NOT NULL,
        confidence    REAL NOT NULL,
        status        TEXT NOT NULL DEFAULT 'pending',
        created_at    TEXT NOT NULL
      )
    ''');
  }

  Future<void> _createLoanPaymentsTable(Database db) async {
    await db.execute('''
      CREATE TABLE loan_payments (
        id          INTEGER PRIMARY KEY AUTOINCREMENT,
        loan_id     INTEGER NOT NULL,
        owner_type  TEXT NOT NULL DEFAULT '${_LoanPaymentOwnerV12.personLoan}',
        amount      INTEGER NOT NULL,
        date        TEXT NOT NULL,
        note        TEXT,
        created_at  TEXT NOT NULL
      )
    ''');
    await db.execute(
      'CREATE INDEX idx_loan_payments_owner ON loan_payments(owner_type, loan_id)',
    );
  }

  Future<void> _createRemindersTable(Database db) async {
    await db.execute('''
      CREATE TABLE reminders (
        id          INTEGER PRIMARY KEY AUTOINCREMENT,
        title       TEXT NOT NULL,
        note        TEXT,
        date_time   TEXT NOT NULL,
        repeat      TEXT NOT NULL DEFAULT 'none',
        active      INTEGER NOT NULL DEFAULT 1
      )
    ''');
  }

  Future<void> _createLoansTable(Database db) async {
    await db.execute('''
      CREATE TABLE loans (
        id                  INTEGER PRIMARY KEY AUTOINCREMENT,
        name                TEXT NOT NULL,
        principal           INTEGER NOT NULL,
        interest_amount     INTEGER NOT NULL DEFAULT 0,
        emi_amount          INTEGER NOT NULL,
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
        price         INTEGER NOT NULL,
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
        target      INTEGER NOT NULL,
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
        amount        INTEGER NOT NULL,
        note          TEXT,
        type          TEXT NOT NULL CHECK (type IN ('expense', 'income', 'lent', 'borrowed')),
        created_at    TEXT NOT NULL,
        counterparty  TEXT,
        settled       INTEGER,
        account       TEXT,
        goal_id       INTEGER,
        loan_id       INTEGER,
        source        TEXT NOT NULL DEFAULT 'manual',
        external_ref  TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE recurring (
        id                      INTEGER PRIMARY KEY AUTOINCREMENT,
        amount                  INTEGER NOT NULL,
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
        opening_balance INTEGER NOT NULL DEFAULT 0,
        is_default      INTEGER NOT NULL DEFAULT 0,
        created_at      TEXT NOT NULL,
        type            TEXT NOT NULL DEFAULT 'cash',
        current_value   INTEGER
      )
    ''');

    await db.execute('''
      CREATE TABLE transfers (
        id            INTEGER PRIMARY KEY AUTOINCREMENT,
        from_account  TEXT NOT NULL,
        to_account    TEXT NOT NULL,
        amount        INTEGER NOT NULL,
        note          TEXT,
        date          TEXT NOT NULL,
        created_at    TEXT NOT NULL
      )
    ''');

    await db.execute('CREATE INDEX idx_txns_date ON txns(date)');
    await db.execute('CREATE INDEX idx_txns_category ON txns(category)');
    await db.execute('CREATE INDEX idx_txns_type ON txns(type)');
    await db.execute(
      'CREATE INDEX idx_txns_external_ref ON txns(external_ref)',
    );
    await db.execute('CREATE INDEX idx_txns_loan_id ON txns(loan_id)');
    await db.execute('CREATE UNIQUE INDEX idx_accounts_name ON accounts(name)');
    await _createAccountIndexes(db);

    await _createWishlistTable(db);
    await _createGoalsTable(db);
    await _createLoansTable(db);
    await _createLoanPaymentsTable(db);
    await _createRemindersTable(db);
    await _createPendingTxnsTable(db);
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
