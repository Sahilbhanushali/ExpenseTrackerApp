"""
db.py — tiny SQLite storage layer for the expense tracker.

One table, "txns":
    id          INTEGER PRIMARY KEY
    date        TEXT    'YYYY-MM-DD' (defaults to today, local time)
    category    TEXT
    amount      REAL
    note        TEXT
    type        TEXT    'expense' | 'income' | 'lent' | 'borrowed'
    chat_id     INTEGER  Telegram chat this entry came from
    created_at  TEXT    ISO timestamp, set automatically
    counterparty TEXT    person's name, only set for lent/borrowed rows
    settled     INTEGER  0/1, only meaningful for lent/borrowed rows

And "recurring", for bills that auto-log themselves each month:
    id              INTEGER PRIMARY KEY
    chat_id         INTEGER  which chat to log/notify for
    amount          REAL
    category        TEXT
    note            TEXT
    day_of_month    INTEGER  1-28, the day it should fire
    last_run_month  TEXT     'YYYY-MM' of the last month it fired, or NULL
    active          INTEGER  1/0
    installments_remaining  INTEGER  NULL = runs indefinitely (rent, subs);
                             a number = an EMI/installment plan that stops
                             and deactivates itself once it hits 0
    loan_id         INTEGER  NULL = a normal expense bill; set = this entry
                             pays down that txns row (a lent/borrowed loan)
                             each month via repay() instead of logging a
                             plain expense — see /repayplan in bot.py

Everything else in the project (bot.py, export.py) goes through the
helpers below rather than touching SQLite directly.
"""

import sqlite3
from datetime import datetime, date
from pathlib import Path
from contextlib import contextmanager

DB_PATH = Path(__file__).parent / "expenses.db"

SCHEMA = """
CREATE TABLE IF NOT EXISTS txns (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    date        TEXT NOT NULL,
    category    TEXT NOT NULL,
    amount      REAL NOT NULL,
    note        TEXT,
    type        TEXT NOT NULL CHECK (type IN ('expense', 'income', 'lent', 'borrowed')),
    chat_id     INTEGER,
    created_at  TEXT NOT NULL,
    counterparty TEXT,
    settled     INTEGER,
    account     TEXT
);

CREATE TABLE IF NOT EXISTS recurring (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    chat_id         INTEGER NOT NULL,
    amount          REAL NOT NULL,
    category        TEXT NOT NULL,
    note            TEXT,
    day_of_month    INTEGER NOT NULL,
    last_run_month  TEXT,
    active          INTEGER NOT NULL DEFAULT 1,
    installments_remaining INTEGER,
    loan_id         INTEGER
);

CREATE TABLE IF NOT EXISTS accounts (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    chat_id         INTEGER NOT NULL,
    name            TEXT NOT NULL,
    opening_balance REAL NOT NULL DEFAULT 0,
    is_default      INTEGER NOT NULL DEFAULT 0,
    created_at      TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS transfers (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    chat_id         INTEGER NOT NULL,
    from_account    TEXT NOT NULL,
    to_account      TEXT NOT NULL,
    amount          REAL NOT NULL,
    note            TEXT,
    date            TEXT NOT NULL,
    created_at      TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS wishlist (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    chat_id         INTEGER NOT NULL,
    name            TEXT NOT NULL,
    price           REAL NOT NULL,
    note            TEXT,
    purchased       INTEGER NOT NULL DEFAULT 0,
    created_at      TEXT NOT NULL,
    purchased_at    TEXT
);
"""


@contextmanager
def _connect():
    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row
    try:
        yield conn
        conn.commit()
    finally:
        conn.close()


