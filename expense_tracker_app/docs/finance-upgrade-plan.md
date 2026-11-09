# Personal Finance Upgrade — Audit & Roadmap

Status: **Phases 1–5 complete. Next: Phase 6 (bank account details and reconciliation), awaiting review.**
Living document: each phase updates its section (schema changes, decisions, test results).

---

## 1. Current architecture (as found)

| Area | What exists | Notes |
|---|---|---|
| Persistence | `sqflite`, single DB `expenses.db`, schema **v12**, versioned `onUpgrade` steps, migration tests (`paise_migration_test.dart`) | Config lives separately in `config.json` (`ConfigRepository`). Backup/restore copies the DB file, so new tables are backed up automatically. |
| Money | Integer paise everywhere since v11 (`money.dart`, `formatMoney`) | Good. Keep. |
| State | `provider` ChangeNotifier controllers per feature; repositories under `lib/data` | Keep. New modules follow the same shape. |
| Ledger | `txns` (expense / income / lent / borrowed, `CHECK` constraint on `type`) + `transfers` (from/to account **name**) | One table mixes consumption, debt and cash movement. No refund, card, principal/interest, savings or adjustment concept. |
| Accounts | `accounts` (name, opening balance, type cash/investment/emergencyFund, optional manual `current_value`, default flag). Balance = opening ± txns ± transfers, computed on read | Name is the join key (`txns.account`, `transfers.*_account`); renames cascade. No bank name, last-4, roles, status, reconciliation. |
| Budgets | `config.monthlyBudgetPaise` + per-category caps in `config.budgets`; calendar month only; 80%/100% warnings (`budget_alerts.dart`, Guardian) | No salary cycle, weekly, daily or custom budgets. |
| Loans (EMI) | `loans` table: principal, flat `interest_amount`, emi, tenure, installments_paid; `payInstallment` logs **full EMI as an expense** | Outstanding = (principal + interest) − emi × paid. No rate, schedule, prepayment, partial payment, fees, frequency. |
| EMI via recurring | `recurring` with `installments_remaining` + `logEmi` (logs first installment as expense, rest as reminders) | **Second, parallel EMI system.** |
| Person-to-person lending | `txns` lent/borrowed + `loan_payments`; repayment **reduces the original row's amount in place** | |
| Goals | `goals` (name, target); contribution = **expense** txn with `goal_id` | |
| Wishlist | purchase logs an expense | Fine. |
| "Expense splitter" | Accounts → *Distribute*: typed amount, "minimum to keep", fixed % per account (20% default), immediately writes completed transfers | |
| Credit cards | **None.** | |
| Recurring bills | `recurring`, due list on launch/resume, user confirms each (good: nothing auto-posts) | |
| Notifications | `flutter_local_notifications` (bills, reminders, budget alerts) + native Guardian channels | No calendar / dedupe across sources. |
| Reports | Calendar ranges, category donut, trends | Calendar month only. |
| Design system | Tokens (`AppSpacing`, `AppRadius`, `AppPalette` light/dark), shared widgets (`AppCard`, `ListRow`, `SettingsGroup`, `BudgetProgressBar`, state views) | Reuse for every new screen. |

## 2. Bugs and incorrect financial calculations found

Severity: **H** = wrong numbers shown today, **M** = wrong under common use, **L** = edge case.

