import '../../core/finance/allocation.dart';
import '../../core/finance/budgets.dart';
import '../../core/finance/cards.dart';
import '../../core/finance/salary_cycle.dart';
import '../../core/utils/money_formatter.dart';
import '../../data/models/account.dart';
import '../../data/models/loan.dart';
import '../../data/models/recurring_bill.dart';
import '../../data/repositories/allocation_repository.dart';
import '../accounts/accounts_controller.dart';
import '../../core/finance/wealth.dart';
import '../cards/cards_controller.dart';
import '../goals/goals_controller.dart';
import '../cycles/cycle_card.dart';

/// Everything allocation looks at, as of [today]. Plain data, so the needs
/// can be built and tested without any database or UI.
class AllocationSnapshot {
  final DateTime today;

  /// Money must last until here: the latest expected salary day, or the end
  /// of the month when there's no salary cycle.
  final DateTime horizon;
  final String currency;
  final List<AccountBalance> accounts;
  final List<BudgetUsage> budgets;
  final List<CardSummary> cards;
  final List<LoanStanding> loans;
  final List<RecurringBill> bills;
  final AllocationSettings settings;
  final List<GoalStanding> goals;

  const AllocationSnapshot({
    this.goals = const [],
    required this.today,
    required this.horizon,
    required this.currency,
    required this.accounts,
    required this.budgets,
    required this.cards,
    required this.loans,
    required this.bills,
    required this.settings,
  });

  List<AccountBalance> get spendable =>
      accounts.where((a) => a.account.isSpendable).toList();

  /// Cash you can actually use: spendable accounts, less money on hold.
  int get liquid =>
      spendable.fold(0, (s, a) => s + a.balance - a.account.holdPaise);

  String? _withRole(AccountRole r) => accounts
      .where(
        (a) =>
            a.account.status == AccountStatus.active &&
            a.account.roles.contains(r),
      )
      .firstOrNull
      ?.account
      .name;

  /// Where day-to-day money sits.
  String? get dailyAccount =>
      _withRole(AccountRole.daily) ??
      spendable.where((a) => a.account.isDefault).firstOrNull?.account.name ??
      spendable.firstOrNull?.account.name;

  /// Where money moves *from*: the salary account with the most available,
  /// else the spendable account with the most.
  String? get sourceAccount {
    final pool = spendable
        .where((a) => a.account.roles.contains(AccountRole.salary))
        .toList();
    final list = pool.isEmpty ? spendable : pool;
    if (list.isEmpty) return null;
    list.sort(
      (a, b) => (b.balance - b.account.holdPaise).compareTo(
        a.balance - a.account.holdPaise,
      ),
    );
    return list.first.account.name;
  }

  String? get emergencyAccount =>
      _withRole(AccountRole.emergency) ??
      accounts
          .where((a) => a.account.type == AccountType.emergencyFund)
          .firstOrNull
          ?.account
          .name;

  int get emergencyBalance => accounts
      .where(
        (a) =>
            a.account.roles.contains(AccountRole.emergency) ||
            a.account.type == AccountType.emergencyFund,
      )
      .fold(0, (s, a) => s + a.worth);
}

/// The next date [bill] falls due on or after [today].
DateTime nextBillDate(RecurringBill bill, DateTime today) {
  final t = dateOnly(today);
  final monthKey =
      '${t.year.toString().padLeft(4, '0')}-${t.month.toString().padLeft(2, '0')}';
  DateTime on(int y, int m) {
    final last = DateTime(y, m + 1, 0).day;
    return DateTime(y, m, bill.dayOfMonth > last ? last : bill.dayOfMonth);
  }

  return bill.lastRunMonth == monthKey
      ? on(t.year, t.month + 1)
      : on(t.year, t.month);
}

