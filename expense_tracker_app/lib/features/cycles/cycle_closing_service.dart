import '../../core/finance/cycle_closing.dart';
import '../../core/finance/salary_cycle.dart';
import '../../core/utils/money_formatter.dart';
import '../../data/models/account.dart';
import '../../data/models/movement.dart';
import '../../data/repositories/account_repository.dart';
import '../../data/repositories/card_repository.dart';
import '../../data/repositories/cycle_repository.dart';
import '../../data/repositories/loan_repository.dart';
import '../../data/repositories/transaction_repository.dart';
import 'cycle_card.dart';

/// Everything shown before closing. All paise.
class ClosingPreview {
  final CycleRange cycle;
  final CycleIncome income;
  final int spent;
  final Map<String, int> categories;
  final Map<String, int> balances;
  final int cardsOwed;
  final int loansOutstanding;
  final int reserved;
  final Map<String, int> unpaid;
  final int unallocatedNow;

  const ClosingPreview({
    required this.cycle,
    required this.income,
    required this.spent,
    required this.categories,
    required this.balances,
    required this.cardsOwed,
    required this.loansOutstanding,
    required this.reserved,
    required this.unpaid,
    required this.unallocatedNow,
  });

  int get net => income.total - spent;
  int get leftover =>
      leftoverAvailable(cycleNet: net, unallocatedNow: unallocatedNow);
}

/// Prepares and performs a cycle close. Every choice is validated before
/// any money moves; then the moves are made, then the cycle is frozen.
class CycleClosingService {
  final CycleRepository _cycles;
  final TransactionRepository _txns;
  final AccountRepository _accounts;
  final CardRepository _cards;
  final LoanRepository _loans;

  CycleClosingService({
    CycleRepository? cycles,
    TransactionRepository? txns,
    AccountRepository? accounts,
    CardRepository? cards,
    LoanRepository? loans,
  }) : _cycles = cycles ?? CycleRepository(),
       _txns = txns ?? TransactionRepository(),
       _accounts = accounts ?? AccountRepository(),
       _cards = cards ?? CardRepository(),
       _loans = loans ?? LoanRepository();

  /// [unallocatedNow] and [reserved] come from Smart Money Allocation, so
  /// the leftover never includes money already set aside or the new
  /// cycle's salary beyond what this cycle actually left over.
  Future<ClosingPreview> preview(
    CycleRange c, {
    required int unallocatedNow,
    required int reserved,
    DateTime? today,
    String currency = '₹',
  }) async {
    if (c.end == null) {
      throw const CycleException(
        'The current cycle closes once your next salary is recorded.',
      );
    }
    final now = today ?? DateTime.now();
    final end = c.end!;
    final (income, totals, categories) = await (
      _cycles.incomeFor(c, now),
      _txns.totalsRange(c.start, end),
      _txns.categoryTotalsRange(c.start, end),
    ).wait;
    final balances = <String, int>{
      for (final a in await _accounts.list())
        a.name: (await _accounts.balanceAsOf(a.name, end))!,
    };
    final owed = await _cards.outstanding();
    final standings = await _loans.standings();
    final unpaid = <String, int>{};
    for (final card in await _cards.list()) {
      final st = (await _cards.statements(card.id!)).firstOrNull;
      if (st == null || st.dueDate.isAfter(end)) continue;
      final left = st.standing(now).remaining;
      if (left > 0) {
        unpaid['${card.name} bill (due ${shortDate(st.dueDate)})'] = left;
      }
    }
    for (final l in standings.where((l) => !l.closed)) {
      for (final i in l.due.where((i) => !i.dueDate.isAfter(end))) {
        unpaid['${l.loan.name} EMI ${i.seq} (due ${shortDate(i.dueDate)})'] =
            i.remaining;
      }
    }
    return ClosingPreview(
      cycle: c,
      income: income,
      spent: totals.expense,
      categories: categories,
      balances: balances,
      cardsOwed: owed.values.fold(0, (s, v) => s + (v > 0 ? v : 0)),
      loansOutstanding: standings
          .where((l) => !l.closed)
          .fold(0, (s, l) => s + l.outstandingPrincipal),
      reserved: reserved,
      unpaid: unpaid,
      unallocatedNow: unallocatedNow,
    );
  }