def _migrate_schema(conn):
    """
    Upgrade pre-existing tables in place — safe to run every startup, a
    no-op once they already match SCHEMA.
    """
    row = conn.execute(
        "SELECT sql FROM sqlite_master WHERE type='table' AND name='txns'"
    ).fetchone()
    if row is not None and "'lent'" not in row["sql"]:
        conn.executescript("""
            ALTER TABLE txns RENAME TO txns_old;

            CREATE TABLE txns (
                id          INTEGER PRIMARY KEY AUTOINCREMENT,
                date        TEXT NOT NULL,
                category    TEXT NOT NULL,
                amount      REAL NOT NULL,
                note        TEXT,
                type        TEXT NOT NULL CHECK (type IN ('expense', 'income', 'lent', 'borrowed')),
                chat_id     INTEGER,
                created_at  TEXT NOT NULL,
                counterparty TEXT,
                settled     INTEGER
            );

            INSERT INTO txns (id, date, category, amount, note, type, chat_id, created_at)
                SELECT id, date, category, amount, note, type, chat_id, created_at FROM txns_old;

            DROP TABLE txns_old;
        """)

    # recurring has no CHECK constraint, so a plain ADD COLUMN works — no
    # need to rebuild the table like txns above.
    cols = {r["name"] for r in conn.execute("PRAGMA table_info(recurring)").fetchall()}
    if "installments_remaining" not in cols:
        conn.execute("ALTER TABLE recurring ADD COLUMN installments_remaining INTEGER")
    if "loan_id" not in cols:
        conn.execute("ALTER TABLE recurring ADD COLUMN loan_id INTEGER")

    txn_cols = {r["name"] for r in conn.execute("PRAGMA table_info(txns)").fetchall()}
    if "account" not in txn_cols:
        conn.execute("ALTER TABLE txns ADD COLUMN account TEXT")


def init_db():
    """Create the txns/recurring tables if they don't already exist, and
    migrate an older txns table in place if needed. Safe to call every time."""
    with _connect() as conn:
        conn.executescript(SCHEMA)
        _migrate_schema(conn)


def add(amount: float, category: str, note: str, txn_type: str,
        chat_id: int = None, txn_date: str = None,
        counterparty: str = None, settled: int = None,
        account: str = None) -> int:
    """
    Insert one transaction. txn_date defaults to today (YYYY-MM-DD).
    counterparty/settled are only meaningful for txn_type 'lent'/'borrowed'.
    account is the money pot (see accounts table) this txn affects — None if
    the chat hasn't set one up. Returns the new row's id.
    """
    txn_date = txn_date or date.today().isoformat()
    created_at = datetime.now().isoformat(timespec="seconds")

    with _connect() as conn:
        cur = conn.execute(
            """INSERT INTO txns (date, category, amount, note, type, chat_id,
                                  created_at, counterparty, settled, account)
               VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)""",
            (txn_date, category, amount, note, txn_type, chat_id, created_at,
             counterparty, settled, account),
        )
        return cur.lastrowid


def undo_last(chat_id: int = None):
    """
    Delete the most recently added transaction (optionally scoped to a
    chat_id). Returns the deleted row as a dict, or None if there was
    nothing to delete.
    """
    with _connect() as conn:
        if chat_id is not None:
            row = conn.execute(
                "SELECT * FROM txns WHERE chat_id = ? ORDER BY id DESC LIMIT 1",
                (chat_id,),
            ).fetchone()
        else:
            row = conn.execute(
                "SELECT * FROM txns ORDER BY id DESC LIMIT 1"
            ).fetchone()

        if row is None:
            return None

        conn.execute("DELETE FROM txns WHERE id = ?", (row["id"],))
        return dict(row)


def get_by_id(row_id: int, chat_id: int = None):
    """Return a single transaction as a dict, or None if it doesn't exist
    (or belongs to a different chat, when chat_id is given)."""
    with _connect() as conn:
        if chat_id is not None:
            row = conn.execute(
                "SELECT * FROM txns WHERE id = ? AND chat_id = ?", (row_id, chat_id)
            ).fetchone()
        else:
            row = conn.execute("SELECT * FROM txns WHERE id = ?", (row_id,)).fetchone()
        return dict(row) if row else None


_EDITABLE_FIELDS = {"amount", "category", "note"}


