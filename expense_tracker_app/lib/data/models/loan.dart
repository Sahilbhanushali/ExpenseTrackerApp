enum LoanKind { personal, consumer, vehicle, home, other }

String loanKindLabel(LoanKind k) => switch (k) {
  LoanKind.personal => 'Personal loan',
  LoanKind.consumer => 'Consumer EMI',
  LoanKind.vehicle => 'Vehicle loan',
  LoanKind.home => 'Home loan',
  LoanKind.other => 'Other',
};

/// How the loan started, which decides its one-time effect:
/// - existing: already running when added — no cash effect, [principalPaise]
///   is what's still owed;
/// - disbursed: the money arrived in an account (not income);
/// - purchase: it paid for something, recorded once as that expense.
enum LoanOpening { existing, disbursed, purchase }

/// An installment loan. What's still owed is derived from its schedule and
/// repayments (see LoanRepository), never typed in.
class Loan {
  final int? id;
  final String name;

  /// All in paise.
  final int principalPaise;
  final int interestPaise;
  final int emiPaise;
  final int tenureMonths;
  final int installmentsPaid;
  final DateTime startDate;
  final String? note;
  final String? account;
  final bool active;
  final LoanKind kind;
  final String? lender;

  /// Annual interest rate × 100 (10.5% → 1050), when known.
  final int? rateBps;
  final LoanOpening opening;

  /// True when the bank gave no rate, so the interest/principal split of
  /// each installment is the user's total interest spread evenly.
  final bool splitEstimated;

  const Loan({
    this.id,
    required this.name,
    required this.principalPaise,
    this.interestPaise = 0,
    required this.emiPaise,
    required this.tenureMonths,
    this.installmentsPaid = 0,
    required this.startDate,
    this.note,
    this.account,
    this.active = true,
    this.kind = LoanKind.personal,
    this.lender,
    this.rateBps,
    this.opening = LoanOpening.existing,
    this.splitEstimated = false,
  });

  /// Total interest implied by the user's own figures when no rate is
  /// known: EMI × tenure − principal (never negative).
  int get impliedInterestPaise {
    final v = emiPaise * tenureMonths - principalPaise;
    return v < 0 ? 0 : v;
  }

  Map<String, Object?> toMap() {
    return {
      'id': id,
      'name': name,
      'principal': principalPaise,
      'interest_amount': interestPaise,
      'emi_amount': emiPaise,
      'tenure_months': tenureMonths,
      'installments_paid': installmentsPaid,
      'start_date': startDate.toIso8601String(),
      'note': note,
      'account': account,
      'active': active ? 1 : 0,
      'kind': kind.name,
      'lender': lender,
      'rate_bps': rateBps,
      'status': active ? 'active' : 'closed',
      'split_estimated': splitEstimated ? 1 : 0,
      'opening': opening.name,
    };
  }

  factory Loan.fromMap(Map<String, Object?> map) {
    return Loan(
      id: map['id'] as int?,
      name: map['name'] as String,
      principalPaise: (map['principal'] as num).round(),
      interestPaise: (map['interest_amount'] as num?)?.round() ?? 0,
      emiPaise: (map['emi_amount'] as num).round(),
      tenureMonths: map['tenure_months'] as int,
      installmentsPaid: map['installments_paid'] as int? ?? 0,
      startDate: DateTime.parse(map['start_date'] as String),
      note: map['note'] as String?,
      account: map['account'] as String?,
      active: (map['active'] as int) == 1 && map['status'] != 'closed',
      kind: LoanKind.values.firstWhere(
        (k) => k.name == map['kind'],
        orElse: () => LoanKind.personal,
      ),
      lender: map['lender'] as String?,
      rateBps: map['rate_bps'] as int?,
      opening: LoanOpening.values.firstWhere(
        (o) => o.name == map['opening'],
        orElse: () => LoanOpening.existing,
      ),
      splitEstimated: map['split_estimated'] == 1,
    );
  }
}

/// One scheduled installment and what's been paid toward it. All paise.
class LoanInstallment {
  final int id;
  final int seq;
  final DateTime dueDate;
  final int amount;
  final int principal;
  final int interest;
  final int principalPaid;
  final int interestPaid;

  /// 'due', 'paid' or 'cancelled' (after a foreclosure).
  final String status;

  const LoanInstallment({
    required this.id,
    required this.seq,
    required this.dueDate,
    required this.amount,
    required this.principal,
    required this.interest,
    required this.principalPaid,
    required this.interestPaid,
    required this.status,
  });

  int get remaining => amount - principalPaid - interestPaid;
  bool get isDue => status == 'due';
  bool get partlyPaid => isDue && (principalPaid + interestPaid) > 0;
}

/// A loan with its schedule and what is still owed.
class LoanStanding {
  final Loan loan;
  final List<LoanInstallment> installments;

  /// Principal still owed — the liability in net worth.
  final int outstandingPrincipal;

  /// Interest and fees paid so far (expenses).
  final int interestPaid;

  const LoanStanding({
    required this.loan,
    required this.installments,
    required this.outstandingPrincipal,
    required this.interestPaid,
  });

  List<LoanInstallment> get due => installments.where((i) => i.isDue).toList();
  LoanInstallment? get next => due.firstOrNull;
  int get paidCount => installments.where((i) => i.status == 'paid').length;

  /// What the remaining schedule asks for (principal + planned interest).
  int get remainingPayable => due.fold(0, (s, i) => s + i.remaining);
  bool get closed => !loan.active;
}
