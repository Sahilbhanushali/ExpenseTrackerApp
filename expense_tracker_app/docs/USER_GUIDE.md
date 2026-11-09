# Expense Tracker User Guide

How to set the app up once, use it every day, and run each salary cycle. It also shows,
step by step, how **Smart allocation** decides where your money goes.

> Every rupee lives in exactly one **account**. Savings, emergency money, goals and
> investments aren't separate piles: they're accounts, or earmarks on accounts. The app
> counts each rupee once and never spends the same money twice.

---

## 1. One-time setup (about 15 minutes)

Do these in order. Each step makes the next one smarter.

| # | Where | What to enter | Why it matters |
|---|-------|---------------|----------------|
| 1 | More → **Accounts** | Every bank account, wallet and cash, with today's balance. Give each one its **roles**: *Salary*, *Daily spending*, *Savings*, *Emergency fund*, *Investing*. | Roles decide what counts as spendable. Money in Savings, Emergency or Investing accounts is never offered for spending. |
| 2 | More → **Salary & cycles** → Salary details | Take-home pay, usual pay days (e.g. 7th–15th), the account it lands in. | Sets the **cycle** (salary day to the day before the next salary) and the allocation *horizon*. |
| 3 | More → **Budgets** | Monthly (or weekly/daily) budgets per category. Mark groceries, rent, transport, medicine and similar as **essential**. | Essential budgets are funded first. They also set your emergency-fund target. |
| 4 | More → **Credit cards** | Each card's limit, statement day and repayment account. Add the latest statement (total due, minimum, due date). | Card dues become obligations, and an overdue balance is treated as urgent. |
| 5 | More → **Loans & EMI** | Each loan or card EMI: amount, EMI, tenure, start date, paying account. | The app generates the schedule, and each installment becomes a dated obligation. |
| 6 | More → **Recurring bills** | Rent, internet, phone, subscriptions and SIPs you pay manually, each with its day of month. | These become obligations and get their own reminders. |
| 7 | More → **Emergency fund** | A target as 3/6/9/12 months of essentials or a custom amount, plus an optional monthly contribution. | Allocation plans this contribution until the target is reached. |
| 8 | More → **Savings goals** | Each goal: target, date, priority, the savings account it sits in, and a monthly amount. | Short-term goals are planned under *Savings*; long-term ones under *Investing*. |
| 9 | More → **Investments** | Holdings per investment account, with their current value as of a date. | Feeds net worth. No live prices and no promised returns. |
| 10 | More → **Smart allocation** → settings | Priority order, savings per cycle, investing per cycle (SIP). | Decides who gets paid first when money is short. |
| 11 | More → **Financial calendar** → 🔔 | Reminders on, and how many days before (on the day / 1 / 3 / 7). | One reminder per EMI, card due, statement day and expected income, with no duplicates. |
| 12 | More → **Spending Guardian** (Android) | Grant the usage and overlay permissions, and pick apps (GPay, Paytm, CRED, slice…). | Shows your budget left the moment you open a payment app. |

---

## 2. How Smart allocation works

### 2.1 Side by side: what you do and what the app does

| Step | You | The app |
|------|-----|---------|
| 1 | Salary arrives. Tap **Record salary** (Salary & cycles), or add it as Income. | Starts a new cycle from that date. Adds the salary to the salary account's balance, once. |
| 2 | Open **Smart allocation**. | Works out **Available** (see 2.2). |
| 3 | — | Collects every **need** due before your next expected salary (the *horizon*): budgets, bills, EMIs, card dues, emergency, goals, SIP. |
| 4 | — | Walks the **priority order** and funds each need in turn until the money runs out (see 2.3). |
| 5 | — | Shows a **shortfall card** if anything important can't be covered. It never shows a fake balanced plan. |
| 6 | Review each line: **Approve**, **Approve all**, **Edit** (amount or destination), or **Skip**. | Approving *reserves* the money. Nothing moves yet. If the money should sit elsewhere (e.g. Savings), it records a **planned transfer**. |
| 7 | Do the actual transfer in your bank or UPI app, then tap **Transfer done**. | Moves the balance between the two accounts. A transfer is never counted as spending. |
| 8 | Pay the bill, EMI or card as usual and log it. | The reservation for that need is **released automatically**, because the need is gone. |
| 9 | Extra income arrives mid-cycle. | It simply raises Available. Earlier approvals stay. Reopen allocation to place the new money. |

### 2.2 What "Available" means

```
Available =  balance of spendable accounts      (salary, daily, cash, wallets)
           − money on hold                      (e.g. a pending refund / blocked amount)
           − money already reserved             (approved, still sitting in that cash)
```