def update(row_id: int, chat_id: int = None, **fields):
    """
    Update one or more of amount/category/note on an existing transaction.
    Returns the updated row as a dict, or None if it doesn't exist (or
    doesn't belong to chat_id, when given).
    """
    fields = {k: v for k, v in fields.items() if k in _EDITABLE_FIELDS and v is not None}
    if not fields:
        return get_by_id(row_id, chat_id=chat_id)

    with _connect() as conn:
        if chat_id is not None:
            row = conn.execute(
                "SELECT * FROM txns WHERE id = ? AND chat_id = ?", (row_id, chat_id)
            ).fetchone()
        else:
            row = conn.execute("SELECT * FROM txns WHERE id = ?", (row_id,)).fetchone()
        if row is None:
            return None

        set_clause = ", ".join(f"{k} = ?" for k in fields)
        conn.execute(
            f"UPDATE txns SET {set_clause} WHERE id = ?",
            (*fields.values(), row_id),
        )
        updated = conn.execute("SELECT * FROM txns WHERE id = ?", (row_id,)).fetchone()
        return dict(updated)


def add_recurring(chat_id: int, amount: float, category: str, note: str, day_of_month: int,
                   installments_remaining: int = None, loan_id: int = None) -> int:
    """
    Register a new recurring bill/subscription. Returns the new row's id.
    installments_remaining=None runs indefinitely (rent, subscriptions); a
    number makes it an EMI/installment plan that deactivates itself once
    that many more auto-logs have fired (see mark_recurring_run).
    loan_id links this to an existing lent/borrowed txns row — each firing
    calls repay() against that loan instead of logging a plain expense.
    """
    with _connect() as conn:
        cur = conn.execute(
            """INSERT INTO recurring (chat_id, amount, category, note, day_of_month,
                                       active, installments_remaining, loan_id)
               VALUES (?, ?, ?, ?, ?, 1, ?, ?)""",
            (chat_id, amount, category, note, day_of_month, installments_remaining, loan_id),
        )
        return cur.lastrowid


def list_recurring(chat_id: int) -> list:
    """Active recurring entries for one chat, ordered by day of month."""
    with _connect() as conn:
        rows = conn.execute(
            "SELECT * FROM recurring WHERE chat_id = ? AND active = 1 ORDER BY day_of_month ASC",
            (chat_id,),
        ).fetchall()
        return [dict(r) for r in rows]


def remove_recurring(row_id: int, chat_id: int = None):
    """Deactivate a recurring entry. Returns True if a row was found and deactivated."""
    with _connect() as conn:
        if chat_id is not None:
            row = conn.execute(
                "SELECT id FROM recurring WHERE id = ? AND chat_id = ?", (row_id, chat_id)
            ).fetchone()
        else:
            row = conn.execute("SELECT id FROM recurring WHERE id = ?", (row_id,)).fetchone()
        if row is None:
            return False
        conn.execute("UPDATE recurring SET active = 0 WHERE id = ?", (row_id,))
        return True


def due_recurring(today: date = None) -> list:
    """
    Active recurring entries whose day_of_month has arrived and that
    haven't already fired this calendar month.
    """
    today = today or date.today()
    month = today.isoformat()[:7]
    with _connect() as conn:
        rows = conn.execute(
            """SELECT * FROM recurring
               WHERE active = 1 AND day_of_month <= ?
                 AND (last_run_month IS NULL OR last_run_month != ?)""",
            (today.day, month),
        ).fetchall()
        return [dict(r) for r in rows]


def mark_recurring_run(row_id: int, month: str) -> bool:
    """
    Stamp a recurring entry as having fired for `month` ('YYYY-MM'). If it
    has installments_remaining set, decrements it and deactivates the entry
    once it reaches 0 — an EMI plan stops itself instead of firing forever.
    Returns True if this was the final installment (now deactivated).
    """
    with _connect() as conn:
        row = conn.execute(
            "SELECT installments_remaining FROM recurring WHERE id = ?", (row_id,)
        ).fetchone()
        remaining = row["installments_remaining"] if row else None

        if remaining is None:
            conn.execute("UPDATE recurring SET last_run_month = ? WHERE id = ?", (month, row_id))
            return False

        remaining -= 1
        finished = remaining <= 0
        conn.execute(
            "UPDATE recurring SET last_run_month = ?, installments_remaining = ?, active = ? WHERE id = ?",
            (month, remaining, 0 if finished else 1, row_id),
        )
        return finished


