import '../../core/finance/cards.dart';

/// A credit card. Only the last four digits are ever stored — never the
/// full number, CVV, PIN or OTP.
class CreditCard {
  final int? id;
  final String name;
  final String? bank;
  final String? last4;

  /// All paise.
  final int limitPaise;

  /// Balance already on the card when it was added (a starting point, not
  /// spending in the app's history).
  final int openingOutstandingPaise;
  final int? statementDay;
  final int? dueDay;
  final String? repaymentAccount;
  final bool active;

  const CreditCard({
    this.id,
    required this.name,
    this.bank,
    this.last4,
    required this.limitPaise,
    this.openingOutstandingPaise = 0,
    this.statementDay,
    this.dueDay,
    this.repaymentAccount,
    this.active = true,
  });

  String get label => last4 == null ? name : '$name ••$last4';

  Map<String, Object?> toMap() => {
    'name': name,
    'bank': bank,
    'last4': last4,
    'limit_amount': limitPaise,
    'opening_outstanding': openingOutstandingPaise,
    'statement_day': statementDay,
    'due_day': dueDay,
    'repayment_account': repaymentAccount,
    'status': active ? 'active' : 'closed',
  };

  factory CreditCard.fromMap(Map<String, Object?> m) => CreditCard(
    id: m['id'] as int,
    name: m['name'] as String,
    bank: m['bank'] as String?,
    last4: m['last4'] as String?,
    limitPaise: m['limit_amount'] as int,
    openingOutstandingPaise: m['opening_outstanding'] as int,
    statementDay: m['statement_day'] as int?,
    dueDay: m['due_day'] as int?,
    repaymentAccount: m['repayment_account'] as String?,
    active: m['status'] != 'closed',
  );
}

class CardStatement {
  final int? id;
  final int cardId;
  final DateTime periodStart;
  final DateTime periodEnd;
  final DateTime generatedOn;
  final DateTime dueDate;
  final StatementFigures figures;
  final String? note;

  /// Paid toward this statement (completed card payments linked to it).
  final int paidPaise;

  const CardStatement({
    this.id,
    required this.cardId,
    required this.periodStart,
    required this.periodEnd,
    required this.generatedOn,
    required this.dueDate,
    required this.figures,
    this.note,
    this.paidPaise = 0,
  });

  StatementStanding standing(DateTime today) => StatementStanding(
    totalDue: figures.totalDue,
    minimumDue: figures.minimumDue,
    paid: paidPaise,
    dueDate: dueDate,
    today: today,
  );
}

class CardEmi {
  final int? id;
  final int cardId;
  final int? purchaseTxnId;
  final String description;

  /// All paise. Interest, fees and taxes are null when the bank didn't say.
  final int purchaseAmount;
  final DateTime purchaseDate;
  final int tenureMonths;
  final int installment;
  final int? interestTotal;
  final int? fees;
  final int? taxes;
  final bool active;

  /// Derived from the statements it was billed on.
  final int billed;
  final int? principalBilled;

  const CardEmi({
    this.id,
    required this.cardId,
    this.purchaseTxnId,
    required this.description,
    required this.purchaseAmount,
    required this.purchaseDate,
    required this.tenureMonths,
    required this.installment,
    this.interestTotal,
    this.fees,
    this.taxes,
    this.active = true,
    this.billed = 0,
    this.principalBilled,
  });

  CardEmiStanding get standing => CardEmiStanding(
    installment: installment,
    tenure: tenureMonths,
    billed: billed,
    purchaseAmount: purchaseAmount,
    principalBilled: principalBilled,
  );
}
