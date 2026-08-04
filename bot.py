"""
bot.py — Telegram front-end for the expense tracker.

Every plain-text message is parsed (parser.py), stored (db.py), and the
dashboard's data.js is regenerated (export.py) before replying. Nothing
here ever talks to the network except Telegram's own API — no other
service is contacted, and the token lives only in config.json.

Commands:
    /start      welcome + quick examples
    /help       same as /start
    /total      this month's spend vs budget, with a text progress bar
    /budget     show every category's cap and this month's usage
    /setbudget      change the overall monthly budget
    /setcatbudget   change one category's budget
    /setgoal        change the savings goal amount/label
    /undo       delete the most recently logged entry (per-chat)
    /recent     last 10 entries with their ids
    /edit       fix an existing entry's amount/category/note
    /recurring  manage auto-logged monthly bills (add/list/remove)
    /goal       this month's savings goal progress
    /export     [YYYY-MM] send transactions as a CSV file
    /dashboard  zip up dashboard.html + fresh data.js and send it

A daily JobQueue job checks for due recurring bills and logs them
automatically — see check_recurring() and main()'s job_queue.run_daily.
"""

import json
import logging
from datetime import date, datetime
from pathlib import Path

from datetime import time as dtime

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
from parser import parse_message, CATEGORY_KEYWORDS

BASE_DIR = Path(__file__).parent
CONFIG_PATH = BASE_DIR / "config.json"

logging.basicConfig(
    format="%(asctime)s %(levelname)s %(name)s: %(message)s", level=logging.INFO
)
log = logging.getLogger("expense-bot")


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
        "  • `got salary 75000`\n\n"
        "Commands:\n"
        "/total — this month vs budget\n"
        "/budget — per-category caps\n"
        "/setbudget <amount> — change monthly budget\n"
        "/setcatbudget <cat> <amount> — change a category's cap\n"
        "/setgoal <amount> [label] — change savings goal\n"
        "/undo — delete the last entry\n"
        "/recent — last 10 entries with their ids\n"
        "/edit <id> <field> <value> — fix an entry\n"
        "/recurring add|list|remove — auto-log monthly bills\n"
        "/goal — savings goal progress\n"
        "/export [YYYY-MM] — download transactions as CSV\n"
        "/dashboard — get dashboard.html + data.js zipped, ready for your phone\n"
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
    if len(args) != 2 or args[0].lower() not in VALID_CATEGORIES or \
            (amount := _parse_amount_arg(args[1])) is None:
        await update.message.reply_text(
            "Usage: /setcatbudget <category> <amount>\n"
            "e.g. /setcatbudget food 7000\n"
            f"Valid categories: {', '.join(sorted(VALID_CATEGORIES))}"
        )
        return

    category = args[0].lower()
    cfg = load_config()
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


async def dashboard_cmd(update: Update, context: ContextTypes.DEFAULT_TYPE):
    path = export.bundle_dashboard()
    try:
        with open(path, "rb") as f:
            await update.message.reply_document(
                document=f,
                filename="dashboard.zip",
                caption=(
                    "📊 dashboard.html + data.js, zipped together and up to date.\n"
                    "Unzip on your phone (keep both files in the same folder) and "
                    "open dashboard.html in a browser."
                ),
            )
    finally:
        path.unlink(missing_ok=True)


async def undo_cmd(update: Update, context: ContextTypes.DEFAULT_TYPE):
    chat_id = update.effective_chat.id
    row = db.undo_last(chat_id=chat_id)
    export.run()
    if row is None:
        await update.message.reply_text("Nothing to undo.")
        return
    cfg = load_config()
    currency = cfg.get("currency", "₹")
    await update.message.reply_text(
        f"🗑️ Removed: {row['category']} {fmt_money(row['amount'], currency)}"
        f" ({row['note'] or 'no note'})"
    )


def _crossed(before: float, after: float, cap: float, frac: float) -> bool:
    """True if this transaction is what pushed `before`->`after` across
    `cap * frac` — so alerts fire once, right when the threshold is crossed,
    not on every message after."""
    return cap > 0 and before < cap * frac <= after


def _threshold_warnings(before_spent, after_spent, budget,
                         before_cat, after_cat, cat_cap, category) -> list:
    warnings = []
    if _crossed(before_spent, after_spent, budget, 1.0):
        warnings.append("🚨 Over monthly budget!")
    elif _crossed(before_spent, after_spent, budget, 0.8):
        warnings.append("⚠️ 80% of monthly budget used.")

    if _crossed(before_cat, after_cat, cat_cap, 1.0):
        warnings.append(f"🚨 Over budget for {category}!")
    elif _crossed(before_cat, after_cat, cat_cap, 0.8):
        warnings.append(f"⚠️ 80% of {category} budget used.")
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
        sign = "+" if r["type"] == "income" else "-"
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


