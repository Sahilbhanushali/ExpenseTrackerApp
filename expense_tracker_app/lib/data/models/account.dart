import 'movement.dart';

/// Which bucket of net worth this account represents. Cash is spendable
/// day-to-day money; investment/emergencyFund are still yours, just set
/// aside for a different purpose — the Dashboard breaks net worth down by
/// this instead of lumping every account into one "Accounts" figure.
enum AccountType { cash, investment, emergencyFund }

AccountType accountTypeFromString(String value) => switch (value) {
  'investment' => AccountType.investment,
  'emergency_fund' => AccountType.emergencyFund,
  _ => AccountType.cash,
};

String accountTypeToString(AccountType type) => switch (type) {
  AccountType.cash => 'cash',
  AccountType.investment => 'investment',
  AccountType.emergencyFund => 'emergency_fund',
};

/// What an account is used for. An account can have several roles.
/// Savings, emergency and investment money is kept in its own accounts
/// (never earmarked inside a spending account), so these roles decide what
/// counts as spendable cash.
enum AccountRole { salary, daily, emi, savings, emergency, investment }

/// Roles whose balance is set aside, not available for day-to-day spending.
const kSetAsideRoles = {
  AccountRole.savings,
  AccountRole.emergency,
  AccountRole.investment,
};

String accountRoleLabel(AccountRole r) => switch (r) {
  AccountRole.salary => 'Salary',
  AccountRole.daily => 'Daily spending',
  AccountRole.emi => 'EMI payments',
  AccountRole.savings => 'Savings',
  AccountRole.emergency => 'Emergency fund',
  AccountRole.investment => 'Investing',
};

Set<AccountRole> parseRoles(String? csv) => {
  for (final part in (csv ?? '').split(','))
    for (final r in AccountRole.values)
      if (r.name == part.trim()) r,
};

String rolesToCsv(Set<AccountRole> roles) =>
    (roles.map((r) => r.name).toList()..sort()).join(',');

/// Roles a pre-v13 account gets from its type.
Set<AccountRole> defaultRolesFor(AccountType type) => switch (type) {
  AccountType.cash => {AccountRole.daily},
  AccountType.investment => {AccountRole.investment},
  AccountType.emergencyFund => {AccountRole.emergency},
};

enum AccountStatus { active, closed }

/// What kind of account it is at the bank — display and defaults only.
enum BankType { savings, current, salary, wallet, cash, deposit, other }

String bankTypeLabel(BankType t) => switch (t) {
  BankType.savings => 'Savings',
  BankType.current => 'Current',
  BankType.salary => 'Salary',
  BankType.wallet => 'Wallet',
  BankType.cash => 'Cash',
  BankType.deposit => 'Fixed deposit',
  BankType.other => 'Other',
};

class MoneyAccount {
  final int? id;
  final String name;

  /// In paise.
  final int openingBalancePaise;
  final bool isDefault;
  final String createdAt;
  final AccountType type;

  /// Investment/emergency-fund accounts only — the current market worth,
  /// which may differ from [openingBalance] plus contributions. When unset,
  /// the derived cash balance is used as-is (nothing has been marked up or
  /// down yet).
  final int? currentValuePaise;

  final String? bankName;

  /// Last four digits only — never a full account number.
  final String? last4;
  final Set<AccountRole> roles;
  final AccountStatus status;
  final BankType? bankType;

  /// Money the bank is holding (a lien, a pending card authorisation):
  /// part of the balance but not available to spend. In paise.
  final int holdPaise;

  /// True when none of its roles mark the money as set aside.
  bool get isSpendable =>
      status == AccountStatus.active &&
      !roles.any(kSetAsideRoles.contains) &&
      type == AccountType.cash;

  const MoneyAccount({
    this.id,
    required this.name,
    this.openingBalancePaise = 0,
    this.isDefault = false,
    required this.createdAt,
    this.type = AccountType.cash,
    this.currentValuePaise,
    this.bankName,
    this.last4,
    this.roles = const {},
    this.status = AccountStatus.active,
    this.bankType,
    this.holdPaise = 0,
  });

  Map<String, Object?> toMap() {
    return {
      'id': id,
      'name': name,
      'opening_balance': openingBalancePaise,
      'is_default': isDefault ? 1 : 0,
      'created_at': createdAt,
      'type': accountTypeToString(type),
      'current_value': currentValuePaise,
      'bank_name': bankName,
      'last4': last4,
      'roles': rolesToCsv(roles),
      'status': status.name,
      'bank_type': bankType?.name,
      'hold_amount': holdPaise,
    };
  }

  factory MoneyAccount.fromMap(Map<String, Object?> map) {
    return MoneyAccount(
      id: map['id'] as int?,
      name: map['name'] as String,
      openingBalancePaise: (map['opening_balance'] as num).round(),
      isDefault: (map['is_default'] as int) == 1,
      createdAt: map['created_at'] as String,
      type: accountTypeFromString(map['type'] as String? ?? 'cash'),
      currentValuePaise: (map['current_value'] as num?)?.round(),
      bankName: map['bank_name'] as String?,
      last4: map['last4'] as String?,
      roles: parseRoles(map['roles'] as String?),
      status: map['status'] == 'closed'
          ? AccountStatus.closed
          : AccountStatus.active,
      bankType: BankType.values
          .where((t) => t.name == map['bank_type'])
          .firstOrNull,
      holdPaise: (map['hold_amount'] as num?)?.round() ?? 0,
    );
  }
}

/// One transfer as seen in the UI: a `movements` row of kind transfer with
/// its two postings, resolved back to account names.
class Transfer {
  /// The movement id.
  final int? id;
  final MovementStatus status;

  /// A plain transfer, or a card bill / loan movement seen from the account.
  final MovementKind kind;
  final String fromAccount;
  final String toAccount;

  /// In paise.
  final int amountPaise;
  final String? note;
  final String date;
  final String createdAt;

  const Transfer({
    this.id,
    required this.fromAccount,
    required this.toAccount,
    required this.amountPaise,
    this.note,
    required this.date,
    required this.createdAt,
    this.status = MovementStatus.completed,
    this.kind = MovementKind.transfer,
  });

  Map<String, Object?> toMap() {
    return {
      'id': id,
      'from_account': fromAccount,
      'to_account': toAccount,
      'amount': amountPaise,
      'note': note,
      'date': date,
      'created_at': createdAt,
    };
  }

  factory Transfer.fromMap(Map<String, Object?> map) {
    return Transfer(
      id: map['id'] as int?,
      fromAccount: map['from_account'] as String,
      toAccount: map['to_account'] as String,
      amountPaise: (map['amount'] as num).round(),
      note: map['note'] as String?,
      date: map['date'] as String,
      createdAt: map['created_at'] as String,
    );
  }
}