What's **not** counted:
- Savings, Emergency fund and Investing accounts. That money is already set aside.
- Salary added a second time. It's already inside the account balance.
- Expected or late salary. Only money you actually have counts.

### 2.3 Priority order (you can reorder it in settings)

| Order | Bucket | What's inside | Funded with |
|-------|--------|---------------|-------------|
| 1 | **Essentials** | What's left of *essential* category budgets | Budget − spent so far |
| 2 | **Bills, EMIs & card dues** | Recurring bills, loan installments and card statements due before the horizon, plus anything overdue | The amount due |
| 3 | **Emergency fund** | Gap to target, capped by your monthly contribution | e.g. ₹2,000 |
| 4 | **Short-term savings** | Savings per cycle plus short-term goals | Goal pace |
| 5 | **Investing** | SIP per cycle plus long-term goals | Plan amount |
| 6 | **Discretionary** | What's left of non-essential budgets (eating out, shopping…) | Budget − spent |
| — | **Unallocated buffer** | Whatever remains | Always last |

Safety rules applied on top of the order:
- **Overdue card debt jumps the queue.** If a card balance is past its due date (interest is
  running), it's funded before savings, investing and discretionary, whatever order you set.
- **Investing guard.** Investing is skipped while any essential or due item is short, or a
  card is overdue. You don't invest borrowed money.
- **Never over-allocates.** The total proposed is always ≤ Available.
- **Shortfall, not fiction.** If ₹X can't be covered, you see ₹X short, the top unmet needs,
  and which discretionary budgets you could trim.

### 2.4 Worked example: the ₹19,000 cycle

Salary of **₹19,000** lands on **10 Nov** in *HDFC Salary*. That account already held
₹2,000, so its balance is ₹21,000. Nothing is on hold or reserved. The next salary is
expected between 7 and 15 Dec, so the horizon is **15 Dec**.

**Available = ₹21,000**

| # | Need | Bucket | Required | Funded | Left after |
|---|------|--------|---------:|-------:|-----------:|
| 1 | Groceries (essential budget) | Essentials | 4,000 | 4,000 | 17,000 |
| 2 | Transport (essential budget) | Essentials | 1,500 | 1,500 | 15,500 |
| 3 | HDFC card bill, due 18 Nov | Obligations | 3,200 | 3,200 | 12,300 |
| 4 | Rent, 1 Dec | Obligations | 6,000 | 6,000 | 6,300 |
| 5 | Fridge EMI, 5 Dec | Obligations | 1,500 | 1,500 | 4,800 |
| 6 | Emergency fund (₹40,000 gap, ₹2,000/month cap) | Emergency | 2,000 | 2,000 | 2,800 |
| 7 | Goa trip goal | Savings | 1,500 | 1,500 | 1,300 |
| 8 | Index fund SIP | Investing | 2,000 | 1,300 | 0 |
| 9 | Eating out (budget) | Discretionary | 2,000 | 0 | 0 |

The result:
- Everything essential and due is covered, so investing is **allowed** and gets the last ₹1,300.
- **Shortfall: ₹2,700** (SIP short ₹700, eating out short ₹2,000). The app suggests trimming
  eating out or lowering the SIP this cycle.
- Approving the emergency line records a **planned transfer** of HDFC Salary → Emergency
  of ₹2,000, and approving the Goa line records HDFC Salary → Savings of ₹1,500 (tagged
  to the goal). Tap **Transfer done** after you actually move the money.

**The same month, if your salary is ₹6,000 short:** Available is ₹15,000. Lines 1–5
(₹16,200) can't all be covered, so the obligations show ₹1,200 short. Emergency, savings
and **investing are skipped** under the investing guard, and the shortfall card lists the
rent and EMI first, by due date.

**Mid-cycle freelance payment of ₹5,000 on 20 Nov:** Available goes up by ₹5,000. Your
approvals stay. Open allocation again and the SIP and eating-out gaps get covered.

---

## 3. Daily routine (under a minute)

| When | Do this | Tip |
|------|---------|-----|
| Whenever you spend | Tap **+** → **Quick** and type naturally, e.g. `spent 500 on ola`, or use **Form** for amount, category and account. | Long-press the app icon → **Add expense** to skip the home screen. |
| Paid by credit card | Pick the card as the account. | Increases the card balance, not a bank balance, so nothing is counted twice when you pay the bill. |
| Got money | **+** → **Income**, e.g. `got salary 75000`. | Use *Record salary* for salary so a cycle starts. |
| Refund received | Open the original expense → **Record a refund**. | Reduces that category's spending without hiding the original purchase. |
| Moved money between your accounts | Accounts → **Transfer**. | Transfers are never spending. |
| Lent or borrowed | More → **Owed**. | Keeps it out of expenses and income. |
| Opening GPay, CRED and similar | Glance at the Guardian popup. | It shows what's left in your budgets before you pay. |
| SMS from your bank | More → **SMS import** → review. | You confirm each one; nothing is added silently. |