| # | Sev | Finding | Where |
|---|---|---|---|
| B1 | H | **Net worth ignores EMI loans.** Dashboard net worth = cash + investments + emergency + owed-to-you − borrowed; the `loans` table's outstanding is never subtracted. | `net_worth_section.dart` |
| B2 | H | **EMI principal counted as spending.** Every installment (both EMI systems) is logged as a full expense, so principal repayment inflates expenses and budget usage. If the purchase itself was also logged, the item is counted twice (violates rules 3, 4, 10). | `loans_controller.payInstallment`, `recurring_controller.logEmi/logDue` |
| B3 | H | **Goal contributions are expenses.** Setting money aside inflates monthly spending, trips budget/Guardian alerts, and "saved" is derived from expenses (violates rule 5). | `goals_controller.contribute` |
| B4 | M | **Two EMI systems** (`loans` and `recurring.installments_remaining`) can both track the same EMI → duplicate reminders and duplicate expenses. | loans + recurring |
| B5 | M | **Loan outstanding assumes flat interest and on-time EMIs only**; no partial, extra or prepayment; interest never separated from principal. | `Loan.outstandingPaise` |
| B6 | M | **Lending repayments rewrite history**: the original lent/borrowed row's amount is reduced in place, so reports for the original date change and the cash return is effectively back-dated (violates rule 15). | `TransactionRepository.repay` |
| B7 | M | **Refunds are classified as income** by the quick-add parser, inflating income instead of reducing the original expense (rule 9). | `kIncomeKeywords` ('refund', 'cashback') |
| B8 | M | **Splitter moves money immediately and non-atomically**: approval = completed transfers, written one by one (a failure mid-way leaves a partial split); rounding remainders are dropped; the typed amount isn't tied to income actually received. | `accounts_screen._showDistribute` |
| B9 | L | Transfers have no shared reference or status; no "planned vs completed". | `transfers` |
| B10 | L | Accounts joined by name; works (renames cascade) but new modules need stable ids. | schema |
| B11 | L | Budgets and Guardian figures are calendar-month only; a salary on the 10th makes "monthly" pace misleading. | budgets |

## 3. Target accounting architecture (Phase 2)

Guiding rule: **one record per real-world event; reporting views are date-range queries, never copies.**

### 3.1 Classification of every money event

| Event | Stored as | Affects P&L (income/expense)? | Affects balances |
|---|---|---|---|
| Expense (cash/bank/UPI) | `txns` expense, `account_id` | yes (expense) | bank − |
| Expense on credit card | `txns` expense, `card_id` | yes (expense, at purchase date) | card outstanding + |
| Income received | `txns` income + `income_source` | yes (income) | bank + |
| Expected income | `expected_income` row | no | none |
| Refund | `txns` refund linked to original expense (`refund_of`) | reduces expense | bank/card + |
| Transfer A → B | `movements` kind=`transfer`, two postings, shared `ref` | no | A −, B + |
| Card bill payment | `movements` kind=`card_payment` | no (liability settlement) | bank −, card outstanding − |
| Loan disbursement / EMI purchase | `movements` kind=`loan_open` | no | liability + (purchase itself is the expense) |
| Loan installment | principal → `movements` kind=`loan_principal`; interest/fees/tax → `txns` expense category `interest`/`fees` | interest/fees only | bank −, liability − principal |
| Savings / emergency / investment contribution | `movements` kind=`transfer` to an account with that role (or `earmark` within the same account) | no | moves between pools |
| Opening balance | `accounts.opening_balance` | no | baseline |
| Reconciliation adjustment | `movements` kind=`adjustment` + `reconciliations` row | no (shown separately) | account ± difference |

**Postings table** gives every account and liability a single signed history:
`balance(account) = opening + Σ txns(account) + Σ postings(account)`.
Liabilities (cards, loans) use the same postings, so outstanding is derived, never typed in, and can be reconciled against statements.

### 3.2 Central rules engine
`lib/core/finance/accounting.dart` — pure functions, no Flutter imports, 100% unit-tested:
`isIncome`, `isExpense`, `cashEffect`, `liabilityEffect`, period totals (`totalsFor(range)`), net worth, available vs reserved. Every screen, report, budget, alert and the Guardian snapshot read through it, so the 15 rules live in one place.

### 3.3 Integrity
- Multi-record writes (transfer legs, installment split, cycle close, allocation transfer) inside `db.transaction`.
- `audit_log` (entity, entity_id, action, before_json, after_json, at) for edits/deletes of money records, statements, loans, cycles, reconciliations.
- Closed cycles store a **frozen summary JSON + rules version**; reopening is explicit, never silent recalculation (rule 15).
- New tables reference accounts by **id**. `txns.account` (name) stays for backward compatibility; a nullable `txns.account_id` is added and back-filled, both kept in sync until every reader uses the id.

## 4. Schema plan (additive; nothing dropped or rewritten)

