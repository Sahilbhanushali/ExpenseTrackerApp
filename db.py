"""
db.py — tiny SQLite storage layer for the expense tracker.

One table, "txns":
    id          INTEGER PRIMARY KEY
    date        TEXT    'YYYY-MM-DD' (defaults to today, local time)
    category    TEXT
    amount      REAL
    note        TEXT
    type        TEXT    'expense' | 'income'
    chat_id     INTEGER  Telegram chat this entry came from
    created_at  TEXT    ISO timestamp, set automatically

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
    type        TEXT NOT NULL CHECK (type IN ('expense', 'income')),
    chat_id     INTEGER,
    created_at  TEXT NOT NULL
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


def init_db():
    """Create the txns table if it doesn't already exist. Safe to call every time."""
    with _connect() as conn:
        conn.execute(SCHEMA)


def add(amount: float, category: str, note: str, txn_type: str,
        chat_id: int = None, txn_date: str = None) -> int:
    """
    Insert one transaction. txn_date defaults to today (YYYY-MM-DD).
    Returns the new row's id.
    """
    txn_date = txn_date or date.today().isoformat()
    created_at = datetime.now().isoformat(timespec="seconds")

    with _connect() as conn:
        cur = conn.execute(
            """INSERT INTO txns (date, category, amount, note, type, chat_id, created_at)
               VALUES (?, ?, ?, ?, ?, ?, ?)""",
            (txn_date, category, amount, note, txn_type, chat_id, created_at),
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
