class SavingsGoal {
  /// In paise.
  final int amountPaise;
  final String label;

  const SavingsGoal({this.amountPaise = 0, this.label = 'Savings goal'});

  Map<String, Object?> toJson() => {'amount': amountPaise, 'label': label};

  /// [toPaise] scales legacy rupee values written before schema 2.
  factory SavingsGoal.fromJson(Map<String, dynamic> json, int scale) =>
      SavingsGoal(
        amountPaise: (((json['amount'] as num?) ?? 0) * scale).round(),
        label: json['label'] as String? ?? 'Savings goal',
      );
}

class AppConfig {
  final String currency;
  final String locale;

  /// In paise.
  final int monthlyBudgetPaise;
  final SavingsGoal savingsGoal;
  final Map<String, List<String>> customCategories;

  /// Per-category caps, in paise.
  final Map<String, int> budgets;

  /// 'system' | 'light' | 'dark'.
  final String themeMode;

  /// Which period the dashboard summarises: 'month' (calendar) or 'cycle'
  /// (salary to salary). Both stay available everywhere; this is the default.
  final String periodView;

  /// The month budgets above were copied into the `budgets` table (v15),
  /// which is the source of truth from then on.
  final bool budgetsImported;

  const AppConfig({
    this.currency = '₹',
    this.locale = 'en-IN',
    this.monthlyBudgetPaise = 0,
    this.savingsGoal = const SavingsGoal(),
    this.customCategories = const {},
    this.budgets = const {},
    this.themeMode = 'system',
    this.periodView = 'month',
    this.budgetsImported = false,
  });

  AppConfig copyWith({
    String? currency,
    String? locale,
    int? monthlyBudgetPaise,
    SavingsGoal? savingsGoal,
    Map<String, List<String>>? customCategories,
    Map<String, int>? budgets,
    String? themeMode,
    String? periodView,
    bool? budgetsImported,
  }) {
    return AppConfig(
      currency: currency ?? this.currency,
      locale: locale ?? this.locale,
      monthlyBudgetPaise: monthlyBudgetPaise ?? this.monthlyBudgetPaise,
      savingsGoal: savingsGoal ?? this.savingsGoal,
      customCategories: customCategories ?? this.customCategories,
      budgets: budgets ?? this.budgets,
      themeMode: themeMode ?? this.themeMode,
      periodView: periodView ?? this.periodView,
      budgetsImported: budgetsImported ?? this.budgetsImported,
    );
  }

  /// Bumped to 2 when money moved from rupees to paise.
  static const schemaVersion = 2;

  Map<String, Object?> toJson() => {
    'schema': schemaVersion,
    'currency': currency,
    'locale': locale,
    'monthlyBudget': monthlyBudgetPaise,
    'savingsGoal': savingsGoal.toJson(),
    'customCategories': customCategories,
    'budgets': budgets,
    'themeMode': themeMode,
    'periodView': periodView,
    'budgetsImported': budgetsImported,
  };

  factory AppConfig.fromJson(Map<String, dynamic> json) {
    final customRaw = (json['customCategories'] as Map?) ?? {};
    final budgetsRaw = (json['budgets'] as Map?) ?? {};
    // Configs written before schema 2 stored rupees; scale them once.
    final scale = ((json['schema'] as num?)?.toInt() ?? 1) < 2 ? 100 : 1;
    return AppConfig(
      currency: json['currency'] as String? ?? '₹',
      locale: json['locale'] as String? ?? 'en-IN',
      monthlyBudgetPaise: (((json['monthlyBudget'] as num?) ?? 0) * scale)
          .round(),
      savingsGoal: json['savingsGoal'] != null
          ? SavingsGoal.fromJson(
              Map<String, dynamic>.from(json['savingsGoal'] as Map),
              scale,
            )
          : const SavingsGoal(),
      customCategories: customRaw.map(
        (k, v) => MapEntry(k as String, List<String>.from(v as List)),
      ),
      budgets: budgetsRaw.map(
        (k, v) => MapEntry(k as String, ((v as num) * scale).round()),
      ),
      themeMode: switch (json['themeMode']) {
        'light' => 'light',
        'dark' => 'dark',
        _ => 'system',
      },
      periodView: json['periodView'] == 'cycle' ? 'cycle' : 'month',
      budgetsImported: json['budgetsImported'] == true,
    );
  }
}