List<AllocationNeed> buildNeeds(AllocationSnapshot s) {
  String fmt(int p) => formatMoney(p, s.currency);
  final daily = s.dailyAccount;
  final out = <AllocationNeed>[];
  final until = 'before ${shortDate(s.horizon)}';

  // Budgets: essentials first, the rest discretionary. An overall cap only
  // counts when there are no category budgets to plan with.
  final categoryBudgets = s.budgets.where((u) => !u.budget.isOverall).toList();
  final budgetLines = categoryBudgets.isNotEmpty
      ? categoryBudgets
      : s.budgets.where((u) => u.budget.isOverall).toList();
  for (final u in budgetLines) {
    if (u.remaining <= 0) continue;
    final b = u.budget;
    out.add(
      AllocationNeed(
        key: 'budget:${b.id}',
        bucket: b.essential
            ? AllocBucket.essentials
            : AllocBucket.discretionary,
        label: b.label,
        required: u.remaining,
        destination: daily,
        reason:
            '${fmt(u.remaining)} left of your ${fmt(b.limitPaise)} '
            '${budgetPeriodLabel(b.period).toLowerCase()} budget.',
      ),
    );
  }

  // Card statements still unpaid that fall due before the horizon, or are
  // already overdue (revolving — interest is building).
  for (final c in s.cards) {
    final st = c.latest;
    if (st == null) continue;
    final standing = st.standing(s.today);
    if (standing.remaining <= 0) continue;
    final overdue = standing.state == StatementState.overdue;
    if (!overdue && st.dueDate.isAfter(s.horizon)) continue;
    out.add(
      AllocationNeed(
        key: 'card:${c.card.id}:stmt:${st.id}',
        bucket: AllocBucket.obligations,
        label: '${c.card.name} bill',
        required: standing.remaining,
        destination: c.card.repaymentAccount ?? daily,
        dueDate: st.dueDate,
        revolving: overdue,
        reason: overdue
            ? 'Overdue since ${shortDate(st.dueDate)}: interest builds on '
                  'what’s unpaid. Minimum left ${fmt(standing.minimumRemaining)}.'
            : 'Statement due ${shortDate(st.dueDate)}, $until. Paying only the '
                  'minimum (${fmt(standing.minimumRemaining)}) leaves the rest '
                  'charging interest.',
      ),
    );
  }

  for (final l in s.loans.where((l) => !l.closed)) {
    for (final i in l.due.where((i) => !i.dueDate.isAfter(s.horizon))) {
      out.add(
        AllocationNeed(
          key: 'loan:${l.loan.id}:inst:${i.id}',
          bucket: AllocBucket.obligations,
          label: '${l.loan.name} EMI ${i.seq}',
          required: i.remaining,
          destination: l.loan.account ?? daily,
          dueDate: i.dueDate,
          reason: i.dueDate.isBefore(dateOnly(s.today))
              ? 'Overdue since ${shortDate(i.dueDate)}.'
              : 'Due ${shortDate(i.dueDate)}, $until.',
        ),
      );
    }
  }

  for (final b in s.bills.where(
    (b) => b.active && b.type == RecurringType.expense && b.loanId == null,
  )) {
    final due = nextBillDate(b, s.today);
    if (due.isAfter(s.horizon)) continue;
    out.add(
      AllocationNeed(
        key: 'bill:${b.id}:${due.year}-${due.month}',
        bucket: AllocBucket.obligations,
        label: b.note?.isNotEmpty == true ? b.note! : b.category,
        required: b.amountPaise,
        destination: daily,
        dueDate: due,
        reason: 'Recurring bill due ${shortDate(due)}, $until.',
      ),
    );
  }

  final set = s.settings;
  final target = set.emergencyTarget ?? 0;
  if (target > 0) {
    final gap = target - s.emergencyBalance;
    if (gap > 0) {
      final monthly = set.emergencyMonthly;
      out.add(
        AllocationNeed(
          key: 'emergency',
          bucket: AllocBucket.emergency,
          label: 'Emergency fund',
          required: monthly != null && monthly > 0 && monthly < gap
              ? monthly
              : gap,
          destination: s.emergencyAccount,
          reason:
              'Your emergency fund has ${fmt(s.emergencyBalance)} of its '
              '${fmt(target)} target — ${fmt(gap)} to go.',
        ),
      );
    }
  }
  for (final g in s.goals.where((g) => !g.goal.achieved)) {
    final want = g.progress.suggested(s.today);
    if (want == null || want <= 0) continue;
    final date = g.goal.targetDate;
    out.add(
      AllocationNeed(
        key: 'goal:${g.goal.id}',
        bucket: g.goal.horizon == GoalHorizon.long
            ? AllocBucket.investing
            : AllocBucket.savings,
        label: g.goal.name,
        required: want,
        destination: g.goal.account,
        dueDate: date,
        reason:
            '${fmt(g.saved)} of ${fmt(g.goal.targetPaise)} saved'
            '${date == null ? '' : ' — about ${fmt(want)} a month reaches it by ${shortDate(date)}'}.',
      ),
    );
  }
  if ((set.savingsPerCycle ?? 0) > 0) {
    out.add(
      AllocationNeed(
        key: 'savings',
        bucket: AllocBucket.savings,
        label: 'Savings',
        required: set.savingsPerCycle!,
        destination: s._withRole(AccountRole.savings),
        reason:
            'Your planned saving of ${fmt(set.savingsPerCycle!)} this period.',
      ),
    );
  }
  if ((set.investPerCycle ?? 0) > 0) {
    out.add(
      AllocationNeed(
        key: 'invest',
        bucket: AllocBucket.investing,
        label: 'Investing',
        required: set.investPerCycle!,
        destination: s._withRole(AccountRole.investment),
        reason:
            'Your planned investment of ${fmt(set.investPerCycle!)} this period.',
      ),
    );
  }
  return out;
}

/// How earlier decisions count against the current needs.
///
/// - [heldBack]: reserved and still sitting in spendable cash — taken off
///   what's available so it isn't allocated twice.
/// - [funded]: reserved *or* already moved — what each need has had, so a
///   saving that was transferred isn't proposed again.
///
/// Either only counts while the need still exists, and never beyond what it
/// now requires: paying a bill or spending a budget releases its share.
({Map<String, int> heldBack, Map<String, int> funded}) effectiveReservations(
  List<AllocationDecision> decisions,
  List<AllocationNeed> needs,
) {
  final byKey = {for (final n in needs) n.key: n};
  final held = <String, int>{}, funded = <String, int>{};
  for (final d in decisions) {
    final n = byKey[d.key];
    if (n == null || d.status == DecisionStatus.skipped) continue;
    final v = d.amount < n.required ? d.amount : n.required;
    funded[d.key] = v;
    if (d.status == DecisionStatus.reserved) held[d.key] = v;
  }
  return (heldBack: held, funded: funded);
}