  /// Checks [actions] against real balances and debts before anything
  /// moves. Returns a message, or null.
  Future<String?> check(
    ClosingPreview p,
    List<LeftoverAction> actions,
    String? source,
  ) async {
    final basic = validateLeftover(actions, p.leftover);
    if (basic != null) return basic;
    if (actions.any((a) => movesMoney(a.kind)) && source == null) {
      return 'Add a spendable account to move money from.';
    }
    final accounts = {for (final a in await _accounts.list()) a.name: a};
    final owed = await _cards.outstanding();
    final loans = {for (final l in await _loans.standings()) l.loan.id: l};
    for (final a in actions.where((a) => movesMoney(a.kind))) {
      final t = a.target!;
      if (t.startsWith('loan:')) {
        final l = loans[int.tryParse(t.substring(5))];
        if (l == null || l.closed) return 'That loan isn’t open.';
        if (a.amountPaise > l.outstandingPrincipal) {
          return 'More than is owed on ${l.loan.name}.';
        }
      } else if (t.startsWith('card:')) {
        final id = int.tryParse(t.substring(5));
        if (!owed.containsKey(id)) return 'That card no longer exists.';
      } else {
        final acc = accounts[t];
        if (acc == null || acc.status != AccountStatus.active) {
          return 'Pick an open account for “${a.label}”.';
        }
        if (t == source) {
          return '“${a.label}” goes to the account it comes from.';
        }
      }
    }
    return null;
  }

  /// Carries out [actions] from [source], then freezes the cycle.
  /// [transfersDone] false records account moves as planned (they count
  /// once marked done); card and loan payments are recorded as made.
  Future<CycleCloseSummary> close(
    ClosingPreview p,
    List<LeftoverAction> actions, {
    required String? source,
    bool transfersDone = true,
    DateTime? today,
  }) async {
    final error = await check(p, actions, source);
    if (error != null) throw CycleException(error);
    final now = today ?? DateTime.now();
    final day = isoDate(now);
    final done = <LeftoverAction>[];
    for (final a in actions) {
      int? movement;
      final t = a.target;
      if (!movesMoney(a.kind)) {
        // A decision only: carry forward / keep as cash.
      } else if (t!.startsWith('loan:')) {
        await _loans.prepay(
          int.parse(t.substring(5)),
          amountPaise: a.amountPaise,
          date: now,
          account: source!,
        );
      } else if (t.startsWith('card:')) {
        final cardId = int.parse(t.substring(5));
        final unpaid = (await _cards.statements(cardId))
            .where((s) => s.standing(now).remaining > 0)
            .lastOrNull;
        movement = await _cards.pay(
          cardId: cardId,
          fromAccount: source!,
          amountPaise: a.amountPaise,
          date: now,
          statementId: unpaid?.id,
          reference: 'Cycle leftover',
        );
      } else {
        movement = await _accounts.addTransfer(
          Transfer(
            fromAccount: source!,
            toAccount: t,
            amountPaise: a.amountPaise,
            note: 'Cycle leftover · ${a.label}',
            date: day,
            createdAt: now.toIso8601String(),
            status: transfersDone
                ? MovementStatus.completed
                : MovementStatus.planned,
          ),
        );
      }
      done.add(a.done(movement));
    }
    final summary = CycleCloseSummary(
      start: p.cycle.start,
      end: p.cycle.end!,
      salary: p.income.salary,
      additionalIncome: p.income.additional,
      spent: p.spent,
      categories: p.categories,
      balances: p.balances,
      cardsOwed: p.cardsOwed,
      loansOutstanding: p.loansOutstanding,
      reservedAtClose: p.reserved,
      unpaidObligations: p.unpaid,
      leftoverAvailable: p.leftover,
      actions: done,
      closedAt: now,
    );
    await _cycles.close(p.cycle.record.id!, summary);
    return summary;
  }
}

/// "₹2,000 moved to Savings" etc., for the confirmation step.
String describeAction(LeftoverAction a, String currency) {
  final amt = formatMoney(a.amountPaise, currency);
  return switch (a.kind) {
    LeftoverKind.carryForward => '$amt carried forward (stays where it is)',
    LeftoverKind.keepCash => '$amt kept as available cash',
    _ => '$amt → ${a.label}',
  };
}
