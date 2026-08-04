# Expense terminal

A personal, fully offline expense tracker you run entirely from Telegram.
You text a bot in plain English, it parses the amount and category and
saves it to a local SQLite file, and an HTML dashboard (no server, no
internet) always shows the latest picture.

Nothing leaves your machine except the messages you already send to your
own Telegram bot. All storage is a single file: `expenses.db`.

## How it works

```
you (Telegram) → bot.py → parser.py → db.py (expenses.db)
                                          ↓
                                     export.py → data.js
                                          ↓
                                   dashboard.html (open in any browser)
```

Every time you send a message, `bot.py` parses it, stores it, and
regenerates `data.js`. `dashboard.html` loads `data.js` with a plain
`<script src="data.js">` tag — not `fetch()` — so double-clicking the
file and opening it works even with zero network access.

## Setup (5 steps)

**1. Get a bot token from BotFather**
Open Telegram, message [@BotFather](https://t.me/BotFather), send
`/newbot`, and follow the prompts. It gives you a token that looks like
`123456789:AAF...`.

**2. Fill in `config.json`**
Open `config.json` and paste your token into `telegram_token`. While
you're there, set `monthlyBudget` and the per-category `budgets` to
whatever caps make sense for you. Currency defaults to `₹` — change it
to `$`, `€`, etc. if you want; it's used everywhere automatically.

**3. Install dependencies**
```bash
pip install -r requirements.txt --break-system-packages
```
(or drop `--break-system-packages` if you're using a virtualenv, which
is fine too).

**4. Run the bot**
```bash
python bot.py
```
Leave this running (in a terminal, a `screen`/`tmux` session, or as a
background service) — it's what listens for your Telegram messages.
On a phone/PC without a spare server, this can run on a Raspberry Pi,
an old laptop, or your own always-on machine; it never talks to
anything except Telegram's API.

**5. Open the dashboard**
Double-click `dashboard.html` (or open it via your browser's File →
Open). It reads `data.js`, which sits next to it and updates itself
after every message you send. No server needed — refresh the page any
time to see the latest numbers.

## Example messages

```
spent 500 on ola
swiggy 420 dinner
1.5k myntra shirt
2l invested in mutual fund
rs 200 chai
₹1,250 blinkit groceries
500rs netflix
got salary 75000
received cashback 150
```

The parser understands:
- **Amounts**: `500`, `1,250`, `1.5k` (= 1500), `2l` (= 200000), `rs 500`,
  `₹500`, `500rs`.
- **Categories** (edit the keyword lists in `parser.py` any time):
  travel, food, groceries, clothes, rent, bills, luxuries, fitness,
  investments, health, education, other.
- **Income**: salary, refund, cashback, received, credited, bonus,
  reimbursement, and similar words flip the entry to `type: income`
  instead of an expense.

## Bot commands

- `/start`, `/help` — quick reminder of how to log spends
- `/total` — this month's spend vs budget with a text progress bar (budget
  is capped at your logged income too, see "Income-aware budget" below)
- `/budget` — every category's cap and how much you've used
- `/setbudget <amount>` — change the overall monthly budget, e.g. `/setbudget 45000`
- `/setcatbudget <category> <amount>` — change one category's cap, e.g. `/setcatbudget food 7000`
- `/setgoal <amount> [label]` — change the savings goal
- `/undo` — deletes the most recent entry (per Telegram chat)
- `/recent` — last 10 entries with their ids, so you know what to `/edit`
- `/edit <id> <amount|category|note> <value>` — fix a past entry, e.g.
  `/edit 12 amount 450`
- `/recurring add <amount> <category> <day 1-28> <note>` — register a bill
  (rent, subscriptions, …) that auto-logs itself every month; also
  `/recurring list` and `/recurring remove <id>`
- `/goal` — this month's savings goal progress (needs `savingsGoal` set in
  `config.json`)
- `/recommend` — a suggested per-category budget split for your current
  budget (see "Budget recommendations" below); `/recommend apply` adopts it
- `/export [YYYY-MM]` — sends a CSV of that month's (or all) transactions
- `/dashboard` — sends a standalone `dashboard.html` with today's data baked
  in, no second file needed — good for offline/away-from-home-WiFi use
- `/link` — the URL of the always-live dashboard on your home WiFi (see
  "Live dashboard on your phone" below)

The bot also proactively warns you in the chat when a new expense pushes
your monthly total or a category past 80% or 100% of its cap — you don't
have to run `/total`/`/budget` to find out.

## Income-aware budget

