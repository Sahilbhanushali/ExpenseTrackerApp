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
    settled     INTEGER
);

CREATE TABLE IF NOT EXISTS recurring (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    chat_id         INTEGER NOT NULL,
    amount          REAL NOT NULL,
    category        TEXT NOT NULL,
    note            TEXT,
    day_of_month    INTEGER NOT NULL,
    last_run_month  TEXT,
    active          INTEGER NOT NULL DEFAULT 1
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
    Upgrade a pre-existing txns table (created before 'lent'/'borrowed' and
    the counterparty/settled columns existed) in place. Safe to run every
    startup — it's a no-op once the table already matches SCHEMA.
    """
    row = conn.execute(
        "SELECT sql FROM sqlite_master WHERE type='table' AND name='txns'"
    ).fetchone()
    if row is None or "'lent'" in row["sql"]:
        return

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


def init_db():
    """Create the txns/recurring tables if they don't already exist, and
    migrate an older txns table in place if needed. Safe to call every time."""
    with _connect() as conn:
        conn.executescript(SCHEMA)
        _migrate_schema(conn)


def add(amount: float, category: str, note: str, txn_type: str,
        chat_id: int = None, txn_date: str = None,
        counterparty: str = None, settled: int = None) -> int:
    """
    Insert one transaction. txn_date defaults to today (YYYY-MM-DD).
    counterparty/settled are only meaningful for txn_type 'lent'/'borrowed'.
    Returns the new row's id.
    """
    txn_date = txn_date or date.today().isoformat()
    created_at = datetime.now().isoformat(timespec="seconds")

    with _connect() as conn:
        cur = conn.execute(
            """INSERT INTO txns (date, category, amount, note, type, chat_id,
                                  created_at, counterparty, settled)
               VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)""",
            (txn_date, category, amount, note, txn_type, chat_id, created_at,
             counterparty, settled),
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


def add_recurring(chat_id: int, amount: float, category: str, note: str, day_of_month: int) -> int:
    """Register a new recurring bill/subscription. Returns the new row's id."""
    with _connect() as conn:
        cur = conn.execute(
            """INSERT INTO recurring (chat_id, amount, category, note, day_of_month, active)
               VALUES (?, ?, ?, ?, ?, 1)""",
            (chat_id, amount, category, note, day_of_month),
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


def mark_recurring_run(row_id: int, month: str):
    """Stamp a recurring entry as having fired for `month` ('YYYY-MM')."""
    with _connect() as conn:
        conn.execute("UPDATE recurring SET last_run_month = ? WHERE id = ?", (month, row_id))


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
