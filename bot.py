"""
bot.py — Telegram front-end for the expense tracker.

Every plain-text message is parsed (parser.py), stored (db.py), and the
dashboard's data.js is regenerated (export.py) before replying. A photo is
treated as a receipt: OCR'd via pytesseract/Tesseract, best-effort matched
to an amount/category, and held pending until /logreceipt confirms it — see
handle_photo(). The only network traffic is Telegram's own API, plus an
optional LAN-only HTTP server (see start_local_server()) that serves the
dashboard to your own phone over WiFi — nothing reaches the public internet
either way, and the token lives only in config.json (never served, never
in data.js).

Commands:
    /start      welcome + quick examples
    /help       same as /start
    /total      this month's spend vs budget, with a text progress bar
    /budget     show every category's cap and this month's usage
    /find       search past entries by note/category keyword
    /compare    this month vs last month
    /digest     on-demand budget-pacing summary (also sent daily at 8pm)
    /setbudget      change the overall monthly budget
    /setcatbudget   change one category's budget
    /setgoal        change the savings goal amount/label
    /recommend      suggested per-category budget split, or [apply] it
    /undo       delete the most recently logged entry (per-chat, asks to confirm)
    /recent     last 10 entries with their ids
    /edit       fix an existing entry's amount/category/note
    /recurring  manage auto-logged monthly bills (add/list/remove)
    /emi        log an installment purchase (this month + auto-logs the rest)
    /lend       log money you lent someone (they owe you back)
    /borrow     log money you borrowed (you owe it back)
    /owed       see everything outstanding, both ways
    /settle     mark a lend/borrow entry as fully paid back
    /repay      apply a partial payment toward an outstanding loan
    /repayplan  schedule automatic monthly repayments against a loan
    /goal       this month's savings goal progress
    /categories list every category and its keywords
    /addcategory  add a new category or teach an existing one keywords
    /logreceipt   confirm/save a receipt photo's OCR'd amount (send a photo first)
    /export     [YYYY-MM] send transactions as a CSV file
    /backup     send expenses.db + config.json as a zip (also sent weekly)
    /dashboard  send a standalone dashboard.html with today's data baked in
    /link       LAN URL for the always-live dashboard (same WiFi only)

Three JobQueue jobs run automatically (see main()'s job_queue.run_daily
calls): check_recurring() at 9am auto-logs due recurring bills,
daily_digest() at 8pm pushes a budget-pacing summary to every chat that's
ever logged something, and weekly_backup() on Sunday nights sends a
DB+config backup the same way.
"""

import calendar
import functools
import io
import json
import logging
import os
import re
import socket
import tempfile
import threading
import zipfile
from datetime import date, datetime, timedelta
from http.server import ThreadingHTTPServer, SimpleHTTPRequestHandler
from pathlib import Path

from datetime import time as dtime

import pytesseract
from PIL import Image
from telegram import Update
from telegram.ext import (
    ApplicationBuilder,
    CommandHandler,
    MessageHandler,
    ContextTypes,
    filters,
)

import db
import export
from parser import parse_multi, parse_receipt_text, detect_emi, detect_repayment_candidate, CATEGORY_KEYWORDS

BASE_DIR = Path(__file__).parent
CONFIG_PATH = BASE_DIR / "config.json"
LOCAL_SERVER_PORT = 8000

logging.basicConfig(
    format="%(asctime)s %(levelname)s %(name)s: %(message)s", level=logging.INFO
)
log = logging.getLogger("expense-bot")


def get_lan_ip() -> str:
    """Best-effort local network IP (not 127.0.0.1) for /link to show. Doesn't
    actually contact 8.8.8.8 — UDP connect() just asks the OS to pick the
    outbound-facing interface for that route, no packet is sent."""
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    try:
        s.connect(("8.8.8.8", 80))
        return s.getsockname()[0]
    except OSError:
        return "127.0.0.1"
    finally:
        s.close()


def start_local_server():
    """
    Serve export.PUBLIC_DIR (dashboard.html + data.js only — never the
    project root, so config.json/expenses.db/bot.py are never reachable)
    over the LAN in a background thread, so a phone on the same WiFi can
    load the dashboard as a live page instead of a one-off Telegram file.
    """
    export.PUBLIC_DIR.mkdir(exist_ok=True)
    handler = functools.partial(SimpleHTTPRequestHandler, directory=str(export.PUBLIC_DIR))
    httpd = ThreadingHTTPServer(("0.0.0.0", LOCAL_SERVER_PORT), handler)
    thread = threading.Thread(target=httpd.serve_forever, daemon=True)
    thread.start()
    log.info("Local dashboard server on http://%s:%s/dashboard.html", get_lan_ip(), LOCAL_SERVER_PORT)
    return httpd


def load_config() -> dict:
    with open(CONFIG_PATH, "r", encoding="utf-8") as f:
        return json.load(f)


def save_config(cfg: dict):
    with open(CONFIG_PATH, "w", encoding="utf-8") as f:
        json.dump(cfg, f, ensure_ascii=False, indent=2)
        f.write("\n")


def fmt_money(amount: float, currency: str) -> str:
    """Indian-style grouping: ₹12,34,567 — last 3 digits, then groups of 2."""
    amount = round(amount)
    sign = "-" if amount < 0 else ""
    amount = abs(amount)
    s = str(amount)
    if len(s) <= 3:
        grouped = s
    else:
        last3 = s[-3:]
        rest = s[:-3]
        parts = []
        while len(rest) > 2:
            parts.insert(0, rest[-2:])
            rest = rest[:-2]
        if rest:
            parts.insert(0, rest)
        grouped = ",".join(parts) + "," + last3
    return f"{sign}{currency}{grouped}"


def effective_budget(configured_budget: float, income: float) -> float:
    """Cap spending at the lesser of the configured budget and this month's
    logged income — but don't collapse to 0 before any income is logged."""
    return min(configured_budget, income) if income > 0 else configured_budget


def progress_bar(spent: float, budget: float, width: int = 12) -> str:
    if budget <= 0:
        return "[no budget set]"
    frac = min(spent / budget, 1.0)
    filled = int(round(frac * width))
    bar = "█" * filled + "░" * (width - filled)
    pct = round(spent / budget * 100)
    return f"{bar} {pct}%"


async def start(update: Update, context: ContextTypes.DEFAULT_TYPE):
    text = (
        "💰 *Expense tracker bot*\n\n"
        "Just text me spending in plain English, e.g.:\n"
        "  • `spent 500 on ola`\n"
        "  • `swiggy 420 dinner`\n"
        "  • `1.5k myntra shirt`\n"
        "  • `got salary 75000`\n"
        "  • `yesterday 500 taxi` / `780 groceries on 3rd aug`\n"
        "  • `450 lunch and 200 auto` (logs both)\n\n"
        "Or just ask, e.g. \"what's my budget\", \"how much have I spent\", "
        "\"how much on food\", \"how much have I spent on ola\", "
        "\"compare this month to last month\", \"savings goal progress\", "
        "\"recent expenses\".\n\n"
        "Commands:\n"
        "/total — this month vs budget\n"
        "/budget — per-category caps\n"
        "/find <term> — search past entries\n"
        "/compare — this month vs last month\n"
        "/digest — on-demand pacing summary (also sent daily at 8pm)\n"
        "/setbudget <amount> — change monthly budget\n"
        "/setcatbudget <cat> <amount> — change a category's cap\n"
        "/setgoal <amount> [label] — change savings goal\n"
        "/recommend — suggested budget split (needs/wealth/wants)\n"
        "/undo — delete the last entry\n"
        "/recent — last 10 entries with their ids\n"
        "/edit <id> <field> <value> — fix an entry\n"
        "/recurring add|list|remove — auto-log monthly bills\n"
        "/emi <amount> <cat> <months> [note] — installment purchase\n"
        "/lend <amount> <person> [note] — you lent them money\n"
        "/borrow <amount> <person> [note] — you borrowed money\n"
        "/owed — see everything outstanding\n"
        "/settle <id> — mark a loan as fully paid back\n"
        "/repay <id> <amount> — apply a partial payment\n"
        "/repayplan <id> <amount> [months] — schedule monthly repayments\n"
        "/goal — savings goal progress\n"
        "/categories — list categories and their keywords\n"
        "/addcategory <name> <kw1,kw2,...> — teach it a new category\n"
        "Send a receipt photo — I'll OCR it and ask you to /logreceipt to confirm\n"
        "/export [YYYY-MM] — download transactions as CSV\n"
        "/backup — download expenses.db + config.json as a zip\n"
        "/dashboard — one self-contained dashboard.html, ready for your phone\n"
        "/link — live dashboard URL, for when you're on this WiFi\n"
    )
    await update.message.reply_text(text, parse_mode="Markdown")