| Version | Change |
|---|---|
| v13 | `audit_log`; `accounts` + `bank_name`, `last4`, `roles` (CSV: salary, daily, emi, savings, emergency, investment), `status`; `txns` + `account_id`, `card_id`, `income_source`, `recurring_income`, `refund_of`, `review_flag`; back-fill `account_id`. |
| v13 | `movements` (id, ref, kind, date, amount, status planned/completed/cancelled, note, created_at) + `postings` (movement_id, owner_type account/card/loan/goal, owner_id, amount signed). Existing `transfers` copied into movements (originals kept, marked migrated, readers switch over). |
| v14 | `salary_profile` (in config: CTC, gross, expected net, expected day range 7–15); `income_cycles` (id, start_date, end_date nullable, salary_txn_id, status open/closed, closed_at, summary_json, rules_version); `expected_income`. |
| v15 | `budgets` (id, period_kind cycle/month/week/day/custom, category nullable = overall, limit, start/end for custom, thresholds). Existing config budgets copied in (config keys still read for old backups). |
| v16 | `credit_cards` (name, bank, last4, limit, statement_day, due_day, repayment_account_id, status); `card_statements` (card_id, period_start, period_end, generated_on, total_due, minimum_due, due_date, previous_balance, payments, refunds, charges, emi_amount, status, reconciled_diff); `card_emis` (card_id, purchase_txn_id, amount, purchase_date, tenure, installment, principal/interest/fee/tax nullable when unknown, remaining). |
| v17 | `loans` + `kind`, `rate_bps`, `frequency`, `due_day`, `account_id`, `outstanding_principal`, `status`; `loan_installments` (loan_id, seq, due_date, principal, interest, fees, status, paid_movement_id, **UNIQUE(loan_id, seq)**) so schedules can't duplicate; `loan_events` (prepayment, foreclosure, correction). |
| v18 | `allocation_plans` (cycle_id, created_at, available, status) + `allocation_items` (category, priority, amount, destination_account_id, reason, due_date, required, reserved, shortfall, status proposed/approved/reserved/transferred/skipped/cancelled, movement_id). |
| v19 | `cycle_closings` (cycle_id, leftover, decisions_json, confirmed_at); `reconciliations` (account_id, date, app_balance, actual_balance, difference, adjustment_movement_id, note). |
| v20 | `goals` + `target_date`, `priority`, `monthly_contribution`, `account_id`, `kind` (goal/emergency/investment); `investment_holdings` (manual: name, units?, invested, current_value, as_of). |

Every step gets a migration test that builds the previous version with realistic rows and asserts nothing was lost or changed.

## 5. Data migration strategy

**Decision (user, Phase 1): start fresh.** All past data and goals are cleared with
Settings → Reset all data, and the user re-enters the current situation. So the
review/reclassification tooling for old EMI expenses, goal contributions, refunds and
lending history (B2, B3, B6, B7 legacy rows) is **not built**; the bugs are fixed for
all new records instead.

Still required, because a phone may upgrade before it is reset:
1. Every schema step stays additive and has a migration test on a populated older DB.
2. Existing `transfers` are copied into `movements`/`postings` so balances don't change on upgrade.
3. Account roles are inferred from type (emergencyFund → emergency, investment → investment).
4. Config budgets stay readable so older backups still restore.

"Reset all data" was made a true fresh start: it now also cancels scheduled
notifications, refreshes every screen, clears Spending Guardian statistics, and stops
SMS import from re-queuing bank messages received before the reset.

## 6. Key algorithms

**Salary cycle.** A cycle starts on the date of the salary income the user marks as "salary received" and ends the day before the next one. The current cycle is open-ended (`end_date = null`); for planning, "next expected salary" = expected day range from the profile (7th–15th, using the earliest day for safety). Transactions belong to a cycle by date only. Calendar months are independent range queries.

