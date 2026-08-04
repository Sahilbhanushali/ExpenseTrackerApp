"""
bot.py — Telegram front-end for the expense tracker.

Every plain-text message is parsed (parser.py), stored (db.py), and the
dashboard's data.js is regenerated (export.py) before replying. Nothing
here ever talks to the network except Telegram's own API — no other
service is contacted, and the token lives only in config.json.

Commands:
    /start   welcome + quick examples
    /help    same as /start
    /total   this month's spend vs budget, with a text progress bar
    /budget  show every category's cap and this month's usage
    /undo    delete the most recently logged entry (per-chat)
"""

import json
import logging
from datetime import date
from pathlib import Path

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
from parser import parse_message

BASE_DIR = Path(__file__).parent
CONFIG_PATH = BASE_DIR / "config.json"

logging.basicConfig(
    format="%(asctime)s %(levelname)s %(name)s: %(message)s", level=logging.INFO
)
log = logging.getLogger("expense-bot")


def load_config() -> dict:
    with open(CONFIG_PATH, "r", encoding="utf-8") as f:
        return json.load(f)


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
        "/undo — delete the last entry\n"
    )
    await update.message.reply_text(text, parse_mode="Markdown")


async def total_cmd(update: Update, context: ContextTypes.DEFAULT_TYPE):
    cfg = load_config()
    currency = cfg.get("currency", "₹")
    month = date.today().isoformat()[:7]
    totals = db.month_total(month)
    spent = totals["expense"]
    budget = cfg.get("monthlyBudget", 0)

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

    db.add(
        amount=parsed["amount"],
        category=parsed["category"],
        note=parsed["note"],
        txn_type=parsed["type"],
        chat_id=chat_id,
    )
    export.run()

    month = date.today().isoformat()[:7]
    totals = db.month_total(month)
    budget = cfg.get("monthlyBudget", 0)

    if parsed["type"] == "income":
        reply = (
            f"✅ Logged income: {fmt_money(parsed['amount'], currency)}"
            f" ({parsed['note'] or 'no note'})"
        )
    else:
        spent = totals["expense"]
        bar = progress_bar(spent, budget)
        reply = (
            f"✅ {parsed['category']} — {fmt_money(parsed['amount'], currency)}"
            f" ({parsed['note'] or 'no note'})\n"
            f"Month so far: {fmt_money(spent, currency)} / {fmt_money(budget, currency)}\n"
            f"{bar}"
        )

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
    app.add_handler(MessageHandler(filters.TEXT & ~filters.COMMAND, handle_message))

    log.info("Bot starting...")
    app.run_polling()


if __name__ == "__main__":
    main()