async def total_cmd(update: Update, context: ContextTypes.DEFAULT_TYPE):
    cfg = load_config()
    currency = cfg.get("currency", "₹")
    month = date.today().isoformat()[:7]
    totals = db.month_total(month)
    spent = totals["expense"]
    budget = effective_budget(cfg.get("monthlyBudget", 0), totals["income"])

    bar = progress_bar(spent, budget)
    remaining = budget - spent
    remaining_str = fmt_money(remaining, currency) if remaining >= 0 else \
        f"-{fmt_money(abs(remaining), currency)}"

    text = (
        f"📊 *{month}*\n"
        f"Spent: {fmt_money(spent, currency)} / {fmt_money(budget, currency)}\n"
        f"{bar}\n"
        f"Remaining: {remaining_str}\n"
        f"Income this month: {fmt_money(totals['income'], currency)}"
    )
    await update.message.reply_text(text, parse_mode="Markdown")


async def budget_cmd(update: Update, context: ContextTypes.DEFAULT_TYPE):
    cfg = load_config()
    currency = cfg.get("currency", "₹")
    month = date.today().isoformat()[:7]
    cat_totals = db.category_totals(month)
    budgets = cfg.get("budgets", {})

    lines = ["🎯 *Category budgets this month*"]
    for cat, cap in budgets.items():
        spent = cat_totals.get(cat, 0.0)
        flag = " ⚠️" if cap and spent > cap else ""
        lines.append(
            f"{cat}: {fmt_money(spent, currency)} / {fmt_money(cap, currency)}{flag}"
        )
    await update.message.reply_text("\n".join(lines), parse_mode="Markdown")


async def _category_query_reply(update: Update, category: str, cfg: dict):
    """Reply with just one category's spend vs cap this month — the precise
    answer to "how much on food" instead of dumping the full /budget list."""
    currency = cfg.get("currency", "₹")
    month = date.today().isoformat()[:7]
    spent = db.category_totals(month).get(category, 0.0)
    cap = cfg.get("budgets", {}).get(category, 0)

    lines = [f"📊 *{category}* — {month}"]
    if cap:
        remaining = cap - spent
        remaining_str = fmt_money(remaining, currency) if remaining >= 0 else \
            f"-{fmt_money(abs(remaining), currency)} (over budget)"
        lines.append(f"{fmt_money(spent, currency)} / {fmt_money(cap, currency)}")
        lines.append(progress_bar(spent, cap))
        lines.append(f"Remaining: {remaining_str}")
    else:
        lines.append(f"Spent: {fmt_money(spent, currency)} (no budget cap set — /setcatbudget {category} <amount>)")
    await update.message.reply_text("\n".join(lines), parse_mode="Markdown")


def _search_transactions(term: str, chat_id: int) -> list:
    term = term.lower()
    return [
        r for r in db.all_rows()
        if r["chat_id"] == chat_id
        and (term in (r["note"] or "").lower() or term in r["category"].lower())
    ]


async def _search_reply(update: Update, term: str, cfg: dict):
    chat_id = update.effective_chat.id
    currency = cfg.get("currency", "₹")
    matches = _search_transactions(term, chat_id)

    if not matches:
        await update.message.reply_text(f"No entries found matching '{term}'.")
        return

    total = sum(r["amount"] for r in matches if r["type"] == "expense")
    lines = [f"🔍 *'{term}'* — {len(matches)} match(es), {fmt_money(total, currency)} spent total"]
    for r in matches[-10:]:
        sign = "+" if r["type"] in ("income", "borrowed") else "-"
        lines.append(
            f"#{r['id']} · {r['date']} · {sign}{fmt_money(r['amount'], currency)} · {r['note'] or 'no note'}"
        )
    await update.message.reply_text("\n".join(lines), parse_mode="Markdown")


async def find_cmd(update: Update, context: ContextTypes.DEFAULT_TYPE):
    args = context.args
    if not args:
        await update.message.reply_text("Usage: /find <term>\ne.g. /find ola")
        return
    cfg = load_config()
    await _search_reply(update, " ".join(args), cfg)


async def compare_cmd(update: Update, context: ContextTypes.DEFAULT_TYPE):
    cfg = load_config()
    currency = cfg.get("currency", "₹")

    today = date.today()
    this_month = today.isoformat()[:7]
    last_month = (today.replace(day=1) - timedelta(days=1)).isoformat()[:7]

    cur = db.month_total(this_month)
    prev = db.month_total(last_month)
    diff = cur["expense"] - prev["expense"]

    lines = [f"📈 *{this_month} vs {last_month}*"]
    lines.append(f"Spent: {fmt_money(cur['expense'], currency)} vs {fmt_money(prev['expense'], currency)}")
    if prev["expense"] > 0:
        pct = abs(diff) / prev["expense"] * 100
        if diff > 0:
            lines.append(f"🔺 up {pct:.0f}% ({fmt_money(diff, currency)} more)")
        elif diff < 0:
            lines.append(f"🔻 down {pct:.0f}% ({fmt_money(abs(diff), currency)} less)")
        else:
            lines.append("➖ same as last month")
    lines.append(f"Income: {fmt_money(cur['income'], currency)} vs {fmt_money(prev['income'], currency)}")
    await update.message.reply_text("\n".join(lines), parse_mode="Markdown")


def _parse_amount_arg(raw: str):
    try:
        value = float(raw.replace(",", ""))
    except ValueError:
        return None
    return value if value >= 0 else None


async def setbudget_cmd(update: Update, context: ContextTypes.DEFAULT_TYPE):
    args = context.args
    if len(args) != 1 or (amount := _parse_amount_arg(args[0])) is None:
        await update.message.reply_text("Usage: /setbudget <amount>\ne.g. /setbudget 45000")
        return

    cfg = load_config()
    currency = cfg.get("currency", "₹")
    cfg["monthlyBudget"] = amount
    save_config(cfg)
    export.run()
    await update.message.reply_text(f"✅ Monthly budget set to {fmt_money(amount, currency)}.")


async def setcatbudget_cmd(update: Update, context: ContextTypes.DEFAULT_TYPE):
    args = context.args
    cfg = load_config()
    valid = valid_categories(cfg)
    if len(args) != 2 or args[0].lower() not in valid or \
            (amount := _parse_amount_arg(args[1])) is None:
        await update.message.reply_text(
            "Usage: /setcatbudget <category> <amount>\n"
            "e.g. /setcatbudget food 7000\n"
            f"Valid categories: {', '.join(sorted(valid))}"
        )
        return

    category = args[0].lower()
    currency = cfg.get("currency", "₹")
    cfg.setdefault("budgets", {})[category] = amount
    save_config(cfg)
    export.run()
    await update.message.reply_text(f"✅ {category} budget set to {fmt_money(amount, currency)}.")


async def setgoal_cmd(update: Update, context: ContextTypes.DEFAULT_TYPE):
    args = context.args
    if not args or (amount := _parse_amount_arg(args[0])) is None:
        await update.message.reply_text(
            "Usage: /setgoal <amount> [label]\ne.g. /setgoal 10000 Emergency fund"
        )
        return

    label = " ".join(args[1:]) or "Savings goal"
    cfg = load_config()
    currency = cfg.get("currency", "₹")
    cfg["savingsGoal"] = {"amount": amount, "label": label}
    save_config(cfg)
    export.run()
    await update.message.reply_text(f"✅ Savings goal set: {label} — {fmt_money(amount, currency)}.")


