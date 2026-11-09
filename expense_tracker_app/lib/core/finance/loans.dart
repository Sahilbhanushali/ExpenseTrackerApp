/// Loan schedules and payment splits. Pure — no database, no Flutter.
///
/// Principal repaid reduces the debt (rule 3); interest and fees are
/// expenses (rule 4). Splits come only from the user's figures:
/// - with an annual rate: the standard reducing-balance schedule;
/// - without one: total interest = EMI × tenure − principal (arithmetic on
///   the user's own numbers), spread evenly and flagged as estimated.
library;

/// [date] moved by [months], day clamped to the target month's length.
DateTime addMonths(DateTime date, int months) {
  final total = date.month - 1 + months;
  final y = date.year + total ~/ 12;
  final m = total % 12 + 1;
  final last = DateTime(y, m + 1, 0).day;
  return DateTime(y, m, date.day > last ? last : date.day);
}

class InstallmentPlan {
  final int seq;
  final DateTime dueDate;

  /// All paise; principal + interest == amount.
  final int amount;
  final int principal;
  final int interest;

  const InstallmentPlan({
    required this.seq,
    required this.dueDate,
    required this.amount,
    required this.principal,
    required this.interest,
  });
}

/// Monthly EMI for a reducing-balance loan, rounded to the paisa.
int emiFor(int principalPaise, int annualRateBps, int months) {
  if (months <= 0) return principalPaise;
  if (annualRateBps <= 0) return (principalPaise / months).ceil();
  final r = annualRateBps / 10000 / 12;
  final f = _pow(1 + r, months);
  return (principalPaise * r * f / (f - 1)).round();
}

double _pow(double b, int e) {
  var out = 1.0;
  for (var i = 0; i < e; i++) {
    out *= b;
  }
  return out;
}

/// Splits [total] into [n] near-equal integer parts that sum exactly to it;
/// the remainder goes to the last part.
List<int> spread(int total, int n) {
  if (n <= 0) return const [];
  final base = total ~/ n;
  return [
    for (var i = 0; i < n; i++) i == n - 1 ? total - base * (n - 1) : base,
  ];
}

/// Installments [startSeq].. for an outstanding [principal], first due on
/// [firstDue]. With [annualRateBps] the split follows the reducing balance
/// and the last installment absorbs rounding; without it, [totalInterest]
/// is spread evenly.
List<InstallmentPlan> buildSchedule({
  required int principal,
  required int emi,
  required int count,
  required DateTime firstDue,
  int? annualRateBps,
  int totalInterest = 0,
  int startSeq = 1,
}) {
  if (count <= 0 || principal <= 0) return const [];
  final out = <InstallmentPlan>[];
  if (annualRateBps != null && annualRateBps > 0) {
    var balance = principal;
    for (var i = 0; i < count && balance > 0; i++) {
      final interest = (balance * annualRateBps + 60000) ~/ 120000;
      final last = i == count - 1;
      var principalPart = emi - interest;
      if (last || principalPart >= balance) principalPart = balance;
      if (principalPart < 0) principalPart = 0;
      out.add(
        InstallmentPlan(
          seq: startSeq + i,
          dueDate: addMonths(firstDue, i),
          amount: principalPart + interest,
          principal: principalPart,
          interest: interest,
        ),
      );
      balance -= principalPart;
    }
    return out;
  }
  // Every installment is the lender's EMI; only the last absorbs the
  // rounding so the schedule adds up to principal + interest exactly.
  final interest = totalInterest < 0 ? 0 : totalInterest;
  final total = principal + interest;
  final interests = spread(interest, count);
  var principalLeft = principal;
  for (var i = 0; i < count; i++) {
    final last = i == count - 1;
    final amount = last ? total - emi * (count - 1) : emi;
    var p = amount - interests[i];
    if (p < 0) p = 0;
    if (last || p > principalLeft) p = principalLeft;
    principalLeft -= p;
    out.add(
      InstallmentPlan(
        seq: startSeq + i,
        dueDate: addMonths(firstDue, i),
        amount: p + interests[i],
        principal: p,
        interest: interests[i],
      ),
    );
    if (principalLeft <= 0 && !last) break;
  }
  return out;
}

/// How a payment toward an installment divides: interest still owed first,
/// then principal. Anything beyond what the installment needs isn't taken.
({int interest, int principal, int unused}) splitPayment({
  required int amount,
  required int interestDue,
  required int principalDue,
}) {
  final i = amount < interestDue ? amount : interestDue;
  final rest = amount - i;
  final p = rest < principalDue ? rest : principalDue;
  return (interest: i, principal: p, unused: rest - p);
}

/// After a prepayment: keep the EMI and finish sooner, or keep the end
/// date and pay less each month.
enum PrepayMode { reduceTenure, reduceEmi }

/// Months needed to clear [outstanding] at [emi] (reducing balance when a
/// rate is known). Null if the EMI never covers the interest.
int? monthsToClear(int outstanding, int emi, int? annualRateBps) {
  if (outstanding <= 0) return 0;
  if (emi <= 0) return null;
  if (annualRateBps == null || annualRateBps <= 0) {
    return (outstanding / emi).ceil();
  }
  var balance = outstanding;
  for (var n = 1; n <= 600; n++) {
    final interest = (balance * annualRateBps + 60000) ~/ 120000;
    if (emi <= interest) return null;
    balance -= emi - interest;
    if (balance <= 0) return n;
  }
  return null;
}