On Home, check **Coming up this week**. It shows the next dues, and anything overdue in red.

---

## 4. Weekly routine (5 minutes)

1. **Financial calendar → 7 days.** Is there enough in the paying accounts for what's due?
2. **Budgets.** If a category is running hot, decide now. Trim it, or accept less in a
   lower-priority bucket.
3. **Accounts → open an account → Check against bank** for one or two accounts, comparing with your bank app. Any difference is
   recorded as a visible adjustment, never hidden.
4. **Smart allocation.** Mark any transfers you've done as **Transfer done**.

---

## 5. Each salary cycle

| When | What to do | Screen |
|------|------------|--------|
| Salary day | **Record salary**. If your opening balance already included this salary, switch on **Already in my opening balance** so it isn't counted twice. | Salary & cycles |
| Same day | Open **Smart allocation**, review, then **Approve all** or edit lines. | Smart allocation |
| Same day | Do the planned transfers (Savings, Emergency, SIP) in your bank, then **Transfer done**. | Smart allocation |
| Statement day | Add the card statement (total, minimum, due date). | Credit cards |
| Before each due date | Pay EMIs, cards and bills, and log the payment. The reservation releases itself. | Loans / Cards / Recurring |
| Last day | **Check against bank** on the main accounts. | Accounts |
| After the cycle ends | **Close cycle**. Review income, spending, balances and anything still owed, then choose what to do with the **leftover**: carry forward, savings, emergency, extra loan principal, card paydown, investments, keep as cash, or a split. | Salary & cycles → Close |

About closing:
- **Leftover** = the smaller of (cycle income − spending) and your unallocated spendable
  cash today. Deciding on a cycle's leftover never spends the next salary.
- A closed cycle is **frozen**. Later edits to old transactions don't silently change
  it, and the app tells you if history changed after closing. You can **Reopen** it if
  you need to.
- Unpaid obligations stay owed after closing. They're never reset.

---

## 6. Reading the main numbers

| Number | Means | Does **not** mean |
|--------|-------|-------------------|
| Left from this cycle's income | Cycle income − cycle spending | Safe to spend. Bills and dues may still be ahead. |
| Available (allocation) | Spendable cash − holds − reserved | Total money you own |
| Net worth | All accounts + investment worth − card and loan debt | Cash in hand |
| Emergency coverage | Emergency balance ÷ essential spending per month | A separate pot. It's your emergency accounts' balance. |
| Goal saved | Starting amount + done transfers to the goal − withdrawals | Money outside its account |
| Investment gain | Your entered value − amount put in, as of your date | A forecast |

---

## 6a. The Home dashboard

| Block | What it shows |
|-------|---------------|
| **Net worth** | Everything you own minus everything you owe. Tap the eye to hide amounts. |
| **In bank & cash / Reserved / Available** | Actual balance of spending accounts · money approved for bills and plans · what's truly free (bank & cash − on hold − reserved). Tap to open Smart allocation. |
| Chips | Savings, emergency fund, investments, owed to you, you owe, cards, loans. Each opens its screen. |
| **Cycle plan** (cycle view) | Allocated so far · unallocated now · due before payday. If dues are more than allocated plus free money, it tells you. |
| **Insights** | Up to 3 most urgent: overdue payments, shortfall before payday, budgets over or near the limit, spending vs the same point last month or cycle, biggest category jump, share of income kept, money moved to savings. Reports shows all of them for any range. |
| **Debt** | Card outstanding with the next due and statement, loans with the next EMI, money you owe people, anything overdue. |
| **Wealth** | Emergency fund progress and coverage, goals saved vs target, investments and planned monthly contribution, and the net worth trend (it builds month by month from now). |

## 7. Troubleshooting

| Symptom | Fix |
|---------|-----|
| Salary counted twice | On the cycle, switch on **Already in my opening balance**, or delete the duplicate income. |
| Allocation says ₹0 available | Check account roles. Only *Salary*, *Daily* and cash accounts are spendable. |
| A paid bill still shows as due | Log the payment against that bill, EMI or card. For a card, pay against the statement. |
| Reminder came for something already paid | Open the app once. Reminders resync on every change, and stale ones are cancelled. |
| Two reminders for one bill | Recurring bills use their own reminder, and the calendar skips them. Turn one off in Reminders if needed. |
| Balance differs from the bank | Open the account → **Check against bank**. It records the difference as an adjustment. |