async def goal_cmd(update: Update, context: ContextTypes.DEFAULT_TYPE):
    cfg = load_config()
    currency = cfg.get("currency", "₹")
    goal = cfg.get("savingsGoal", {})
    target = goal.get("amount", 0)
    label = goal.get("label", "Savings goal")

    if not target:
        await update.message.reply_text(
            "No savings goal set. Add a \"savingsGoal\": {\"amount\": ..., \"label\": ...} "
            "to config.json to enable this."
        )
        return

    month = date.today().isoformat()[:7]
    totals = db.month_total(month)
    net = totals["income"] - totals["expense"]

    bar = progress_bar(max(net, 0), target)
    remaining = target - net
    text = (
        f"🎯 *{label}* — {month}\n"
        f"Saved so far: {fmt_money(net, currency)} / {fmt_money(target, currency)}\n"
        f"{bar}\n"
    )
    text += (
        f"{fmt_money(remaining, currency)} to go" if remaining > 0
        else "Goal reached! 🎉"
    )
    await update.message.reply_text(text, parse_mode="Markdown")


async def export_cmd(update: Update, context: ContextTypes.DEFAULT_TYPE):
    args = context.args
    month = None
    if args:
        month = args[0]
        try:
            datetime.strptime(month, "%Y-%m")
        except ValueError:
            await update.message.reply_text("Month must look like YYYY-MM, e.g. /export 2026-08")
            return

    path = export.export_csv(month=month)
    try:
        with open(path, "rb") as f:
            await update.message.reply_document(
                document=f,
                filename=path.name,
                caption=f"📄 Export: {month or 'all transactions'}",
            )
    finally:
        path.unlink(missing_ok=True)


def _build_backup_zip() -> Path:
    """Zip up expenses.db + config.json (the two files that can't be
    regenerated from anything else) so a corrupted disk or bad edit doesn't
    wipe your whole history with no way back."""
    ts = datetime.now().strftime("%Y%m%d_%H%M%S")
    fd, path = tempfile.mkstemp(prefix=f"expense_backup_{ts}_", suffix=".zip")
    os.close(fd)
    path = Path(path)
    with zipfile.ZipFile(path, "w", zipfile.ZIP_DEFLATED) as zf:
        zf.write(db.DB_PATH, arcname="expenses.db")
        zf.write(CONFIG_PATH, arcname="config.json")
    return path


async def backup_cmd(update: Update, context: ContextTypes.DEFAULT_TYPE):
    path = _build_backup_zip()
    try:
        with open(path, "rb") as f:
            await update.message.reply_document(
                document=f,
                filename=path.name,
                caption=(
                    "💾 Backup: expenses.db + config.json (includes your bot "
                    "token — this file is as sensitive as the bot itself)."
                ),
            )
    finally:
        path.unlink(missing_ok=True)


async def weekly_backup(context: ContextTypes.DEFAULT_TYPE):
    """Weekly JobQueue job: push the same backup /backup produces to every
    chat that's ever logged something, so it exists somewhere off this
    machine even if you never remember to run /backup yourself."""
    path = _build_backup_zip()
    chat_ids = {r["chat_id"] for r in db.all_rows() if r["chat_id"] is not None}
    try:
        for chat_id in chat_ids:
            try:
                with open(path, "rb") as f:
                    await context.bot.send_document(
                        chat_id=chat_id, document=f, filename=path.name,
                        caption="💾 Weekly backup",
                    )
            except Exception:
                log.exception("Failed to send weekly backup to chat %s", chat_id)
    finally:
        path.unlink(missing_ok=True)


async def dashboard_cmd(update: Update, context: ContextTypes.DEFAULT_TYPE):
    path = export.bundle_standalone_dashboard()
    try:
        with open(path, "rb") as f:
            await update.message.reply_document(
                document=f,
                filename="dashboard.html",
                caption=(
                    "📊 Dashboard with today's data baked in — just open this file "
                    "directly, no unzipping or second file needed. On Android, "
                    "open it from the Downloads app with Chrome."
                ),
            )
    finally:
        path.unlink(missing_ok=True)


async def link_cmd(update: Update, context: ContextTypes.DEFAULT_TYPE):
    ip = get_lan_ip()
    url = f"http://{ip}:{LOCAL_SERVER_PORT}/dashboard.html"
    await update.message.reply_text(
        f"🔗 Live dashboard (same WiFi as this machine only):\n{url}\n\n"
        "Reload the page any time for the latest numbers — no need to "
        "re-request it. Not on this WiFi? Use /dashboard instead for an "
        "offline snapshot."
    )


# chat_id -> expiry datetime for a pending /undo awaiting /undo confirm.
# In-memory only (cleared on restart) — acceptable since an expired or lost
# confirmation just means re-running /undo, not a stuck state.
_PENDING_UNDO = {}
_UNDO_CONFIRM_WINDOW = timedelta(minutes=2)


async def undo_cmd(update: Update, context: ContextTypes.DEFAULT_TYPE):
    chat_id = update.effective_chat.id
    cfg = load_config()
    currency = cfg.get("currency", "₹")

    if context.args and context.args[0].lower() == "confirm":
        expiry = _PENDING_UNDO.pop(chat_id, None)
        if expiry is None or datetime.now() > expiry:
            await update.message.reply_text("Nothing pending to confirm — run /undo again.")
            return
        row = db.undo_last(chat_id=chat_id)
        export.run()
        if row is None:
            await update.message.reply_text("Nothing to undo.")
            return
        await update.message.reply_text(
            f"🗑️ Removed: {row['category']} {fmt_money(row['amount'], currency)}"
            f" ({row['note'] or 'no note'})"
        )
        return

    rows = [r for r in db.all_rows() if r["chat_id"] == chat_id]
    if not rows:
        await update.message.reply_text("Nothing to undo.")
        return

    last = rows[-1]
    _PENDING_UNDO[chat_id] = datetime.now() + _UNDO_CONFIRM_WINDOW
    sign = "+" if last["type"] in ("income", "borrowed") else "-"
    await update.message.reply_text(
        f"⚠️ This will delete:\n"
        f"#{last['id']} · {last['date']} · {last['category']} · "
        f"{sign}{fmt_money(last['amount'], currency)} · {last['note'] or 'no note'}\n\n"
        f"Reply /undo confirm within 2 minutes to delete it, or ignore to cancel."
    )


def _crossed(before: float, after: float, cap: float, frac: float) -> bool:
    """True if this transaction is what pushed `before`->`after` across
    `cap * frac` — so alerts fire once, right when the threshold is crossed,
    not on every message after."""
    return cap > 0 and before < cap * frac <= after


def _threshold_warnings(before_spent, after_spent, budget,
                         before_cat, after_cat, cat_cap, category,
                         currency="₹") -> list:
    warnings = []
    remaining = budget - after_spent
    if _crossed(before_spent, after_spent, budget, 1.0):
        warnings.append(
            f"🚨 Over monthly budget! You've overspent by "
            f"{fmt_money(abs(remaining), currency)}."
        )
    elif _crossed(before_spent, after_spent, budget, 0.8):
        warnings.append(
            f"⚠️ 80% of monthly budget used — "
            f"{fmt_money(remaining, currency)} left for the month."
        )

    cat_remaining = cat_cap - after_cat
    if _crossed(before_cat, after_cat, cat_cap, 1.0):
        warnings.append(
            f"🚨 Over budget for {category}! Overspent by "
            f"{fmt_money(abs(cat_remaining), currency)}."
        )
    elif _crossed(before_cat, after_cat, cat_cap, 0.8):
        warnings.append(
            f"⚠️ 80% of {category} budget used — "
            f"{fmt_money(cat_remaining, currency)} left in this category."
        )
    return warnings


async def recent_cmd(update: Update, context: ContextTypes.DEFAULT_TYPE):
    chat_id = update.effective_chat.id
    cfg = load_config()
    currency = cfg.get("currency", "₹")

    rows = [r for r in db.all_rows() if r["chat_id"] == chat_id][-10:]
    rows.reverse()

    if not rows:
        await update.message.reply_text("Nothing logged yet.")
        return

    lines = ["🧾 Last entries — use /edit <id> <field> <value> to fix one:"]
    for r in rows:
        sign = "+" if r["type"] in ("income", "borrowed") else "-"
        lines.append(
            f"#{r['id']} · {r['date']} · {r['category']} · "
            f"{sign}{fmt_money(r['amount'], currency)} · {r['note'] or 'no note'}"
        )
    await update.message.reply_text("\n".join(lines))