def outstanding_loans(chat_id: int = None) -> list:
    """Lent/borrowed rows that haven't been settled yet, oldest first."""
    with _connect() as conn:
        if chat_id is not None:
            rows = conn.execute(
                """SELECT * FROM txns
                   WHERE type IN ('lent', 'borrowed') AND (settled IS NULL OR settled = 0)
                     AND chat_id = ?
                   ORDER BY date ASC, id ASC""",
                (chat_id,),
            ).fetchall()
        else:
            rows = conn.execute(
                """SELECT * FROM txns
                   WHERE type IN ('lent', 'borrowed') AND (settled IS NULL OR settled = 0)
                   ORDER BY date ASC, id ASC"""
            ).fetchall()
        return [dict(r) for r in rows]


def settle(row_id: int, chat_id: int = None):
    """Mark a lent/borrowed row as settled (paid back). Returns the updated
    row as a dict, or None if it doesn't exist / isn't a loan row / doesn't
    belong to chat_id."""
    with _connect() as conn:
        if chat_id is not None:
            row = conn.execute(
                "SELECT * FROM txns WHERE id = ? AND chat_id = ? AND type IN ('lent', 'borrowed')",
                (row_id, chat_id),
            ).fetchone()
        else:
            row = conn.execute(
                "SELECT * FROM txns WHERE id = ? AND type IN ('lent', 'borrowed')", (row_id,)
            ).fetchone()
        if row is None:
            return None

        conn.execute("UPDATE txns SET settled = 1 WHERE id = ?", (row_id,))
        updated = conn.execute("SELECT * FROM txns WHERE id = ?", (row_id,)).fetchone()
        return dict(updated)


def repay(row_id: int, repay_amount: float, chat_id: int = None):
    """
    Apply a partial (or full) repayment to an outstanding lent/borrowed row
    by reducing its amount in place. Clamps at 0 and auto-settles once it
    reaches 0 — mirrors settle()'s all-at-once behavior but for paying a
    debt down over several transactions instead of one.

    Returns {"row": <updated row dict>, "applied": float, "overpaid": float}
    — overpaid is whatever part of repay_amount exceeded what was still
    owed (not recorded anywhere, just surfaced so the caller can flag it) —
    or None if the row doesn't exist, isn't a loan, or is already settled.
    """
    with _connect() as conn:
        if chat_id is not None:
            row = conn.execute(
                "SELECT * FROM txns WHERE id = ? AND chat_id = ? AND type IN ('lent', 'borrowed')",
                (row_id, chat_id),
            ).fetchone()
        else:
            row = conn.execute(
                "SELECT * FROM txns WHERE id = ? AND type IN ('lent', 'borrowed')", (row_id,)
            ).fetchone()
        if row is None or row["settled"] == 1:
            return None

        outstanding = row["amount"]
        applied = min(repay_amount, outstanding)
        overpaid = max(repay_amount - outstanding, 0.0)
        new_amount = outstanding - applied
        settled = 1 if new_amount <= 0 else 0

        conn.execute(
            "UPDATE txns SET amount = ?, settled = ? WHERE id = ?",
            (new_amount, settled, row_id),
        )
        updated = conn.execute("SELECT * FROM txns WHERE id = ?", (row_id,)).fetchone()
        return {"row": dict(updated), "applied": applied, "overpaid": overpaid}


def all_rows() -> list:
    """Return every transaction as a list of dicts, oldest first."""
    with _connect() as conn:
        rows = conn.execute("SELECT * FROM txns ORDER BY date ASC, id ASC").fetchall()
        return [dict(r) for r in rows]


def month_total(month: str) -> dict:
    """
    month: 'YYYY-MM'. Returns {"expense": float, "income": float} totals
    for that month.
    """
    with _connect() as conn:
        rows = conn.execute(
            "SELECT type, SUM(amount) as total FROM txns WHERE date LIKE ? GROUP BY type",
            (f"{month}%",),
        ).fetchall()

    totals = {"expense": 0.0, "income": 0.0}
    for r in rows:
        totals[r["type"]] = r["total"] or 0.0
    return totals


