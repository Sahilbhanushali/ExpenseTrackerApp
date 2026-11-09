/// Closing a salary cycle. Pure — no database, no Flutter.
///
/// - The leftover you can decide on is money that really exists from this
///   cycle: the smaller of the cycle's result (income − spending) and what
///   is unallocated in spendable accounts now. Deciding on November's
///   leftover can never spend December's salary.
/// - Nothing resets or moves by itself; every move is one the user chose.
/// - A closed cycle keeps a frozen summary with the rules version that made
///   it, and is shown from that summary from then on (rule 15).
library;

import 'dart:convert';

/// Bumped whenever how a closing summary is computed changes, so old
/// summaries are read as what they were.
const kClosingRulesVersion = 1;

enum LeftoverKind {
  carryForward,
  savings,
  emergency,
  loanPrincipal,
  cardPayment,
  investing,
  keepCash,
  custom,
}

String leftoverLabel(LeftoverKind k) => switch (k) {
  LeftoverKind.carryForward => 'Carry forward to next cycle',
  LeftoverKind.savings => 'Move to savings',
  LeftoverKind.emergency => 'Add to emergency fund',
  LeftoverKind.loanPrincipal => 'Pay extra loan principal',
  LeftoverKind.cardPayment => 'Pay down card debt',
  LeftoverKind.investing => 'Move to investments',
  LeftoverKind.keepCash => 'Keep as available cash',
  LeftoverKind.custom => 'Move to another account',
};

/// Whether choosing this moves money (vs. just recording a decision).
bool movesMoney(LeftoverKind k) =>
    k != LeftoverKind.carryForward && k != LeftoverKind.keepCash;

/// One destination for part of the leftover. [target] is an account name,
/// or `loan:<id>` / `card:<id>`.
class LeftoverAction {
  final LeftoverKind kind;
  final int amountPaise;
  final String? target;
  final String label;

  /// Filled in once carried out: the movement it created.
  final int? movementId;

  const LeftoverAction({
    required this.kind,
    required this.amountPaise,
    this.target,
    required this.label,
    this.movementId,
  });

  LeftoverAction done(int? movementId) => LeftoverAction(
    kind: kind,
    amountPaise: amountPaise,
    target: target,
    label: label,
    movementId: movementId,
  );

  Map<String, Object?> toJson() => {
    'kind': kind.name,
    'amount': amountPaise,
    'target': target,
    'label': label,
    'movement': movementId,
  };

  factory LeftoverAction.fromJson(Map<String, dynamic> j) => LeftoverAction(
    kind: LeftoverKind.values.byName(j['kind'] as String),
    amountPaise: j['amount'] as int,
    target: j['target'] as String?,
    label: j['label'] as String,
    movementId: j['movement'] as int?,
  );
}

/// Leftover the user can decide on, in paise.
int leftoverAvailable({required int cycleNet, required int unallocatedNow}) {
  final net = cycleNet < 0 ? 0 : cycleNet;
  final cash = unallocatedNow < 0 ? 0 : unallocatedNow;
  return net < cash ? net : cash;
}

/// Why these choices can't be confirmed, or null.
String? validateLeftover(List<LeftoverAction> actions, int available) {
  for (final a in actions) {
    if (a.amountPaise <= 0) return 'Every amount must be more than zero.';
    if (movesMoney(a.kind) && (a.target == null || a.target!.isEmpty)) {
      return 'Pick where “${leftoverLabel(a.kind)}” should go.';
    }
  }
  final total = actions.fold<int>(0, (s, a) => s + a.amountPaise);
  if (total > available) return 'That’s more than the leftover you have.';
  return null;
}

/// The frozen record of a closed cycle. All money in paise.
class CycleCloseSummary {
  final DateTime start;
  final DateTime end;
  final int salary;
  final int additionalIncome;
  final int spent;
  final Map<String, int> categories;

  /// Account → balance at the end of the cycle's last day.
  final Map<String, int> balances;
  final int cardsOwed;
  final int loansOutstanding;
  final int reservedAtClose;

  /// Unpaid at close: label → amount. Still liabilities after closing.
  final Map<String, int> unpaidObligations;
  final int leftoverAvailable;
  final List<LeftoverAction> actions;
  final DateTime closedAt;
  final int rulesVersion;

  const CycleCloseSummary({
    required this.start,
    required this.end,
    required this.salary,
    required this.additionalIncome,
    required this.spent,
    required this.categories,
    required this.balances,
    required this.cardsOwed,
    required this.loansOutstanding,
    required this.reservedAtClose,
    required this.unpaidObligations,
    required this.leftoverAvailable,
    required this.actions,
    required this.closedAt,
    this.rulesVersion = kClosingRulesVersion,
  });

  int get income => salary + additionalIncome;
  int get net => income - spent;
  int get decided => actions.fold(0, (s, a) => s + a.amountPaise);
  int get carriedForward => actions
      .where((a) => a.kind == LeftoverKind.carryForward)
      .fold(0, (s, a) => s + a.amountPaise);

  String encode() => jsonEncode({
    'start': start.toIso8601String(),
    'end': end.toIso8601String(),
    'salary': salary,
    'additional': additionalIncome,
    'spent': spent,
    'categories': categories,
    'balances': balances,
    'cardsOwed': cardsOwed,
    'loansOutstanding': loansOutstanding,
    'reserved': reservedAtClose,
    'unpaid': unpaidObligations,
    'leftover': leftoverAvailable,
    'actions': [for (final a in actions) a.toJson()],
    'closedAt': closedAt.toIso8601String(),
    'rules': rulesVersion,
  });

  static CycleCloseSummary decode(String s) {
    final j = jsonDecode(s) as Map<String, dynamic>;
    Map<String, int> ints(Object? m) => {
      for (final e in ((m as Map?) ?? const {}).entries)
        e.key as String: e.value as int,
    };
    return CycleCloseSummary(
      start: DateTime.parse(j['start'] as String),
      end: DateTime.parse(j['end'] as String),
      salary: j['salary'] as int,
      additionalIncome: j['additional'] as int,
      spent: j['spent'] as int,
      categories: ints(j['categories']),
      balances: ints(j['balances']),
      cardsOwed: j['cardsOwed'] as int,
      loansOutstanding: j['loansOutstanding'] as int,
      reservedAtClose: j['reserved'] as int,
      unpaidObligations: ints(j['unpaid']),
      leftoverAvailable: j['leftover'] as int,
      actions: [
        for (final a in (j['actions'] as List? ?? const []))
          LeftoverAction.fromJson(Map<String, dynamic>.from(a as Map)),
      ],
      closedAt: DateTime.parse(j['closedAt'] as String),
      rulesVersion: j['rules'] as int? ?? 1,
    );
  }
}
