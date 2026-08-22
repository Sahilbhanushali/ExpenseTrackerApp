class SavingsGoal {
  final double amount;
  final String label;

  const SavingsGoal({this.amount = 0, this.label = 'Savings goal'});

  Map<String, Object?> toJson() => {'amount': amount, 'label': label};

  factory SavingsGoal.fromJson(Map<String, dynamic> json) => SavingsGoal(
    amount: (json['amount'] as num?)?.toDouble() ?? 0,
    label: json['label'] as String? ?? 'Savings goal',
  );
}

class AppConfig {
  final String currency;
  final String locale;
  final double monthlyBudget;
  final SavingsGoal savingsGoal;
  final Map<String, List<String>> customCategories;
  final Map<String, double> budgets;

  const AppConfig({
    this.currency = '₹',
    this.locale = 'en-IN',
    this.monthlyBudget = 0,
    this.savingsGoal = const SavingsGoal(),
    this.customCategories = const {},
    this.budgets = const {},
  });

  AppConfig copyWith({
    String? currency,
    String? locale,
    double? monthlyBudget,
    SavingsGoal? savingsGoal,
    Map<String, List<String>>? customCategories,
    Map<String, double>? budgets,
  }) {
    return AppConfig(
      currency: currency ?? this.currency,
      locale: locale ?? this.locale,
      monthlyBudget: monthlyBudget ?? this.monthlyBudget,
      savingsGoal: savingsGoal ?? this.savingsGoal,
      customCategories: customCategories ?? this.customCategories,
      budgets: budgets ?? this.budgets,
    );
  }

  Map<String, Object?> toJson() => {
    'currency': currency,
    'locale': locale,
    'monthlyBudget': monthlyBudget,
    'savingsGoal': savingsGoal.toJson(),
    'customCategories': customCategories,
    'budgets': budgets,
  };

  factory AppConfig.fromJson(Map<String, dynamic> json) {
    final customRaw = (json['customCategories'] as Map?) ?? {};
    final budgetsRaw = (json['budgets'] as Map?) ?? {};
    return AppConfig(
      currency: json['currency'] as String? ?? '₹',
      locale: json['locale'] as String? ?? 'en-IN',
      monthlyBudget: (json['monthlyBudget'] as num?)?.toDouble() ?? 0,
      savingsGoal: json['savingsGoal'] != null
          ? SavingsGoal.fromJson(
              Map<String, dynamic>.from(json['savingsGoal'] as Map),
            )
          : const SavingsGoal(),
      customCategories: customRaw.map(
        (k, v) => MapEntry(k as String, List<String>.from(v as List)),
      ),
      budgets: budgetsRaw.map(
        (k, v) => MapEntry(k as String, (v as num).toDouble()),
      ),
    );
  }
}