def category_totals(month: str) -> dict:
    """Per-category expense totals for a given 'YYYY-MM' month."""
    with _connect() as conn:
        rows = conn.execute(
            """SELECT category, SUM(amount) as total FROM txns
               WHERE date LIKE ? AND type = 'expense'
               GROUP BY category""",
            (f"{month}%",),
        ).fetchall()
    return {r["category"]: r["total"] or 0.0 for r in rows}


def add_account(chat_id: int, name: str, opening_balance: float = 0.0) -> int:
    """Register a new money pot (bank/cash/wallet/card) for a chat. Returns
    the new row's id. Caller (bot.py) is responsible for rejecting duplicate
    names — this just inserts."""
    created_at = datetime.now().isoformat(timespec="seconds")
    with _connect() as conn:
        cur = conn.execute(
            """INSERT INTO accounts (chat_id, name, opening_balance, is_default, created_at)
               VALUES (?, ?, ?, 0, ?)""",
            (chat_id, name, opening_balance, created_at),
        )
        return cur.lastrowid


def list_accounts(chat_id: int) -> list:
    """All accounts for a chat, oldest first."""
    with _connect() as conn:
        rows = conn.execute(
            "SELECT * FROM accounts WHERE chat_id = ? ORDER BY id ASC", (chat_id,)
        ).fetchall()
        return [dict(r) for r in rows]


def get_default_account(chat_id: int) -> str:
    """The account name new transactions should be tagged with, or None if
    the chat hasn't set one up / hasn't picked a default."""
    with _connect() as conn:
        row = conn.execute(
            "SELECT name FROM accounts WHERE chat_id = ? AND is_default = 1", (chat_id,)
        ).fetchone()
        return row["name"] if row else None


def set_default_account(chat_id: int, name: str) -> bool:
    """Make `name` the chat's default account (used to auto-tag new
    transactions). Returns False if no such account exists for this chat."""
    with _connect() as conn:
        row = conn.execute(
            "SELECT id FROM accounts WHERE chat_id = ? AND name = ?", (chat_id, name)
        ).fetchone()
        if row is None:
            return False
        conn.execute("UPDATE accounts SET is_default = 0 WHERE chat_id = ?", (chat_id,))
        conn.execute("UPDATE accounts SET is_default = 1 WHERE id = ?", (row["id"],))
        return True


def account_balance(chat_id: int, name: str) -> float:
    """Current balance of one account: opening balance, plus everything
    logged against it (income/borrowed add, expense/lent subtract — same
    sign convention as everywhere else in this file), plus transfers."""
    with _connect() as conn:
        acc = conn.execute(
            "SELECT opening_balance FROM accounts WHERE chat_id = ? AND name = ?",
            (chat_id, name),
        ).fetchone()
        if acc is None:
            return None
        balance = acc["opening_balance"]

        rows = conn.execute(
            "SELECT type, SUM(amount) as total FROM txns WHERE chat_id = ? AND account = ? GROUP BY type",
            (chat_id, name),
        ).fetchall()
        for r in rows:
            total = r["total"] or 0.0
            if r["type"] in ("expense", "lent"):
                balance -= total
            else:  # income, borrowed
                balance += total

        transferred_in = conn.execute(
            "SELECT SUM(amount) as total FROM transfers WHERE chat_id = ? AND to_account = ?",
            (chat_id, name),
        ).fetchone()["total"] or 0.0
        transferred_out = conn.execute(
            "SELECT SUM(amount) as total FROM transfers WHERE chat_id = ? AND from_account = ?",
            (chat_id, name),
        ).fetchone()["total"] or 0.0
        balance += transferred_in - transferred_out

        return balance


def add_transfer(chat_id: int, from_account: str, to_account: str, amount: float,
                  note: str = None, txn_date: str = None) -> int:
    """Move money between two of a chat's accounts. Doesn't touch txns —
    account_balance() nets transfers in separately."""
    txn_date = txn_date or date.today().isoformat()
    created_at = datetime.now().isoformat(timespec="seconds")
    with _connect() as conn:
        cur = conn.execute(
            """INSERT INTO transfers (chat_id, from_account, to_account, amount, note, date, created_at)
               VALUES (?, ?, ?, ?, ?, ?, ?)""",
            (chat_id, from_account, to_account, amount, note, txn_date, created_at),
        )
        return cur.lastrowid