`monthlyBudget` in `config.json` is a ceiling, not a target: the bot and
dashboard actually cap you at `min(monthlyBudget, income logged this
month)`, so you're never shown a budget bigger than what you've actually
earned that month. Before any income is logged for the month, it falls
back to the configured `monthlyBudget` so the cap doesn't collapse to 0
before payday.

## Recurring bills

`/recurring add` stores a bill with a day-of-month it should fire. A
background job (via `python-telegram-bot`'s `JobQueue`) checks once a day
and auto-logs any bill that's come due and hasn't already fired that
month, then messages you that it did. This needs the `job-queue` extra —
see Setup step 3.

## Savings goal

Set `savingsGoal: {"amount": ..., "label": ...}` in `config.json` to track
a monthly savings target (net = income − expense so far this month) via
`/goal` and the dashboard's "Savings goal" panel. Omit the key (or set
`amount` to 0) to hide it.

## Budget recommendations

`/recommend` splits your effective monthly budget (income-aware, see
above) across categories using a fixed rule-of-thumb weighting — needs
52% (rent, bills, groceries, health, travel), wealth-building 20%
(investments — paid before lifestyle spend, not after), wants 28% (food,
fitness, clothes, luxuries, education, other). It's weighted toward rent
being the largest fixed cost rather than a plain 50/30/20, since that's
typically true in India; edit `RECOMMENDED_ALLOCATION` in `bot.py` if your
situation is different. It also flags categories where your current caps
differ a lot from the recommendation, and warns if your caps already sum
to more than your budget. `/recommend apply` writes the suggested numbers
straight into `config.json`'s `budgets`.

## Live dashboard on your phone

`bot.py` also runs a small HTTP server (port 8000 by default —
`LOCAL_SERVER_PORT` in `bot.py`) bound to your LAN, serving *only*
`dashboard.html` + `data.js` from a dedicated `public_dashboard/` folder
that `export.py` keeps in sync — never the project root, so
`config.json` (your bot token) and `expenses.db` are never reachable over
the network. Run `/link` to get the current URL (same WiFi as the machine
running the bot only) and just reload the page for fresh numbers, instead
of re-requesting a file each time. Not on that WiFi? `/dashboard` sends a
one-off offline snapshot instead.

## Files

| File | Purpose |
|---|---|
| `parser.py` | Turns a message into `{amount, category, note, type}`. Edit `CATEGORY_KEYWORDS` / `INCOME_KEYWORDS` here to teach it new merchants. |
| `db.py` | SQLite storage (`expenses.db`) — transactions (`add`, `undo_last`, `get_by_id`, `update`, `all_rows`, `month_total`, `category_totals`) and recurring bills (`add_recurring`, `list_recurring`, `remove_recurring`, `due_recurring`, `mark_recurring_run`). |
| `export.py` | Reads the DB + `config.json`, writes `data.js` and syncs `public_dashboard/` for the dashboard; can also write a CSV (`export_csv()`) or a standalone single-file dashboard (`bundle_standalone_dashboard()`). Never includes the bot token. |
| `bot.py` | The Telegram bot itself — wires parser → db → export → reply together, plus the daily recurring-bill job and the local LAN dashboard server. |
| `config.json` | Your bot token, currency, budget caps, and savings goal. |
| `dashboard.html` | The offline dashboard. Self-contained, no CDN, no build step, mobile-friendly. |
| `data.js` | Auto-generated by `export.py` — don't edit by hand. |
| `public_dashboard/` | Auto-generated copy of `dashboard.html` + `data.js` — the only two files the local LAN server serves. Don't edit by hand. |

## Adjusting things

- **Change currency/categories**: everything reads `currency` and
  `categories` from `config.json` / `parser.py`, so swapping `₹` for `$`
  or renaming categories doesn't require touching the dashboard.
- **New merchant keyword**: add it to the right list in
  `CATEGORY_KEYWORDS` in `parser.py` — no restart logic needed beyond
  restarting `bot.py`.
- **Change budgets or savings goal**: use `/setbudget`, `/setcatbudget`,
  or `/setgoal` from Telegram (no restart needed), or edit `config.json`
  by hand and either restart `bot.py` or just wait for the next message
  (config is re-read on every message either way).
- **Back up your data**: `expenses.db` is the only file that matters —
  copy it anywhere you like.

## Testing it yourself

Both `parser.py` and `db.py` can be run directly for a quick smoke test:
```bash
python parser.py   # prints parsed output for a handful of sample messages
python db.py        # inserts/reads/undoes a few rows against expenses.db
```