async def edit_cmd(update: Update, context: ContextTypes.DEFAULT_TYPE):
    chat_id = update.effective_chat.id
    args = context.args

    if len(args) < 3 or not args[0].isdigit() or args[1] not in ("amount", "category", "note"):
        await update.message.reply_text(
            "Usage: /edit <id> <amount|category|note> <value>\n"
            "e.g. /edit 12 amount 450   or   /edit 12 category food\n"
            "Use /recent to find an entry's id."
        )
        return

    row_id = int(args[0])
    field = args[1]
    value = " ".join(args[2:])

    before = db.get_by_id(row_id, chat_id=chat_id)
    if before is None:
        await update.message.reply_text(f"No entry #{row_id} found for you.")
        return

    if field == "amount":
        try:
            value = round(float(value.replace(",", "")), 2)
        except ValueError:
            await update.message.reply_text("Amount must be a number, e.g. /edit 12 amount 450")
            return

    updated = db.update(row_id, chat_id=chat_id, **{field: value})
    export.run()

    cfg = load_config()
    currency = cfg.get("currency", "₹")
    before_val = before[field] if field != "amount" else fmt_money(before[field], currency)
    after_val = updated[field] if field != "amount" else fmt_money(updated[field], currency)
    await update.message.reply_text(f"✏️ #{row_id} {field}: {before_val} → {after_val}")


async def lend_cmd(update: Update, context: ContextTypes.DEFAULT_TYPE):
    chat_id = update.effective_chat.id
    args = context.args
    if len(args) < 2 or (amount := _parse_amount_arg(args[0])) is None:
        await update.message.reply_text(
            "Usage: /lend <amount> <person> [note]\ne.g. /lend 500 Rahul table part"
        )
        return

    person = args[1].strip().title()
    note = " ".join(args[2:])
    cfg = load_config()
    currency = cfg.get("currency", "₹")

    db.add(amount=amount, category="lending", note=note, txn_type="lent",
            chat_id=chat_id, counterparty=person, settled=0)
    export.run()
    await update.message.reply_text(
        f"🤝 Logged: you lent {person} {fmt_money(amount, currency)}"
        f"{f' ({note})' if note else ''}\n"
        f"{person} owes you this back — /owed to track, /settle <id> once repaid."
    )


async def borrow_cmd(update: Update, context: ContextTypes.DEFAULT_TYPE):
    chat_id = update.effective_chat.id
    args = context.args
    if len(args) < 2 or (amount := _parse_amount_arg(args[0])) is None:
        await update.message.reply_text(
            "Usage: /borrow <amount> <person> [note]\ne.g. /borrow 1000 Priya rent split"
        )
        return

    person = args[1].strip().title()
    note = " ".join(args[2:])
    cfg = load_config()
    currency = cfg.get("currency", "₹")

    db.add(amount=amount, category="lending", note=note, txn_type="borrowed",
            chat_id=chat_id, counterparty=person, settled=0)
    export.run()
    await update.message.reply_text(
        f"🤝 Logged: you borrowed {fmt_money(amount, currency)} from {person}"
        f"{f' ({note})' if note else ''}\n"
        f"You owe {person} this back — /owed to track, /settle <id> once repaid."
    )


async def owed_cmd(update: Update, context: ContextTypes.DEFAULT_TYPE):
    chat_id = update.effective_chat.id
    cfg = load_config()
    currency = cfg.get("currency", "₹")

    rows = db.outstanding_loans(chat_id=chat_id)
    if not rows:
        await update.message.reply_text("Nothing outstanding — all settled up! 🎉")
        return

    lines = ["🤝 *Outstanding — use /settle <id> once repaid*"]
    for r in rows:
        person = r["counterparty"] or "someone"
        verb = "owes you" if r["type"] == "lent" else "you owe"
        note_suffix = f" ({r['note']})" if r["note"] else ""
        lines.append(
            f"#{r['id']} · {person} {verb} {fmt_money(r['amount'], currency)}{note_suffix}"
        )
    await update.message.reply_text("\n".join(lines), parse_mode="Markdown")


async def settle_cmd(update: Update, context: ContextTypes.DEFAULT_TYPE):
    chat_id = update.effective_chat.id
    args = context.args
    if not args or not args[0].isdigit():
        await update.message.reply_text("Usage: /settle <id>\nSee /owed for ids.")
        return

    row = db.settle(int(args[0]), chat_id=chat_id)
    if row is None:
        await update.message.reply_text(f"No outstanding entry #{args[0]} found.")
        return

    export.run()
    cfg = load_config()
    currency = cfg.get("currency", "₹")
    person = row["counterparty"] or "them"
    await update.message.reply_text(
        f"✅ Settled #{row['id']}: {person} · {fmt_money(row['amount'], currency)}"
    )


def _format_repay_reply(result: dict, currency: str) -> str:
    row = result["row"]
    person = row["counterparty"] or "them"
    lines = [f"✅ Applied {fmt_money(result['applied'], currency)} to {person}'s debt (#{row['id']})."]
    if row["settled"]:
        lines.append("🎉 Fully settled!")
    else:
        lines.append(f"Remaining: {fmt_money(row['amount'], currency)}")
    if result["overpaid"] > 0:
        lines.append(
            f"⚠️ That's {fmt_money(result['overpaid'], currency)} more than was owed — "
            f"the extra wasn't recorded anywhere."
        )
    return "\n".join(lines)


def _find_outstanding_by_counterparty(chat_id: int, name: str, loan_type: str) -> list:
    name_lower = name.lower()
    return [
        r for r in db.outstanding_loans(chat_id=chat_id)
        if r["type"] == loan_type and (r["counterparty"] or "").lower() == name_lower
    ]


async def repay_cmd(update: Update, context: ContextTypes.DEFAULT_TYPE):
    chat_id = update.effective_chat.id
    args = context.args
    if len(args) < 2 or not args[0].isdigit():
        await update.message.reply_text("Usage: /repay <id> <amount>\nSee /owed for ids.")
        return

    amount = _parse_amount_arg(args[1])
    if not amount:
        await update.message.reply_text("Amount must be a positive number.")
        return

    cfg = load_config()
    currency = cfg.get("currency", "₹")
    result = db.repay(int(args[0]), amount, chat_id=chat_id)
    if result is None:
        await update.message.reply_text(f"No outstanding loan #{args[0]} found for you.")
        return

    export.run()
    await update.message.reply_text(_format_repay_reply(result, currency))