VALID_CATEGORIES = set(CATEGORY_KEYWORDS.keys()) | {"other"}


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
            lines.append(
                f"#{r['id']} · day {r['day_of_month']} · {r['category']} · "
                f"{fmt_money(r['amount'], currency)} · {r['note'] or 'no note'}"
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
        if category not in VALID_CATEGORIES:
            await update.message.reply_text(
                f"Unknown category '{category}'. Valid: {', '.join(sorted(VALID_CATEGORIES))}"
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
        db.add(
            amount=r["amount"],
            category=r["category"],
            note=r["note"],
            txn_type="expense",
            chat_id=r["chat_id"],
        )
        db.mark_recurring_run(r["id"], month)
        try:
            await context.bot.send_message(
                chat_id=r["chat_id"],
                text=(
                    f"🔁 Auto-logged recurring bill: {r['category']} "
                    f"{fmt_money(r['amount'], currency)} ({r['note'] or 'no note'})"
                ),
            )
        except Exception:
            log.exception("Failed to notify chat %s about recurring bill #%s", r["chat_id"], r["id"])

    export.run()


async def handle_message(update: Update, context: ContextTypes.DEFAULT_TYPE):
    message = update.message.text
    chat_id = update.effective_chat.id
    cfg = load_config()
    currency = cfg.get("currency", "₹")

    parsed = parse_message(message)

    if parsed["amount"] is None:
        await update.message.reply_text(
            "Couldn't find an amount in that — try something like "
            "`spent 500 on ola` or `1.5k myntra shirt`.",
            parse_mode="Markdown",
        )
        return

    month = date.today().isoformat()[:7]
    before_totals = db.month_total(month)
    before_cat = db.category_totals(month).get(parsed["category"], 0.0)

    db.add(
        amount=parsed["amount"],
        category=parsed["category"],
        note=parsed["note"],
        txn_type=parsed["type"],
        chat_id=chat_id,
    )
    export.run()

    totals = db.month_total(month)
    budget = effective_budget(cfg.get("monthlyBudget", 0), totals["income"])

    if parsed["type"] == "income":
        reply = (
            f"✅ Logged income: {fmt_money(parsed['amount'], currency)}"
            f" ({parsed['note'] or 'no note'})"
        )
    else:
        spent = totals["expense"]
        after_cat = db.category_totals(month).get(parsed["category"], 0.0)
        cat_cap = cfg.get("budgets", {}).get(parsed["category"], 0)

        bar = progress_bar(spent, budget)
        reply = (
            f"✅ {parsed['category']} — {fmt_money(parsed['amount'], currency)}"
            f" ({parsed['note'] or 'no note'})\n"
            f"Month so far: {fmt_money(spent, currency)} / {fmt_money(budget, currency)}\n"
            f"{bar}"
        )

        warnings = _threshold_warnings(
            before_totals["expense"], spent, budget,
            before_cat, after_cat, cat_cap, parsed["category"],
        )
        if warnings:
            reply += "\n\n" + "\n".join(warnings)

    await update.message.reply_text(reply)


def main():
    cfg = load_config()
    token = cfg.get("telegram_token", "")
    if not token or token == "PUT_YOUR_BOTFATHER_TOKEN_HERE":
        raise SystemExit(
            "Set telegram_token in config.json first (get one from @BotFather)."
        )

    db.init_db()
    export.run()

    app = ApplicationBuilder().token(token).build()
    app.add_handler(CommandHandler("start", start))
    app.add_handler(CommandHandler("help", start))
    app.add_handler(CommandHandler("total", total_cmd))
    app.add_handler(CommandHandler("budget", budget_cmd))
    app.add_handler(CommandHandler("undo", undo_cmd))
    app.add_handler(CommandHandler("recent", recent_cmd))
    app.add_handler(CommandHandler("edit", edit_cmd))
    app.add_handler(CommandHandler("recurring", recurring_cmd))
    app.add_handler(CommandHandler("goal", goal_cmd))
    app.add_handler(CommandHandler("export", export_cmd))
    app.add_handler(CommandHandler("dashboard", dashboard_cmd))
    app.add_handler(CommandHandler("setbudget", setbudget_cmd))
    app.add_handler(CommandHandler("setcatbudget", setcatbudget_cmd))
    app.add_handler(CommandHandler("setgoal", setgoal_cmd))
    app.add_handler(MessageHandler(filters.TEXT & ~filters.COMMAND, handle_message))

    # once a day, auto-log any recurring bill that's come due
    app.job_queue.run_daily(check_recurring, time=dtime(hour=9, minute=0))

    log.info("Bot starting...")
    app.run_polling()


if __name__ == "__main__":
    main()
