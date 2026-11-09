import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

/// Which table `loan_payments.loan_id` points at. Person-to-person loans
/// live in `txns`, EMI loans live in `loans` — two separate id sequences,
/// so a payment row is meaningless without knowing which one it belongs to.
abstract final class LoanPaymentOwner {
  static const personLoan = 'person_loan';
  static const emiLoan = 'emi_loan';
}

/// SQLite schema — 1:1 port of expense_bot/db.py's SCHEMA, minus the
/// Telegram-only chat_id column (single local user, no chat scoping needed).
class AppDatabase {
  static const dbName = 'expenses.db';
  static const _dbVersion = 19;

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
    // Postings before the movements they reference.
    'postings',
    'movements',
    'audit_log',
    'income_cycles',
    'salary_profile',
    'expected_income',
    'budgets',
    'card_statement_emis',
    'card_emis',
    'card_statements',
    'credit_cards',
    'loan_installments',
    'loan_events',
    'reconciliations',
    'allocation_decisions',
    'allocation_settings',
    'investment_holdings',
  ];

  AppDatabase._([this._pathOverride]);
  static final AppDatabase instance = AppDatabase._();

  /// A fresh, isolated database — for tests only. Each call opens its own
  /// instance so tests never share state. Pass a file [path] when a test
  /// needs the database to survive being closed and reopened (migrations).
  factory AppDatabase.forTesting([String path = ':memory:']) =>
      AppDatabase._(path);

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
        "DEFAULT '${LoanPaymentOwner.personLoan}'",
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
    if (oldVersion < 13) {
      await _upgradeToLedgerV13(db);
    }
    if (oldVersion < 14) {
      await _createCycleTables(db);
    }
    if (oldVersion < 15) {
      await _upgradeTxnsV15(db);
      await _createIncomeAndBudgetTables(db);
    }
    if (oldVersion < 16) {
      await _createDebtTables(db);
    }
    if (oldVersion < 17) {
      await _createReconciliationTables(db);
    }
    if (oldVersion < 18) {
      await _createAllocationTables(db);
    }
    if (oldVersion < 19) {
      await _createWealthTables(db);
    }
  }

  /// Bank details and roles. Status 'closed' hides an account from pickers
  /// without deleting its history.
  static Future<void> _addAccountDetailColumns(Database db) async {
    // Re-runnable: a half-finished upgrade must be able to resume.
    final existing = {
      for (final c in await db.rawQuery('PRAGMA table_info(accounts)'))
        c['name'] as String,
    };
    const columns = {
      'bank_name': 'TEXT',
      'last4': 'TEXT',
      'roles': "TEXT NOT NULL DEFAULT ''",
      'status': "TEXT NOT NULL DEFAULT 'active'",
    };
    for (final MapEntry(key: name, value: type) in columns.entries) {
      if (!existing.contains(name)) {
        await db.execute('ALTER TABLE accounts ADD COLUMN $name $type');
      }
    }
  }

  /// Non-income, non-expense money: one `movements` row per event, one
  /// `postings` row per side. Plus an audit trail for money records.
  static Future<void> _createLedgerTables(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS movements (
        id            INTEGER PRIMARY KEY AUTOINCREMENT,
        ref           TEXT NOT NULL UNIQUE,
        kind          TEXT NOT NULL,
        date          TEXT NOT NULL,
        amount        INTEGER NOT NULL CHECK (amount > 0),
        status        TEXT NOT NULL DEFAULT 'completed'
                      CHECK (status IN ('planned', 'completed', 'cancelled')),
        note          TEXT,
        created_at    TEXT NOT NULL,
        completed_at  TEXT
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_movements_date ON movements(date)',
    );
    await db.execute('''
      CREATE TABLE IF NOT EXISTS postings (
        id           INTEGER PRIMARY KEY AUTOINCREMENT,
        movement_id  INTEGER NOT NULL REFERENCES movements(id),
        owner_type   TEXT NOT NULL,
        owner_id     INTEGER,
        amount       INTEGER NOT NULL
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_postings_owner ON postings(owner_type, owner_id)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_postings_movement ON postings(movement_id)',
    );
    await db.execute('''
      CREATE TABLE IF NOT EXISTS audit_log (
        id          INTEGER PRIMARY KEY AUTOINCREMENT,
        entity      TEXT NOT NULL,
        entity_id   INTEGER,
        action      TEXT NOT NULL,
        before_json TEXT,
        after_json  TEXT,
        at          TEXT NOT NULL
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_audit_entity ON audit_log(entity, entity_id)',
    );
  }

  static String _txnsDdl(String table) =>
      '''
      CREATE TABLE $table (
        id               INTEGER PRIMARY KEY AUTOINCREMENT,
        date             TEXT NOT NULL,
        category         TEXT NOT NULL,
        amount           INTEGER NOT NULL,
        note             TEXT,
        type             TEXT NOT NULL CHECK (type IN ('expense', 'income', 'lent', 'borrowed', 'refund')),
        created_at       TEXT NOT NULL,
        counterparty     TEXT,
        settled          INTEGER,
        account          TEXT,
        goal_id          INTEGER,
        loan_id          INTEGER,
        source           TEXT NOT NULL DEFAULT 'manual',
        external_ref     TEXT,
        income_source    TEXT,
        recurring_income INTEGER NOT NULL DEFAULT 0,
        refund_of        INTEGER
      )
    ''';

  static const _txnsV14Columns =
      'id, date, category, amount, note, type, created_at, counterparty, '
      'settled, account, goal_id, loan_id, source, external_ref';

  /// v14 → v15: `txns.type` gains 'refund'. SQLite can't alter a CHECK
  /// constraint, so the table is rebuilt: same rows, same ids, copied
  /// column by column, then the indexes are recreated. Re-runnable — a
  /// table that already allows refunds is left alone.
  static Future<void> _upgradeTxnsV15(Database db) async {
    final ddl = await db.rawQuery(
      "SELECT sql FROM sqlite_master WHERE type = 'table' AND name = 'txns'",
    );
    final current = (ddl.first['sql'] as String?) ?? '';
    if (!current.contains("'refund'")) {
      await db.execute('DROP TABLE IF EXISTS txns_v15');
      await db.execute(_txnsDdl('txns_v15'));
      await db.execute(
        'INSERT INTO txns_v15 ($_txnsV14Columns) '
        'SELECT $_txnsV14Columns FROM txns',
      );
      await db.execute('DROP TABLE txns');
      await db.execute('ALTER TABLE txns_v15 RENAME TO txns');
    }
    for (final (name, col) in [
      ('idx_txns_date', 'date'),
      ('idx_txns_category', 'category'),
      ('idx_txns_type', 'type'),
      ('idx_txns_external_ref', 'external_ref'),
      ('idx_txns_loan_id', 'loan_id'),
      ('idx_txns_account', 'account'),
      ('idx_txns_refund_of', 'refund_of'),
    ]) {
      await db.execute('CREATE INDEX IF NOT EXISTS $name ON txns($col)');
    }
    // Recorded salaries are salary income.
    await db.execute(
      "UPDATE txns SET income_source = 'salary' WHERE type = 'income' "
      'AND income_source IS NULL AND (id IN (SELECT salary_txn_id FROM '
      "income_cycles WHERE salary_txn_id IS NOT NULL) OR category = 'salary')",
    );
  }

  static Future<void> _addColumns(
    Database db,
    String table,
    Map<String, String> columns,
  ) async {
    final existing = {
      for (final c in await db.rawQuery('PRAGMA table_info($table)'))
        c['name'] as String,
    };
    for (final MapEntry(key: name, value: type) in columns.entries) {
      if (!existing.contains(name)) {
        await db.execute('ALTER TABLE $table ADD COLUMN $name $type');
      }
    }
  }

  /// v16: credit cards (with statements, payments and card EMIs) and the
  /// rebuilt loans (schedules, split payments, prepayments). Additive and
  /// re-runnable. Card purchases are `txns` with `card_id` (an expense on
  /// the card, not the bank); bill payments and loan principal are
  /// `movements` to a card/loan posting.
  static Future<void> _createDebtTables(Database db) async {
    await _addColumns(db, 'txns', {'card_id': 'INTEGER'});
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_txns_card ON txns(card_id)',
    );
    await _addColumns(db, 'movements', {
      'link_type': 'TEXT',
      'link_id': 'INTEGER',
    });
    await _addColumns(db, 'loans', {
      'kind': "TEXT NOT NULL DEFAULT 'personal'",
      'lender': 'TEXT',
      'rate_bps': 'INTEGER',
      'status': "TEXT NOT NULL DEFAULT 'active'",
      'split_estimated': 'INTEGER NOT NULL DEFAULT 0',
      'opening': "TEXT NOT NULL DEFAULT 'existing'",
    });
    await _addColumns(db, 'loan_payments', {
      'installment_id': 'INTEGER',
      'principal': 'INTEGER',
      'interest': 'INTEGER',
      'movement_id': 'INTEGER',
      'txn_id': 'INTEGER',
    });
    await db.execute('''
      CREATE TABLE IF NOT EXISTS credit_cards (
        id                  INTEGER PRIMARY KEY AUTOINCREMENT,
        name                TEXT NOT NULL,
        bank                TEXT,
        last4               TEXT,
        limit_amount        INTEGER NOT NULL CHECK (limit_amount >= 0),
        statement_day       INTEGER CHECK (statement_day BETWEEN 1 AND 31),
        due_day             INTEGER CHECK (due_day BETWEEN 1 AND 31),
        repayment_account   TEXT,
        opening_outstanding INTEGER NOT NULL DEFAULT 0,
        status              TEXT NOT NULL DEFAULT 'active',
        created_at          TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS card_statements (
        id               INTEGER PRIMARY KEY AUTOINCREMENT,
        card_id          INTEGER NOT NULL,
        period_start     TEXT NOT NULL,
        period_end       TEXT NOT NULL,
        generated_on     TEXT NOT NULL,
        due_date         TEXT NOT NULL,
        total_due        INTEGER NOT NULL CHECK (total_due >= 0),
        minimum_due      INTEGER NOT NULL DEFAULT 0,
        previous_balance INTEGER NOT NULL DEFAULT 0,
        payments         INTEGER NOT NULL DEFAULT 0,
        refunds          INTEGER NOT NULL DEFAULT 0,
        purchases        INTEGER NOT NULL DEFAULT 0,
        emi_amount       INTEGER NOT NULL DEFAULT 0,
        charges          INTEGER NOT NULL DEFAULT 0,
        note             TEXT,
        created_at       TEXT NOT NULL,
        UNIQUE (card_id, period_end)
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS card_emis (
        id               INTEGER PRIMARY KEY AUTOINCREMENT,
        card_id          INTEGER NOT NULL,
        purchase_txn_id  INTEGER,
        description      TEXT NOT NULL,
        purchase_amount  INTEGER NOT NULL CHECK (purchase_amount > 0),
        purchase_date    TEXT NOT NULL,
        tenure_months    INTEGER NOT NULL CHECK (tenure_months > 0),
        installment      INTEGER NOT NULL CHECK (installment > 0),
        interest_total   INTEGER,
        fees             INTEGER,
        taxes            INTEGER,
        status           TEXT NOT NULL DEFAULT 'active',
        created_at       TEXT NOT NULL
      )
    ''');
    // One row per EMI per statement it was billed on: the billed count is
    // derived from these rows, so a statement can't bill an EMI twice.
    await db.execute('''
      CREATE TABLE IF NOT EXISTS card_statement_emis (
        statement_id INTEGER NOT NULL,
        emi_id       INTEGER NOT NULL,
        principal    INTEGER,
        interest     INTEGER,
        PRIMARY KEY (statement_id, emi_id)
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS loan_installments (
        id             INTEGER PRIMARY KEY AUTOINCREMENT,
        loan_id        INTEGER NOT NULL,
        seq            INTEGER NOT NULL,
        due_date       TEXT NOT NULL,
        amount         INTEGER NOT NULL,
        principal      INTEGER NOT NULL,
        interest       INTEGER NOT NULL,
        principal_paid INTEGER NOT NULL DEFAULT 0,
        interest_paid  INTEGER NOT NULL DEFAULT 0,
        status         TEXT NOT NULL DEFAULT 'due'
                       CHECK (status IN ('due', 'paid', 'cancelled')),
        UNIQUE (loan_id, seq)
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS loan_events (
        id          INTEGER PRIMARY KEY AUTOINCREMENT,
        loan_id     INTEGER NOT NULL,
        kind        TEXT NOT NULL
                    CHECK (kind IN ('prepayment', 'foreclosure', 'correction', 'fee')),
        amount      INTEGER NOT NULL,
        date        TEXT NOT NULL,
        movement_id INTEGER,
        txn_id      INTEGER,
        note        TEXT,
        created_at  TEXT NOT NULL
      )
    ''');
  }

  /// v17: account type and money on hold, and a record of every time a
  /// balance was checked against the bank (with the adjustment, if any).
  static Future<void> _createReconciliationTables(Database db) async {
    await _addColumns(db, 'accounts', {
      'bank_type': 'TEXT',
      'hold_amount': 'INTEGER NOT NULL DEFAULT 0',
    });
    await db.execute('''
      CREATE TABLE IF NOT EXISTS reconciliations (
        id                     INTEGER PRIMARY KEY AUTOINCREMENT,
        owner_type             TEXT NOT NULL CHECK (owner_type IN ('account', 'card')),
        owner_id               INTEGER NOT NULL,
        as_of                  TEXT NOT NULL,
        app_balance            INTEGER NOT NULL,
        actual_balance         INTEGER NOT NULL,
        difference             INTEGER NOT NULL,
        adjustment_movement_id INTEGER,
        note                   TEXT,
        created_at             TEXT NOT NULL
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_reconciliations_owner '
      'ON reconciliations(owner_type, owner_id)',
    );
  }

  /// v18: Smart Money Allocation. Proposals are computed live and never
  /// stored; only the user's decisions are (reserve, skip, transfer done),
  /// one per need per period ([scope]: the cycle start or month).
  static Future<void> _createAllocationTables(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS allocation_settings (
        id               INTEGER PRIMARY KEY CHECK (id = 1),
        priority_order   TEXT NOT NULL,
        emergency_target INTEGER,
        emergency_monthly INTEGER,
        savings_per_cycle INTEGER,
        invest_per_cycle INTEGER
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS allocation_decisions (
        id          INTEGER PRIMARY KEY AUTOINCREMENT,
        scope       TEXT NOT NULL,
        need_key    TEXT NOT NULL,
        bucket      TEXT NOT NULL,
        label       TEXT NOT NULL,
        amount      INTEGER NOT NULL CHECK (amount >= 0),
        destination TEXT,
        source      TEXT,
        status      TEXT NOT NULL
                    CHECK (status IN ('reserved', 'transferred', 'skipped')),
        movement_id INTEGER,
        created_at  TEXT NOT NULL,
        updated_at  TEXT NOT NULL,
        UNIQUE (scope, need_key)
      )
    ''');
  }

  /// v19: goals become earmarks on savings accounts (contributions are
  /// transfers tagged with the goal, never expenses); the emergency target
  /// can be months of essential spending; manual investment holdings.
  static Future<void> _createWealthTables(Database db) async {
    await _addColumns(db, 'goals', {
      'target_date': 'TEXT',
      'priority': 'INTEGER NOT NULL DEFAULT 2',
      'monthly_contribution': 'INTEGER',
      'account': 'TEXT',
      'kind': "TEXT NOT NULL DEFAULT 'short'",
      'status': "TEXT NOT NULL DEFAULT 'active'",
      'starting_amount': 'INTEGER NOT NULL DEFAULT 0',
    });
    await _addColumns(db, 'allocation_settings', {
      'emergency_months': 'INTEGER',
      'essential_monthly': 'INTEGER',
    });
    await db.execute('''
      CREATE TABLE IF NOT EXISTS investment_holdings (
        id            INTEGER PRIMARY KEY AUTOINCREMENT,
        account       TEXT NOT NULL,
        name          TEXT NOT NULL,
        kind          TEXT NOT NULL DEFAULT 'other',
        invested      INTEGER NOT NULL CHECK (invested >= 0),
        current_value INTEGER NOT NULL CHECK (current_value >= 0),
        as_of         TEXT NOT NULL,
        note          TEXT,
        status        TEXT NOT NULL DEFAULT 'active',
        created_at    TEXT NOT NULL
      )
    ''');
  }

  /// Expected (not yet received) income, and budgets for every period.
  static Future<void> _createIncomeAndBudgetTables(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS expected_income (
        id               INTEGER PRIMARY KEY AUTOINCREMENT,
        source           TEXT NOT NULL,
        amount           INTEGER NOT NULL CHECK (amount > 0),
        expected_date    TEXT NOT NULL,
        account          TEXT,
        note             TEXT,
        status           TEXT NOT NULL DEFAULT 'pending'
                         CHECK (status IN ('pending', 'received', 'cancelled')),
        received_txn_id  INTEGER,
        created_at       TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS budgets (
        id           INTEGER PRIMARY KEY AUTOINCREMENT,
        period       TEXT NOT NULL
                     CHECK (period IN ('cycle', 'month', 'week', 'day', 'custom')),
        category     TEXT,
        limit_amount INTEGER NOT NULL CHECK (limit_amount > 0),
        start_date   TEXT,
        end_date     TEXT,
        caution_pct  INTEGER NOT NULL DEFAULT 80
                     CHECK (caution_pct BETWEEN 1 AND 99),
        essential    INTEGER NOT NULL DEFAULT 0,
        name         TEXT,
        created_at   TEXT NOT NULL
      )
    ''');
    // One overall and one per-category budget per recurring period.
    await db.execute(
      'CREATE UNIQUE INDEX IF NOT EXISTS idx_budgets_unique '
      "ON budgets(period, IFNULL(category, '')) WHERE period != 'custom'",
    );
  }

  /// Salary cycles: only start dates are stored, ends are derived (see
  /// salary_cycle.dart). `end_date` and `summary_json` are written once, when
  /// a cycle is closed, and never recalculated (rule 15).
  static Future<void> _createCycleTables(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS income_cycles (
        id               INTEGER PRIMARY KEY AUTOINCREMENT,
        start_date       TEXT NOT NULL UNIQUE,
        salary_txn_id    INTEGER,
        untracked_salary INTEGER CHECK (untracked_salary IS NULL OR untracked_salary > 0),
        note             TEXT,
        created_at       TEXT NOT NULL,
        closed_at        TEXT,
        end_date         TEXT,
        summary_json     TEXT,
        rules_version    INTEGER
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS salary_profile (
        id            INTEGER PRIMARY KEY CHECK (id = 1),
        ctc_annual    INTEGER,
        gross_monthly INTEGER,
        expected_net  INTEGER,
        day_from      INTEGER NOT NULL DEFAULT 7,
        day_to        INTEGER NOT NULL DEFAULT 15,
        account       TEXT
      )
    ''');
  }

  /// v12 → v13: account details and roles, ledger tables, and every
  /// existing transfer copied into movements + postings so balances are
  /// identical before and after. The old `transfers` rows are left as they
  /// were (nothing rewritten) and are no longer read.
  static Future<void> _upgradeToLedgerV13(Database db) async {
    await _addAccountDetailColumns(db);
    await db.execute(
      "UPDATE accounts SET roles = CASE type "
      "WHEN 'investment' THEN 'investment' "
      "WHEN 'emergency_fund' THEN 'emergency' "
      "ELSE 'daily' END WHERE roles = ''",
    );
    await _createLedgerTables(db);

    final ids = {
      for (final r in await db.query('accounts', columns: ['id', 'name']))
        r['name'] as String: r['id'] as int,
    };
    final transfers = await db.query('transfers', orderBy: 'id ASC');
    for (final t in transfers) {
      final amount = (t['amount'] as num).round();
      if (amount <= 0) continue;
      final movementId = await db.insert('movements', {
        'ref': 'legacy-transfer-${t['id']}',
        'kind': 'transfer',
        'date': t['date'],
        'amount': amount,
        'status': 'completed',
        'note': t['note'],
        'created_at': t['created_at'],
        'completed_at': t['created_at'],
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
      // Already copied by an earlier, interrupted run.
      if (movementId == 0) continue;
      for (final (name, sign) in [
        (t['from_account'], -1),
        (t['to_account'], 1),
      ]) {
        final id = ids[name];
        await db.insert('postings', {
          'movement_id': movementId,
          // An account deleted outside the app's own delete flow: keep the
          // money visible as leaving/entering the books, not lost.
          'owner_type': id == null ? 'external' : 'account',
          'owner_id': id,
          'amount': sign * amount,
        });
      }
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
        owner_type  TEXT NOT NULL DEFAULT '${LoanPaymentOwner.personLoan}',
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
    await db.execute(_txnsDdl('txns'));

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
    await _addAccountDetailColumns(db);
    await _createLedgerTables(db);
    await _createCycleTables(db);
    await _createIncomeAndBudgetTables(db);
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_txns_refund_of ON txns(refund_of)',
    );

    await _createWishlistTable(db);
    await _createGoalsTable(db);
    await _createLoansTable(db);
    await _createLoanPaymentsTable(db);
    await _createRemindersTable(db);
    await _createPendingTxnsTable(db);
    // Last: extends loans and loan_payments, created above.
    await _createDebtTables(db);
    await _createReconciliationTables(db);
    await _createAllocationTables(db);
    await _createWealthTables(db);
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