async def repayplan_cmd(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """
    /repayplan <loan id> <monthly amount> [months] — schedules automatic
    monthly repayments against an existing lend/borrow entry (see /owed for
    ids), instead of a one-off /repay each time. Without [months] it keeps
    firing until the loan is fully settled; with it, it stops after that
    many payments even if a balance remains (e.g. paying off a smaller
    fixed amount deliberately rather than the whole debt on autopilot).
    """
    chat_id = update.effective_chat.id
    args = context.args
    if len(args) < 2 or not args[0].isdigit():
        await update.message.reply_text(
            "Usage: /repayplan <loan id> <monthly amount> [months]\n"
            "e.g. /repayplan 12 5000 9\nSee /owed for loan ids."
        )
        return

    loan_id = int(args[0])
    monthly_amount = _parse_amount_arg(args[1])
    if not monthly_amount:
        await update.message.reply_text("Monthly amount must be a positive number.")
        return

    loans = [r for r in db.outstanding_loans(chat_id=chat_id) if r["id"] == loan_id]
    if not loans:
        await update.message.reply_text(f"No outstanding loan #{loan_id} found for you.")
        return
    loan = loans[0]

    months = None
    if len(args) >= 3:
        try:
            months = int(args[2])
        except ValueError:
            await update.message.reply_text("Months must be a whole number.")
            return
        if months < 1:
            await update.message.reply_text("Months must be at least 1.")
            return

    cfg = load_config()
    currency = cfg.get("currency", "₹")
    today = date.today()
    rid = db.add_recurring(
        chat_id, monthly_amount, "lending", f"repayment to {loan['counterparty'] or 'them'}",
        today.day, installments_remaining=months, loan_id=loan_id,
    )
    plan_note = f" for {months} months" if months else " until settled"
    await update.message.reply_text(
        f"📅 Repayment plan #{rid}: {fmt_money(monthly_amount, currency)}/month toward "
        f"{loan['counterparty'] or 'them'}'s {fmt_money(loan['amount'], currency)} balance"
        f"{plan_note}, starting day {today.day} each month.\n"
        f"Use /recurring remove {rid} to cancel it."
    )


def all_categories(cfg: dict) -> dict:
    """CATEGORY_KEYWORDS merged with config.json's customCategories, so
    /addcategory and friends don't require editing parser.py."""
    merged = {k: list(v) for k, v in CATEGORY_KEYWORDS.items()}
    for cat, keywords in cfg.get("customCategories", {}).items():
        merged[cat] = list(keywords) + merged.get(cat, [])
    return merged


def valid_categories(cfg: dict) -> set:
    return set(all_categories(cfg).keys()) | {"other"}


async def categories_cmd(update: Update, context: ContextTypes.DEFAULT_TYPE):
    cfg = load_config()
    merged = all_categories(cfg)
    custom = set(cfg.get("customCategories", {}).keys())
    lines = ["🏷️ *Categories*"]
    for cat in sorted(merged):
        tag = " (custom)" if cat in custom else ""
        kws = ", ".join(merged[cat][:6])
        more = f" +{len(merged[cat]) - 6} more" if len(merged[cat]) > 6 else ""
        lines.append(f"*{cat}*{tag}: {kws}{more}")
    lines.append(
        "\nUse /addcategory <name> <keyword1,keyword2,...> to add a new "
        "category or teach an existing one more keywords."
    )
    await update.message.reply_text("\n".join(lines), parse_mode="Markdown")


async def addcategory_cmd(update: Update, context: ContextTypes.DEFAULT_TYPE):
    args = context.args
    if len(args) < 2:
        await update.message.reply_text(
            "Usage: /addcategory <name> <keyword1,keyword2,...>\n"
            "e.g. /addcategory pets vet,dog food,grooming"
        )
        return

    name = args[0].lower().strip()
    keywords = [kw.strip().lower() for kw in " ".join(args[1:]).split(",") if kw.strip()]
    if not keywords:
        await update.message.reply_text("Give at least one keyword, comma-separated.")
        return

    cfg = load_config()
    custom = cfg.setdefault("customCategories", {})
    existing = custom.get(name, [])
    custom[name] = sorted(set(existing) | set(keywords))
    save_config(cfg)

    await update.message.reply_text(
        f"✅ '{name}' now matches: {', '.join(custom[name])}\n"
        f"Use /setcatbudget {name} <amount> to give it a budget."
    )

# A rule-of-thumb monthly split: pay essentials, pay yourself (investing)
# before you spend, then the rest is guilt-free lifestyle money. Weighted
# for typical Indian cost-of-living (rent is usually the single biggest
# fixed cost) rather than a plain 50/30/20. (category -> (bucket, % of budget))
RECOMMENDED_ALLOCATION = {
    "rent":        ("needs",  0.28),
    "bills":       ("needs",  0.05),
    "groceries":   ("needs",  0.10),
    "health":      ("needs",  0.04),
    "travel":      ("needs",  0.05),
    "investments": ("wealth", 0.20),
    "food":        ("wants",  0.08),
    "fitness":     ("wants",  0.05),
    "clothes":     ("wants",  0.04),
    "luxuries":    ("wants",  0.06),
    "education":   ("wants",  0.03),
    "other":       ("wants",  0.02),
}
BUCKET_TITLE = {"needs": "Needs (essentials)", "wealth": "Wealth-building", "wants": "Wants (life you love)"}


def build_recommendation(base: float) -> dict:
    """category -> recommended monthly amount, given a total budget/income."""
    return {cat: round(base * pct, 2) for cat, (_, pct) in RECOMMENDED_ALLOCATION.items()}


async def recommend_cmd(update: Update, context: ContextTypes.DEFAULT_TYPE):
    cfg = load_config()
    currency = cfg.get("currency", "₹")
    month = date.today().isoformat()[:7]
    income = db.month_total(month)["income"]
    base = effective_budget(cfg.get("monthlyBudget", 0), income)

    if base <= 0:
        await update.message.reply_text(
            "Set a monthlyBudget first (via /setbudget) so I have something to work from."
        )
        return

    rec = build_recommendation(base)

    if context.args and context.args[0].lower() == "apply":
        cfg["budgets"] = rec
        save_config(cfg)
        export.run()
        lines = [f"✅ Category budgets set to the recommended split ({fmt_money(base, currency)} total):"]
        for c, amt in rec.items():
            lines.append(f"  {c}: {fmt_money(amt, currency)}")
        await update.message.reply_text("\n".join(lines))
        return

    current_budgets = cfg.get("budgets", {})

    lines = [f"💡 *Recommended monthly split* — based on {fmt_money(base, currency)}"]
    for bucket in ("needs", "wealth", "wants"):
        cats = [c for c, (b, _) in RECOMMENDED_ALLOCATION.items() if b == bucket]
        bucket_total = sum(rec[c] for c in cats)
        pct = round(sum(p for _, (b, p) in RECOMMENDED_ALLOCATION.items() if b == bucket) * 100)
        lines.append(f"\n{BUCKET_TITLE[bucket]} — {fmt_money(bucket_total, currency)} ({pct}%)")
        for c in cats:
            lines.append(f"  {c}: {fmt_money(rec[c], currency)}")

    drift = [
        (c, current_budgets[c], rec[c])
        for c in rec
        if c in current_budgets and abs(current_budgets[c] - rec[c]) > rec[c] * 0.15
    ]
    if drift:
        lines.append("\n⚠️ Your current caps differ a fair bit from this:")
        for c, cur, new in drift:
            lines.append(f"  {c}: {fmt_money(cur, currency)} now → {fmt_money(new, currency)} recommended")

    current_sum = sum(current_budgets.values())
    if current_sum > base:
        lines.append(
            f"\n⚠️ Your category caps currently add up to {fmt_money(current_sum, currency)}, "
            f"which is over your {fmt_money(base, currency)} budget — they can't all be hit at once."
        )

    lines.append("\nRun /recommend apply to set your category budgets to these numbers.")
    await update.message.reply_text("\n".join(lines), parse_mode="Markdown")


async def recurring_cmd(update: Update, context: ContextTypes.DEFAULT_TYPE):
    chat_id = update.effective_chat.id
    cfg = load_config()
    currency = cfg.get("currency", "₹")
    args = context.args

    if not args:
        await update.message.reply_text(
            "Usage:\n"
            "/recurring add <amount> <category> <day 1-28> <note>\n"
            "/recurring list\n"
            "/recurring remove <id>"
        )
        return

    sub = args[0].lower()

    if sub == "list":
        rows = db.list_recurring(chat_id)
        if not rows:
            await update.message.reply_text("No recurring bills set up yet.")
            return
        lines = ["🔁 Recurring bills:"]
        for r in rows:
            remaining = r.get("installments_remaining")
            tail = f" · {remaining} left" if remaining is not None else ""
            lines.append(
                f"#{r['id']} · day {r['day_of_month']} · {r['category']} · "
                f"{fmt_money(r['amount'], currency)} · {r['note'] or 'no note'}{tail}"
            )
        await update.message.reply_text("\n".join(lines))
        return

    if sub == "remove":
        if len(args) < 2 or not args[1].isdigit():
            await update.message.reply_text("Usage: /recurring remove <id>")
            return
        ok = db.remove_recurring(int(args[1]), chat_id=chat_id)
        await update.message.reply_text("🗑️ Removed." if ok else "No such recurring bill.")
        return

    if sub == "add":
        if len(args) < 4:
            await update.message.reply_text(
                "Usage: /recurring add <amount> <category> <day 1-28> <note>\n"
                "e.g. /recurring add 15000 rent 3 monthly rent"
            )
            return
        try:
            amount = round(float(args[1].replace(",", "")), 2)
        except ValueError:
            await update.message.reply_text("Amount must be a number.")
            return
        category = args[2].lower()
        valid = valid_categories(cfg)
        if category not in valid:
            await update.message.reply_text(
                f"Unknown category '{category}'. Valid: {', '.join(sorted(valid))}"
            )
            return
        try:
            day = int(args[3])
        except ValueError:
            await update.message.reply_text("Day must be a number between 1 and 28.")
            return
        if not (1 <= day <= 28):
            await update.message.reply_text("Day must be between 1 and 28 (so it always exists).")
            return
        note = " ".join(args[4:])
        rid = db.add_recurring(chat_id, amount, category, note, day)
        await update.message.reply_text(
            f"🔁 Added recurring #{rid}: {fmt_money(amount, currency)} {category} "
            f"on day {day} each month."
        )
        return

    await update.message.reply_text("Unknown subcommand. Use add, list, or remove.")


async def emi_cmd(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """
    /emi <monthly_amount> <category> <months> [note] — logs this month's
    installment now and schedules the rest as a self-limiting recurring
    entry, instead of ever logging the full purchase price as one expense.
    Explicit command only (not guessed from free text) — an EMI creates a
    several-month recurring commitment, too consequential to infer wrong.
    """
    chat_id = update.effective_chat.id
    args = context.args
    if len(args) < 3:
        await update.message.reply_text(
            "Usage: /emi <monthly amount> <category> <months> [note]\n"
            "e.g. /emi 10000 other 6 fridge"
        )
        return

    amount = _parse_amount_arg(args[0])
    if amount is None:
        await update.message.reply_text("Monthly amount must be a number.")
        return

    cfg = load_config()
    currency = cfg.get("currency", "₹")
    category = args[1].lower()
    valid = valid_categories(cfg)
    if category not in valid:
        await update.message.reply_text(
            f"Unknown category '{category}'. Valid: {', '.join(sorted(valid))}"
        )
        return

    try:
        months = int(args[2])
    except ValueError:
        await update.message.reply_text("Months must be a whole number.")
        return
    if months < 1:
        await update.message.reply_text("Months must be at least 1.")
        return

    note = " ".join(args[3:])
    today = date.today()

    db.add(amount=amount, category=category, note=note, txn_type="expense", chat_id=chat_id)

    remaining_months = months - 1
    if remaining_months > 0:
        db.add_recurring(
            chat_id, amount, category, note, today.day,
            installments_remaining=remaining_months,
        )
    export.run()

    await update.message.reply_text(
        f"💳 EMI logged: {fmt_money(amount, currency)}/month for {category}"
        f"{f' ({note})' if note else ''} — 1 of {months} paid."
        + (f" The remaining {remaining_months} will auto-log on day {today.day} each month."
           if remaining_months > 0 else " That was the only installment.")
    )


async def check_recurring(context: ContextTypes.DEFAULT_TYPE):
    """Daily JobQueue job: auto-log any recurring bill that's due and hasn't
    already fired this month, then notify the chat it belongs to."""
    cfg = load_config()
    currency = cfg.get("currency", "₹")
    today = date.today()
    month = today.isoformat()[:7]

    due = db.due_recurring(today)
    if not due:
        return

    for r in due:
        loan_id = r.get("loan_id")

        if loan_id is not None:
            # Repayment plan: pay down the linked loan instead of logging a
            # plain expense — this is what actually reduces what's owed.
            result = db.repay(loan_id, r["amount"], chat_id=r["chat_id"])
            if result is None:
                # loan already settled (e.g. paid off manually via /repay
                # in between firings) — nothing left to do, stop the plan
                db.remove_recurring(r["id"], chat_id=r["chat_id"])
                continue

            finished = db.mark_recurring_run(r["id"], month)
            loan_settled = result["row"]["settled"] == 1
            if loan_settled and not finished:
                db.remove_recurring(r["id"], chat_id=r["chat_id"])
            person = result["row"]["counterparty"] or "them"
            finished_note = " — fully settled! 🎉" if loan_settled else \
                f" (remaining: {fmt_money(result['row']['amount'], currency)})"
            text = (
                f"🔁 Auto-applied repayment to {person}: "
                f"{fmt_money(result['applied'], currency)}{finished_note}"
            )
        else:
            db.add(
                amount=r["amount"],
                category=r["category"],
                note=r["note"],
                txn_type="expense",
                chat_id=r["chat_id"],
            )
            finished = db.mark_recurring_run(r["id"], month)
            finished_note = " — that was the last installment, all paid off! 🎉" if finished else ""
            text = (
                f"🔁 Auto-logged recurring bill: {r['category']} "
                f"{fmt_money(r['amount'], currency)} ({r['note'] or 'no note'}){finished_note}"
            )

        try:
            await context.bot.send_message(chat_id=r["chat_id"], text=text)
        except Exception:
            log.exception("Failed to notify chat %s about recurring bill #%s", r["chat_id"], r["id"])

    export.run()


def _build_digest_text(cfg: dict) -> str:
    """This month's pacing summary — spend so far vs. days elapsed,
    projected to see if you're on track to stay under budget. Returns None
    if there's no monthlyBudget set (nothing meaningful to pace against)."""
    currency = cfg.get("currency", "₹")
    today = date.today()
    month = today.isoformat()[:7]
    totals = db.month_total(month)
    spent = totals["expense"]
    budget = effective_budget(cfg.get("monthlyBudget", 0), totals["income"])
    if budget <= 0:
        return None

    day_of_month = today.day
    days_in_month = calendar.monthrange(today.year, today.month)[1]
    pace = (spent / day_of_month) * days_in_month if day_of_month else spent
    pct_used = round(spent / budget * 100) if budget else 0
    pct_days = round(day_of_month / days_in_month * 100)

    lines = [
        f"🌙 *Day {day_of_month}/{days_in_month} — {month}*",
        f"Spent: {fmt_money(spent, currency)} / {fmt_money(budget, currency)}"
        f" ({pct_used}% of budget, {pct_days}% of month gone)",
    ]
    if pace > budget:
        lines.append(
            f"⚠️ Pacing to end at {fmt_money(pace, currency)} — "
            f"{fmt_money(pace - budget, currency)} over budget at this rate."
        )
    else:
        lines.append(f"✅ Pacing to end around {fmt_money(pace, currency)}, under budget.")
    return "\n".join(lines)


async def daily_digest(context: ContextTypes.DEFAULT_TYPE):
    """Daily JobQueue job: push a pacing summary to every chat that's ever
    logged something, so overspending shows up before month-end instead of
    only when you happen to check /total."""
    cfg = load_config()
    text = _build_digest_text(cfg)
    if text is None:
        return

    chat_ids = {r["chat_id"] for r in db.all_rows() if r["chat_id"] is not None}
    for chat_id in chat_ids:
        try:
            await context.bot.send_message(chat_id=chat_id, text=text, parse_mode="Markdown")
        except Exception:
            log.exception("Failed to send daily digest to chat %s", chat_id)


async def digest_cmd(update: Update, context: ContextTypes.DEFAULT_TYPE):
    cfg = load_config()
    text = _build_digest_text(cfg)
    if text is None:
        await update.message.reply_text(
            "Set a monthlyBudget first (via /setbudget) so I have something to pace against."
        )
        return
    await update.message.reply_text(text, parse_mode="Markdown")


# Plain-English questions that don't contain an amount get routed to an
# existing command instead of failing as "couldn't find an amount". Checked
# in order, first match wins — more specific phrasing (category budgets,
# goal) is listed before the generic "budget"/"total" catch-all.
QUERY_INTENTS = [
    (("compare", "vs last month", "last month to this"), "compare"),
    (("category budget", "categories budget", "budget for", "budget per category",
      "category caps", "category wise"), "budget"),
    (("owed", "outstanding", "who owes me", "do i owe"), "owed"),
    (("saving", "savings", "goal"), "goal"),
    (("recent", "last few", "last transaction", "last expense", "history"), "recent"),
    (("categories", "what categories", "list categories"), "categories"),
    (("budget", "how much have i spent", "how much did i spend", "spent so far",
      "total spent", "total this month", "how much left", "remaining",
      "how much can i spend"), "total"),
    (("help", "commands", "what can you do"), "help"),
]


def _detect_query_intent(message_lower: str) -> str:
    for keywords, intent in QUERY_INTENTS:
        if any(kw in message_lower for kw in keywords):
            return intent
    return None


_QUERY_TRIGGER_WORDS = ("how much", "spent", "spend", "budget", "left", "remaining", "total")


def _extract_category_mentioned(message_lower: str, cfg: dict) -> str:
    # \b avoids "rent" matching inside "different"/"parent"/"current" etc.
    for cat in sorted(valid_categories(cfg), key=len, reverse=True):
        if re.search(r"\b" + re.escape(cat) + r"\b", message_lower):
            return cat
    return None


# Picks up "...on <word>" to use as a merchant/keyword search term, e.g.
# "how much have I spent on ola". Only a single word — merchants in this
# tracker's notes are typically one token ("ola", "swiggy", "netflix").
_SEARCH_ON_RE = re.compile(r"\bon\s+([a-z][a-z\-]*)", re.IGNORECASE)


def _extract_search_term(message_lower: str, cfg: dict) -> str:
    m = _SEARCH_ON_RE.search(message_lower)
    if not m:
        return None
    term = m.group(1).lower()
    if term in valid_categories(cfg):
        return None  # handled by the category-specific path instead
    return term


def _log_one_transaction(parsed: dict, chat_id: int, cfg: dict, currency: str) -> str:
    """Insert one already-parsed transaction and return its confirmation
    text. Does NOT call export.run() — the caller does that once, after all
    items in a (possibly multi-item) message are inserted."""
    txn_date = parsed.get("date") or date.today().isoformat()
    date_note = "" if txn_date == date.today().isoformat() else f" [dated {txn_date}]"

    if parsed["type"] in ("lent", "borrowed"):
        person = parsed["counterparty"] or "them"
        note = parsed["note"]
        db.add(
            amount=parsed["amount"], category="lending", note=note,
            txn_type=parsed["type"], chat_id=chat_id,
            counterparty=parsed["counterparty"], settled=0, txn_date=txn_date,
        )
        note_suffix = f" ({note})" if note else ""
        if parsed["type"] == "lent":
            return (
                f"🤝 Logged: you lent {person} {fmt_money(parsed['amount'], currency)}{note_suffix}{date_note}\n"
                f"{person} owes you this back — /owed to track, /settle <id> once repaid."
            )
        return (
            f"🤝 Logged: you borrowed {fmt_money(parsed['amount'], currency)} from {person}{note_suffix}{date_note}\n"
            f"You owe {person} this back — /owed to track, /settle <id> once repaid."
        )

    # Use the entry's own month for before/after totals, not always today's —
    # a backdated entry ("yesterday 500 taxi" on the 1st of the month) should
    # affect the month it actually belongs to, not the month you typed it in.
    month = txn_date[:7]
    before_totals = db.month_total(month)
    before_cat = db.category_totals(month).get(parsed["category"], 0.0)

    db.add(
        amount=parsed["amount"],
        category=parsed["category"],
        note=parsed["note"],
        txn_type=parsed["type"],
        chat_id=chat_id,
        txn_date=txn_date,
    )

    totals = db.month_total(month)
    budget = effective_budget(cfg.get("monthlyBudget", 0), totals["income"])

    if parsed["type"] == "income":
        return (
            f"✅ Logged income: {fmt_money(parsed['amount'], currency)}"
            f" ({parsed['note'] or 'no note'}){date_note}\n"
            f"Total income for {month}: {fmt_money(totals['income'], currency)}"
            f" (was {fmt_money(before_totals['income'], currency)} before this)\n"
            f"Effective monthly budget is now: {fmt_money(budget, currency)}"
        )

    spent = totals["expense"]
    after_cat = db.category_totals(month).get(parsed["category"], 0.0)
    cat_cap = cfg.get("budgets", {}).get(parsed["category"], 0)

    bar = progress_bar(spent, budget)
    remaining = budget - spent
    remaining_str = fmt_money(remaining, currency) if remaining >= 0 else \
        f"-{fmt_money(abs(remaining), currency)} (over budget)"
    reply = (
        f"✅ {parsed['category']} — {fmt_money(parsed['amount'], currency)}"
        f" ({parsed['note'] or 'no note'}){date_note}\n"
        f"{month} so far: {fmt_money(spent, currency)} / {fmt_money(budget, currency)}"
        f" · Remaining: {remaining_str}\n"
        f"{bar}"
    )

    warnings = _threshold_warnings(
        before_totals["expense"], spent, budget,
        before_cat, after_cat, cat_cap, parsed["category"],
        currency,
    )
    if warnings:
        reply += "\n\n" + "\n".join(warnings)
    return reply


# chat_id -> (parsed transaction dict, expiry datetime) for a receipt photo
# awaiting /logreceipt. In-memory only, same tradeoff as _PENDING_UNDO.
_PENDING_RECEIPT = {}
_RECEIPT_CONFIRM_WINDOW = timedelta(minutes=5)


async def handle_photo(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Receipt photo -> OCR -> best-effort amount/category guess, held
    pending until /logreceipt confirms it. Never auto-logs from OCR alone —
    it's too error-prone (blurry photos, multiple totals on one receipt) to
    write to the ledger without a human glancing at the number first."""
    chat_id = update.effective_chat.id
    cfg = load_config()
    currency = cfg.get("currency", "₹")

    photo = update.message.photo[-1]  # last = highest resolution
    tg_file = await photo.get_file()
    photo_bytes = await tg_file.download_as_bytearray()

    try:
        image = Image.open(io.BytesIO(bytes(photo_bytes)))
        text = pytesseract.image_to_string(image)
    except Exception:
        log.exception("OCR failed for chat %s", chat_id)
        await update.message.reply_text(
            "Couldn't read that image — try typing the amount manually, e.g. `495 food`.",
            parse_mode="Markdown",
        )
        return

    parsed = parse_receipt_text(text, extra_categories=cfg.get("customCategories"))
    if parsed["amount"] is None:
        await update.message.reply_text(
            "Couldn't find an amount on that receipt — try typing it manually, e.g. `495 food`.",
            parse_mode="Markdown",
        )
        return

    _PENDING_RECEIPT[chat_id] = (parsed, datetime.now() + _RECEIPT_CONFIRM_WINDOW)
    await update.message.reply_text(
        f"🧾 Detected: {fmt_money(parsed['amount'], currency)} · {parsed['category']}"
        f" ({parsed['note'] or 'no note'})\n\n"
        f"Reply /logreceipt to save this, or /logreceipt <category> to log it under "
        f"a different category. Looks wrong? Just type it manually instead."
    )


async def logreceipt_cmd(update: Update, context: ContextTypes.DEFAULT_TYPE):
    chat_id = update.effective_chat.id
    cfg = load_config()
    currency = cfg.get("currency", "₹")

    pending = _PENDING_RECEIPT.pop(chat_id, None)
    if pending is None or datetime.now() > pending[1]:
        await update.message.reply_text("Nothing pending — send a receipt photo first.")
        return

    parsed, expiry = pending
    if context.args:
        category = context.args[0].lower()
        valid = valid_categories(cfg)
        if category not in valid:
            _PENDING_RECEIPT[chat_id] = (parsed, expiry)  # let them retry without resending
            await update.message.reply_text(
                f"Unknown category '{category}'. Valid: {', '.join(sorted(valid))}"
            )
            return
        parsed["category"] = category

    reply = _log_one_transaction(parsed, chat_id, cfg, currency)
    export.run()
    await update.message.reply_text(reply)


async def handle_message(update: Update, context: ContextTypes.DEFAULT_TYPE):
    message = update.message.text
    chat_id = update.effective_chat.id
    cfg = load_config()
    currency = cfg.get("currency", "₹")

    emi = detect_emi(message)
    if emi is not None:
        # Never guess-log an EMI-worded message — a normal parse would grab
        # the full purchase price as this month's expense (wrong: only one
        # installment happened). Point at /emi instead, which sets up the
        # month-by-month schedule correctly.
        if emi["monthly_amount"] is not None and emi["months"] is not None:
            suggestion = f"/emi {emi['monthly_amount']:.0f} <category> {emi['months']} <note>"
            await update.message.reply_text(
                f"💳 Looks like an EMI purchase — I won't guess and log the full price.\n"
                f"Try: `{suggestion}`\n(fill in a category and note)",
                parse_mode="Markdown",
            )
        else:
            await update.message.reply_text(
                "💳 Looks like an EMI purchase. Use "
                "`/emi <monthly amount> <category> <months> [note]` so I log "
                "one installment at a time instead of the full price.",
                parse_mode="Markdown",
            )
        return

    repay_candidate = detect_repayment_candidate(message)
    if repay_candidate is not None:
        person = repay_candidate["counterparty"]
        matches = _find_outstanding_by_counterparty(chat_id, person, "borrowed")

        if repay_candidate["is_plan"]:
            # A recurring monthly figure ("...5000 every month") is never
            # auto-applied or auto-scheduled — same reasoning as EMI: it's a
            # multi-month commitment, too consequential to guess at.
            amt = repay_candidate["amount"]
            if matches:
                loan = matches[0]
                await update.message.reply_text(
                    f"📅 Looks like a repayment plan to {loan['counterparty']} "
                    f"(you owe {fmt_money(loan['amount'], currency)}).\n"
                    f"Reply `/repayplan {loan['id']} {amt:.0f}` to schedule it monthly, "
                    f"or `/repay {loan['id']} <amount>` for a one-off payment instead.",
                    parse_mode="Markdown",
                )
            else:
                total = repay_candidate["total_guess"]
                borrow_hint = f"/borrow {total:.0f} {person} <note>" if total else f"/borrow <amount owed> {person} <note>"
                await update.message.reply_text(
                    f"📅 Looks like a repayment plan to {person}, but there's no debt logged "
                    f"for them yet. First register what you owe, then schedule the plan:\n"
                    f"1. `{borrow_hint}`\n"
                    f"2. `/repayplan <id from step 1> {amt:.0f}`",
                    parse_mode="Markdown",
                )
            return

        if matches:
            loan = matches[0]  # outstanding_loans() orders oldest first
            if repay_candidate["explicit"]:
                result = db.repay(loan["id"], repay_candidate["amount"], chat_id=chat_id)
                export.run()
                await update.message.reply_text(_format_repay_reply(result, currency))
            else:
                await update.message.reply_text(
                    f"💰 This looks like it could be a repayment to {loan['counterparty']} "
                    f"(you owe {fmt_money(loan['amount'], currency)}).\n"
                    f"Reply `/repay {loan['id']} {repay_candidate['amount']:.0f}` to apply it, "
                    f"or ignore if this was something else.",
                    parse_mode="Markdown",
                )
            return
        # no matching outstanding debt with that name — fall through and
        # log it as a normal transaction below, same as before this feature

    parsed_list = parse_multi(message, extra_categories=cfg.get("customCategories"))
    valid = [p for p in parsed_list if p["amount"] is not None]

    if not valid:
        message_lower = message.lower()
        category = _extract_category_mentioned(message_lower, cfg)
        term = _extract_search_term(message_lower, cfg)
        intent = _detect_query_intent(message_lower)

        if intent == "compare":
            await compare_cmd(update, context)
        elif category and any(kw in message_lower for kw in _QUERY_TRIGGER_WORDS):
            await _category_query_reply(update, category, cfg)
        elif term and any(kw in message_lower for kw in _QUERY_TRIGGER_WORDS):
            await _search_reply(update, term, cfg)
        elif intent == "budget":
            await budget_cmd(update, context)
        elif intent == "owed":
            await owed_cmd(update, context)
        elif intent == "goal":
            await goal_cmd(update, context)
        elif intent == "recent":
            await recent_cmd(update, context)
        elif intent == "categories":
            await categories_cmd(update, context)
        elif intent == "total":
            await total_cmd(update, context)
        elif intent == "help":
            await start(update, context)
        else:
            await update.message.reply_text(
                "Couldn't find an amount, and this didn't look like a question "
                "I recognize either.\n\n"
                "To log spending: `spent 500 on ola` or `1.5k myntra shirt`\n"
                "To ask something: \"what's my budget\", \"how much have I spent\", "
                "\"savings goal progress\", \"recent expenses\"",
                parse_mode="Markdown",
            )
        return

    replies = [_log_one_transaction(parsed, chat_id, cfg, currency) for parsed in valid]
    export.run()

    if len(replies) > 1:
        header = f"📝 Logged {len(replies)} entries from that message:\n\n"
        await update.message.reply_text(header + "\n\n—\n\n".join(replies))
    else:
        await update.message.reply_text(replies[0])


def main():
    cfg = load_config()
    token = cfg.get("telegram_token", "")
    if not token or token == "PUT_YOUR_BOTFATHER_TOKEN_HERE":
        raise SystemExit(
            "Set telegram_token in config.json first (get one from @BotFather)."
        )

    db.init_db()
    export.run()
    start_local_server()

    app = ApplicationBuilder().token(token).build()
    app.add_handler(CommandHandler("start", start))
    app.add_handler(CommandHandler("help", start))
    app.add_handler(CommandHandler("total", total_cmd))
    app.add_handler(CommandHandler("budget", budget_cmd))
    app.add_handler(CommandHandler("find", find_cmd))
    app.add_handler(CommandHandler("compare", compare_cmd))
    app.add_handler(CommandHandler("digest", digest_cmd))
    app.add_handler(CommandHandler("undo", undo_cmd))
    app.add_handler(CommandHandler("recent", recent_cmd))
    app.add_handler(CommandHandler("edit", edit_cmd))
    app.add_handler(CommandHandler("recurring", recurring_cmd))
    app.add_handler(CommandHandler("emi", emi_cmd))
    app.add_handler(CommandHandler("lend", lend_cmd))
    app.add_handler(CommandHandler("borrow", borrow_cmd))
    app.add_handler(CommandHandler("owed", owed_cmd))
    app.add_handler(CommandHandler("settle", settle_cmd))
    app.add_handler(CommandHandler("repay", repay_cmd))
    app.add_handler(CommandHandler("repayplan", repayplan_cmd))
    app.add_handler(CommandHandler("goal", goal_cmd))
    app.add_handler(CommandHandler("export", export_cmd))
    app.add_handler(CommandHandler("backup", backup_cmd))
    app.add_handler(CommandHandler("logreceipt", logreceipt_cmd))
    app.add_handler(CommandHandler("dashboard", dashboard_cmd))
    app.add_handler(CommandHandler("link", link_cmd))
    app.add_handler(CommandHandler("setbudget", setbudget_cmd))
    app.add_handler(CommandHandler("setcatbudget", setcatbudget_cmd))
    app.add_handler(CommandHandler("setgoal", setgoal_cmd))
    app.add_handler(CommandHandler("recommend", recommend_cmd))
    app.add_handler(CommandHandler("categories", categories_cmd))
    app.add_handler(CommandHandler("addcategory", addcategory_cmd))
    app.add_handler(MessageHandler(filters.TEXT & ~filters.COMMAND, handle_message))
    app.add_handler(MessageHandler(filters.PHOTO, handle_photo))

    # once a day, auto-log any recurring bill that's come due
    app.job_queue.run_daily(check_recurring, time=dtime(hour=9, minute=0))
    # once a day, push a budget-pacing summary so overspending shows up
    # before month-end instead of only when you happen to check /total
    app.job_queue.run_daily(daily_digest, time=dtime(hour=20, minute=0))
    # once a week (Sunday night), push a DB+config backup so history survives
    # a corrupted disk even if /backup is never run manually
    app.job_queue.run_daily(weekly_backup, time=dtime(hour=21, minute=0), days=(6,))

    log.info("Bot starting...")
    app.run_polling()


if __name__ == "__main__":
    main()