**Available to allocate.**
`liquid = Σ balances of accounts with daily/salary/savings roles (excluding emergency & investment roles)`
`reserved = Σ allocation items in status approved/reserved not yet transferred or consumed`
`unallocated = liquid − reserved` (income is already inside `liquid` once recorded, so it's never added twice).

**Allocation engine** (pure function, configurable priority list):
1. Essentials: budgeted essential categories for the rest of the cycle minus spent so far.
2. Obligations due before the next expected salary: card statement dues (total due, minimum shown separately), loan installments, recurring bills; minus what is already reserved for each.
3. Emergency fund: (target − current), capped by configured monthly contribution.
4. Short-term goals by priority/target date: required monthly = remaining ÷ months left.
5. Long-term investing: configured contribution; skipped if any P1–P2 shortfall or revolving card debt exists.
6. Discretionary: remaining discretionary budgets.
7. Buffer: whatever remains.
Revolving card balances (unpaid statement carried over) are moved ahead of 4–6 automatically. Each item carries required, reserved, proposed, shortfall and a reason string built from the actual numbers. Σ proposed ≤ unallocated always; if obligations exceed funds the plan reports the shortfall and the highest-priority unmet items instead of balancing.

**Card statement math.** `computed_due = previous_balance − payments − refunds + purchases + emi_installments + charges` for the statement window; compared with the user-entered total → reconciliation difference shown, never auto-corrected. Remaining due = total due − Σ payments linked to that statement.

**Loan schedule.** Reducing-balance EMI when a rate is known; otherwise the user's figures (flat or unknown split are stored as unknown, not invented). Installments generated once into `loan_installments` (unique per seq). Prepayment reduces outstanding principal and regenerates only *future unpaid* rows (option: reduce tenure or reduce EMI).

## 7. Phased roadmap

Each phase ends with: `flutter analyze`, full `flutter test`, new unit tests, migration test, this document updated. A phase does not start until the previous one's calculations are verified.

| Phase | Scope | Fixes | Exit tests |
|---|---|---|---|
| 1 | Audit (this document) | — | — |
| 2 | Accounting core: `accounting.dart`, `movements`/`postings`, `audit_log`, account ids/roles, transfers → movements, atomic writes | B1, B9, B10 | Rules 1, 8, 12–14; transfer scenario 7; net worth incl. loans |
| 3 | Salary profile + income cycles + dual period selector app-wide | B11 | Scenarios 1, 2; variable salary; cycle boundaries |
| 4 | Income sources/expected income, refunds, budgets table (cycle/month/week/day/custom), thresholds | B7 | Budget utilization; refund adjusts expense |
| 5 | Credit cards, statements, payments, card EMI; loans rebuild with schedules, split payments, prepayment; merge EMI systems | B2, B4, B5 | Scenarios 3–6; EMI not double counted; principal math |
| 6 | Bank account details, reconciliation + adjustments with audit trail | — | Reconciliation difference; adjustment audited |
| 7 | Smart Money Allocation engine + approval workflow (replaces Distribute) | B8 | Scenarios 9, 10; Σ ≤ available; no double counting |
| 8 | Cycle closing + leftover decisions + frozen history | — | Scenario 8; validation; history immutability |
| 9 | Emergency fund, goals rework, manual investments | B3 | Coverage months; no asset double count |
| 10 | Financial calendar + reminder dedupe | — | 7/15/30-day views; one notification per obligation |
| 11 | Dashboard, reports, insights (cycle + month views) | — | Widget/layout tests |
| 12 | Full migration run, end-to-end scenario tests | B6 (new records) | All 10 scenarios; upgrade from v12 |

## 8. Decisions

| # | Decision | Source |
|---|---|---|
| D1 | Start fresh: past data and goals are cleared; no legacy-data review tooling. | user |
| D2 | Savings and emergency money live in **separate bank accounts**, never as earmarks inside a spending account. Allocation treats accounts with savings/emergency/investment roles as non-spendable; no earmark concept is built. | user |
| D3 | A salary cycle stays open until the actual salary is recorded, even past the 15th. **Revised in Phase 3:** planning assumes the *latest* expected day (the 15th), not the earliest — planning to the 7th would overstate what can be spent per day whenever salary comes later in the window. After the 15th with no salary the cycle shows "salary is later than expected" and no per-day figure. | default, revised |
| D4 | Stop for review after each phase. | default |

## 9. Phase log

### Phase 2 — Accounting core (done)

Schema **v13** (`_upgradeToLedgerV13`, re-runnable):
- `accounts` + `bank_name`, `last4` (4 digits only), `roles` (CSV of salary, daily, emi,
  savings, emergency, investment; inferred from type on upgrade), `status` (active/closed).
- `movements` (unique `ref`, kind, date, amount > 0, status planned/completed/cancelled,
  completed_at) and `postings` (movement_id, owner_type account/external, owner_id,
  signed amount).
- `audit_log` (entity, entity_id, action, before_json, after_json, at).
- Every v12 `transfers` row copied to one movement + two postings (`legacy-transfer-<id>`);
  the old rows are untouched and no longer read.

Code:
- `lib/core/finance/accounting.dart`: income/expense classification, balance effect,
  `NetWorth` (now subtracts EMI loans: **B1 fixed**).
- `AccountRepository`: balance = opening + txns + completed postings; transfers are
  atomic movements with a shared ref and audit entry (**B9 fixed**); `addTransfers` batch
  is all-or-nothing; `setTransferStatus` for planned → completed/cancelled; delete
  reassigns postings by id (**B10** for new data).
- Distribute now records all shares in one transaction (**B8 partly**: still fixed %,
  replaced in Phase 7).
- Audit entries for account create/update/delete, transfer create/status, txn edit/delete.
- Account form (one sheet for add and edit): bank, last 4, roles, closed status. Closed
  accounts leave all pickers but keep history. `AccountsController.spendableTotal`
  excludes savings/emergency/investment accounts (decision D2).

Tests (`test/ledger_v13_test.dart`, 12): v12 → v13 keeps balances and copies transfers;
re-running is a no-op; scenario 7 (₹3,000 salary → savings: balances move, month income
and expense unchanged, postings sum to zero, one shared movement, audited); planned
transfers don't count until completed and stop counting when cancelled; batch rollback;
input validation; account delete moves transfer history; opening-balance edit audited
and not income; txn edit/delete audited; classification rules; net worth with loans;
spendable roles. Full suite: 214 passing, `flutter analyze` clean.

### Phase 3 — Salary profile and dual periods (done)

Schema **v14** (`_createCycleTables`, re-runnable):
- `income_cycles` (start_date UNIQUE, salary_txn_id, untracked_salary, note, created_at,
  closed_at, end_date, summary_json, rules_version). Only starts are stored; ends are
  derived (next start − 1 day), so cycles can't overlap or leave gaps. `end_date`,
  `summary_json`, `rules_version` are reserved for closing (Phase 8).
- `salary_profile` (single row: CTC/yr, gross/mo, expected take-home, usual day range,
  usual account). Account renames cascade to it.

Code:
- `lib/core/finance/salary_cycle.dart` (pure): cycle ranges, cycle for a date, next salary
  window (clamped to month length), standing (day N, days to last, late), start
  validation (no future, no duplicate, nothing inside a closed cycle, moves stay between
  neighbours, nothing moves a closed cycle's end).
- `CycleRepository`: record salary (income txn + cycle + audit, atomic) or, when the
  salary is already inside an opening balance, keep the amount on the cycle only
  (rule 8); start a cycle without salary; move a start; remove a boundary (salary entry
  kept); cycle income = salary + every other income in the cycle's dates.
- `CycleController` follows the ledger; dashboard **Month / Salary cycle** toggle
  (remembered in config `periodView`); cycle view = cycle card (left from this cycle's
  income, salary, other income, spent, next salary window, days it must last), categories,
  upcoming bills, recent; previous/next cycle navigation. Reports gain **This cycle /
  Last cycle**. More → **Salary & cycles** screen (record salary, salary details,
  history with change-start / remove). CTC, gross and expected pay are always labelled
  as not received.
- "Left from this cycle's income" is never called "safe to spend": bills, EMIs and card
  dues aren't subtracted until Phases 5–7.

Tests (`test/salary_cycle_test.dart`, 14): cycle ranges from actual dates (10 Nov,
12 Dec); salary window and month clamping; standing and late salary; start validation
incl. closed cycles; scenarios 1–2 (₹19,000 + ₹2,000 → cycle income ₹21,000, balance and
calendar month agree); variable salaries with one expense counted once in the cycle view
and once in the month view from a single row; already-in-balance salary not double
counted; attaching salary to an empty cycle only once; closed cycles immutable; moves
audited; deleted salary entry counts as zero; profile validation; v13 → v14 upgrade;
cycle card at 320 px / 1.5× and tablet. Full suite: 228 passing, `flutter analyze` clean.

### UI consistency pass (between Phases 3 and 4)

- Root cause of "colours merging": in dark mode the ink hero surface flipped to near-white
  while status colours stayed light (1.5–2.3:1); white text sat on bright category fills
  (2.6:1); selected chips put `textPrimary` on the selected fill (**1.00:1** light,
  2.26:1 dark — the Add account role chips).
- Fixes: ink stays dark in both themes; new tokens `onInkMuted`, `inkIncome/Warning/
  Expense/Accent`, `action/onAction` (buttons, FAB, selected chips and segments),
  `onStatus` (text on solid status fills); `textTertiary` darkened/lightened to ≥4.5:1;
  `ensureContrast`/`bestOn` helpers guarantee icon contrast in `CategoryIcon` and
  `ListRow`; category tiles and the drill-down header became tinted surfaces with normal
  text; warning snackbars use the ink snackbar with a status icon.
- Every data-entry dialog (wishlist, owed, recurring, goals, loans, reminders, settings,
  transfer, account delete-and-move) moved to one `showFormSheet` with inline validation —
  they used to close silently on bad input.
- Guardian: PhonePe and BHIM replaced by CRED (`com.dreamplug.androidapp`) and slice
  (`indwin.c3.shareapp`, verified); old saved selections filtered on read; an app the
  native side didn't report shows "couldn't check" instead of "not installed". The
  notification-import allowlist had a wrong slice id (`com.slice.android`); the real one
  was added.
- Tests: `contrast_test.dart` (every palette pairing, both themes),
  `selected_state_contrast_test.dart` (rendered chip/segment labels; fails on the old
  theme), `form_sheet_test.dart`.

### Phase 4 — Income, refunds and budget periods (done)

Schema **v15**:
- `txns` rebuilt (re-runnable; ids and rows preserved, indexes recreated) so `type`
  allows `refund`; new columns `income_source`, `recurring_income`, `refund_of`. Recorded
  salaries back-filled as `income_source = 'salary'`.
- `expected_income` (source, amount, expected date, account, status
  pending/received/cancelled, received_txn_id).
- `budgets` (period cycle/month/week/day/custom, category or overall, limit, custom
  dates, caution %, essential, name); unique per period+category except custom.

Rules and code:
- Refunds (rule 9): linked to the original expense, keep its category, credit the
  account, reduce spending in the period they arrive; never income; capped at what's
  left unrefunded; deleting the expense deletes its refunds; an expense can't be edited
  below what was refunded. Every expense aggregate nets refunds.
- Income: source (salary, freelance, side, business, bonus, incentive, reimbursement,
  interest, other), "repeats regularly", destination account picker in the add form.
  Expected income is listed apart and never counted until marked received, which records
  the actual amount as income (atomic, audited).
- Budgets: `lib/core/finance/budgets.dart` (period ranges — weeks Mon–Sun, cycle budgets
  to the latest expected salary day; levels; per-day pace; cycle-income gap; validation).
  `BudgetController` replaces the month-only config budgets (imported once from config);
  month views, Reports, Spending Guardian and add-transaction alerts read it. Alerts now
  fire for any budget the expense crosses. Limits never change automatically.
- Screens: **Budgets** (filter by period, cycle-income check, cards with progress, left/
  over, per-day pace; add/edit sheet); **Income** (received by source for month or cycle,
  expected list with Received / Not coming); refund action in the transaction sheet.
- Removed: old Budget planner screen, `budget_alerts.dart`, config budget setters.

Tests (`test/phase4_test.dart`, 8): period ranges, cycle budget ends and late salary,
levels/pace/validation, cycle-income gap; refunds (spending, category, balance, not
income, cap, delete cascade, edit guard); expected → received; week budget caution with
income leaving limits unchanged; legacy import once; v14 → v15 rebuild keeps rows, ids,
refs and indexes. Full suite: 249 passing, `flutter analyze` clean, Kotlin 8/8.

### Phase 5 — Credit cards, card EMIs and loans (done)

Schema **v16** (`_createDebtTables`, additive and re-runnable; runs last on a fresh
install because it extends `loans`/`loan_payments`):
- `txns.card_id`; `movements.link_type/link_id`; `loans` + kind, lender, rate_bps,
  status, split_estimated, opening; `loan_payments` + installment_id, principal,
  interest, movement_id, txn_id.
- `credit_cards` (name, bank, last 4 only, limit, statement/due day, repayment account,
  opening outstanding, status), `card_statements` (period, generated, due, total,
  minimum, breakdown; unique per card + period end), `card_emis`, `card_statement_emis`
  (one row per EMI per statement → billed count can't double), `loan_installments`
  (UNIQUE loan + seq), `loan_events` (prepayment, foreclosure, correction, fee).

Accounting:
- Card purchase = expense on the card (`card_id`), counted once on its date; never
  touches a bank. Bill payment = movement bank → card linked to its statement (rule 2).
  Refunds of card purchases go back to the card. Card outstanding = opening + spending −
  refunds − payments (derived). Unpaid statements stay liabilities (rule 11).
- Card EMI: the purchase stays the single expense; statements mark installments billed
  and record new interest/fees/GST once as an expense on the card (rules 4, 10).
  Principal outstanding of a card EMI is shown only when the bank itemised it — never
  invented; remaining payable = installment × installments left.
- Loans: schedules generated once (reducing balance with a rate; otherwise the user's
  own implied interest spread evenly, every installment equal to the stated EMI, flagged
  "estimated split"). Payment = interest first (expense, `source = 'loan'`) then
  principal (movement bank → loan, rule 3). Partial payments, prepayment (finish sooner
  or lower EMI; only unpaid future installments rebuilt), foreclosure (charges are an
  expense), balance correction (no money moves; audited), undo last payment; deleting an
  installment's interest entry reverses the whole payment. Openings: already running (no
  cash effect), money received (account +, not income), bought on EMI (the item recorded
  once as an expense). Loans saved before v16 get their schedule once, paid installments
  marked, with a correction so what's owed stays right.
- Net worth subtracts loan principal outstanding and card outstanding.
- One EMI system (**B2, B4, B5 fixed**): quick-add "bought X on EMI" opens the loan form;
  "paid EMI X" pays the matching loan's next installment (split); the Recurring screen's
  EMI button opens Loans. Interest/principal no longer double counted.
- Account history shows card bills, loan repayments and disbursements alongside transfers.
- Screens: **Credit cards** (owed, utilisation, statement state) → card detail (pay
  full/minimum/custom toward a statement, add statement with breakdown check and billed
  EMIs, convert purchase to EMI, recent card spending). **Loans & EMI** rebuilt → loan
  detail (pay EMI with live split, prepay, close early, correct balance, undo, schedule
  list). "Paid from" in the add form includes cards.

Tests: `phase5_test.dart` (17) — EMI formula and reducing schedule, flat schedule equals
stated EMI, interest-first split, months to clear, statement arithmetic and states
(unpaid → partly → overdue → paid, revolving), card purchase not on bank, scenarios 3, 4,
5 and 6, card refund, statement validation/duplicates, loan openings, bought-on-EMI single
expense, prepay both modes, foreclosure with charges, correction audited, schedule never
duplicated, net worth with cards and loans, v15 → v16 legacy loan; `data_integrity_test`
loan groups rewritten (split, delete reverses payment, undo, final installment closes,
owner-scoped history); `debt_screens_test.dart` (8) — four screens at 320 px / 1.5× in
both themes. Old flat-interest `loan_test.dart` / `loan_repository_test.dart` removed.

Known gaps: per-EMI principal/interest from a statement isn't entered in the UI yet
(stored as unknown); statements can't be edited (delete and re-add before payment);
card payments can't be undone in the UI yet — reconciliation (Phase 6) adds adjustments.