def available_savings(chat_id: int) -> float:
    """Rough all-time spare cash for a chat: income earned, minus expenses,
    minus what's currently tied up in outstanding lent money. Deliberately
    excludes outstanding borrowed money — that cash is sitting in your
    pocket but it's owed, not saved, so it must never count toward wishlist
    affordability (counting it would show a purchase as "affordable" using
    money that's actually a debt to someone else)."""
    with _connect() as conn:
        rows = conn.execute(
            "SELECT type, SUM(amount) as total FROM txns WHERE chat_id = ? GROUP BY type",
            (chat_id,),
        ).fetchall()
    totals = {r["type"]: (r["total"] or 0.0) for r in rows}
    return totals.get("income", 0.0) - totals.get("expense", 0.0) - totals.get("lent", 0.0)


def add_wishlist_item(chat_id: int, name: str, price: float, note: str = None) -> int:
    """Add a purchase goal. Returns the new row's id."""
    created_at = datetime.now().isoformat(timespec="seconds")
    with _connect() as conn:
        cur = conn.execute(
            """INSERT INTO wishlist (chat_id, name, price, note, purchased, created_at)
               VALUES (?, ?, ?, ?, 0, ?)""",
            (chat_id, name, price, note, created_at),
        )
        return cur.lastrowid


def list_wishlist(chat_id: int, include_purchased: bool = False) -> list:
    """Wishlist items for a chat, cheapest first (closest to affordable)."""
    with _connect() as conn:
        if include_purchased:
            rows = conn.execute(
                "SELECT * FROM wishlist WHERE chat_id = ? ORDER BY price ASC", (chat_id,)
            ).fetchall()
        else:
            rows = conn.execute(
                "SELECT * FROM wishlist WHERE chat_id = ? AND purchased = 0 ORDER BY price ASC",
                (chat_id,),
            ).fetchall()
        return [dict(r) for r in rows]


def mark_wishlist_purchased(row_id: int, chat_id: int = None):
    """Mark a wishlist item as bought. Returns the updated row, or None if
    it doesn't exist (or belongs to a different chat)."""
    purchased_at = datetime.now().isoformat(timespec="seconds")
    with _connect() as conn:
        if chat_id is not None:
            row = conn.execute(
                "SELECT id FROM wishlist WHERE id = ? AND chat_id = ?", (row_id, chat_id)
            ).fetchone()
        else:
            row = conn.execute("SELECT id FROM wishlist WHERE id = ?", (row_id,)).fetchone()
        if row is None:
            return None
        conn.execute(
            "UPDATE wishlist SET purchased = 1, purchased_at = ? WHERE id = ?",
            (purchased_at, row_id),
        )
        updated = conn.execute("SELECT * FROM wishlist WHERE id = ?", (row_id,)).fetchone()
        return dict(updated)


def remove_wishlist_item(row_id: int, chat_id: int = None) -> bool:
    """Delete a wishlist item outright. Returns True if a row was found."""
    with _connect() as conn:
        if chat_id is not None:
            row = conn.execute(
                "SELECT id FROM wishlist WHERE id = ? AND chat_id = ?", (row_id, chat_id)
            ).fetchone()
        else:
            row = conn.execute("SELECT id FROM wishlist WHERE id = ?", (row_id,)).fetchone()
        if row is None:
            return False
        conn.execute("DELETE FROM wishlist WHERE id = ?", (row_id,))
        return True


if __name__ == "__main__":
    # quick end-to-end smoke test
    import os
    if DB_PATH.exists():
        os.remove(DB_PATH)

    init_db()
    add(500, "travel", "ola", "expense", chat_id=1)
    add(420, "food", "swiggy dinner", "expense", chat_id=1)
    add(75000, "income", "salary", "income", chat_id=1)
    print("all rows:", all_rows())
    print("month total:", month_total(date.today().isoformat()[:7]))
    print("undo:", undo_last(chat_id=1))
    print("all rows after undo:", all_rows())
