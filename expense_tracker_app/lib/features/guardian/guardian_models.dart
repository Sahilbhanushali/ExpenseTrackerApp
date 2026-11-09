/// Monitored UPI apps. Package ids are the ones published on Google Play;
/// the Guardian screen checks which are actually installed.
const kGuardianApps = <({String package, String label})>[
  (package: 'com.google.android.apps.nbu.paisa.user', label: 'Google Pay'),
  (package: 'net.one97.paytm', label: 'Paytm'),
  (package: 'com.dreamplug.androidapp', label: 'CRED'),
  (package: 'indwin.c3.shareapp', label: 'slice'),
];

/// Ordered by severity. Mirrors `Level` in GuardianRules.kt, which decides
/// the overlay; this copy only drives the status shown in the app.
enum GuardianLevel { none, caution, reached, exceeded }

/// Same rules as the native side and the app's budget bar: over means
/// spent > budget, reached means spent == budget, caution from
/// [cautionPercent].
GuardianLevel guardianLevel(int spent, int budget, int cautionPercent) {
  if (budget <= 0) return GuardianLevel.none;
  if (spent > budget) return GuardianLevel.exceeded;
  if (spent == budget) return GuardianLevel.reached;
  if (spent * 100 >= budget * cautionPercent) return GuardianLevel.caution;
  return GuardianLevel.none;
}

class GuardianSettings {
  final bool enabled;
  final Set<String> apps;
  final int cautionPercent;
  final bool alertCaution;
  final bool alertLimit;
  final bool alertDaily;
  final bool alertCategory;
  final int cooldownMinutes;
  final bool notifyThresholds;

  const GuardianSettings({
    this.enabled = false,
    this.apps = const {},
    this.cautionPercent = 80,
    this.alertCaution = true,
    this.alertLimit = true,
    this.alertDaily = false,
    this.alertCategory = true,
    this.cooldownMinutes = 30,
    this.notifyThresholds = true,
  });

  factory GuardianSettings.fromMap(Map<Object?, Object?> m) => GuardianSettings(
    enabled: m['enabled'] == true,
    apps: {...((m['apps'] as List?) ?? const []).whereType<String>()},
    cautionPercent: (m['cautionPercent'] as num?)?.toInt() ?? 80,
    alertCaution: m['alertCaution'] != false,
    alertLimit: m['alertLimit'] != false,
    alertDaily: m['alertDaily'] == true,
    alertCategory: m['alertCategory'] != false,
    cooldownMinutes: (m['cooldownMinutes'] as num?)?.toInt() ?? 30,
    notifyThresholds: m['notifyThresholds'] != false,
  );
}

class GuardianPermissions {
  final bool usageAccess;
  final bool overlay;
  final bool notifications;
  final bool batteryUnrestricted;

  const GuardianPermissions({
    this.usageAccess = false,
    this.overlay = false,
    this.notifications = false,
    this.batteryUnrestricted = false,
  });

  bool get canMonitor => usageAccess && overlay;

  factory GuardianPermissions.fromMap(Map<Object?, Object?> m) =>
      GuardianPermissions(
        usageAccess: m['usageAccess'] == true,
        overlay: m['overlay'] == true,
        notifications: m['notifications'] == true,
        batteryUnrestricted: m['batteryUnrestricted'] == true,
      );
}

/// Everything the native side reports about the Guardian.
class GuardianState {
  final GuardianSettings settings;
  final bool running;
  final GuardianPermissions permissions;
  final Map<String, bool> installed;
  final int alertsShown;
  final int budgetExceeded;
  final Map<String, int> opens;
  final int? sdkInt;

  const GuardianState({
    this.settings = const GuardianSettings(),
    this.running = false,
    this.permissions = const GuardianPermissions(),
    this.installed = const {},
    this.alertsShown = 0,
    this.budgetExceeded = 0,
    this.opens = const {},
    this.sdkInt,
  });

  factory GuardianState.fromMap(Map<Object?, Object?> m) {
    final stats = (m['stats'] as Map?) ?? const {};
    return GuardianState(
      settings: GuardianSettings.fromMap((m['settings'] as Map?) ?? const {}),
      running: m['running'] == true,
      permissions: GuardianPermissions.fromMap(
        (m['permissions'] as Map?) ?? const {},
      ),
      installed: {
        for (final e in ((m['installed'] as Map?) ?? const {}).entries)
          e.key as String: e.value == true,
      },
      alertsShown: (stats['alertsShown'] as num?)?.toInt() ?? 0,
      budgetExceeded: (stats['budgetExceeded'] as num?)?.toInt() ?? 0,
      opens: {
        for (final e in ((stats['opens'] as Map?) ?? const {}).entries)
          e.key as String: (e.value as num).toInt(),
      },
      sdkInt: (m['sdkInt'] as num?)?.toInt(),
    );
  }
}

class CategorySpend {
  final String name;

  /// Both in paise.
  final int cap;
  final int spent;
  const CategorySpend(this.name, this.cap, this.spent);

  Map<String, Object> toJson() => {'name': name, 'cap': cap, 'spent': spent};
}

/// The figures handed to the native monitor. Derived from the ledger and
/// config on every change; the ledger stays the only source of truth.
class BudgetSnapshot {
  final DateTime computedAt;
  final String currency;

  /// All in paise.
  final int budget;
  final int spent;
  final int todaySpent;
  final List<CategorySpend> categories;

  const BudgetSnapshot({
    required this.computedAt,
    required this.currency,
    required this.budget,
    required this.spent,
    required this.todaySpent,
    required this.categories,
  });

  static String _two(int v) => v.toString().padLeft(2, '0');
  String get month => '${computedAt.year}-${_two(computedAt.month)}';
  String get day => '$month-${_two(computedAt.day)}';

  int get percent => budget > 0 ? spent * 100 ~/ budget : 0;

  List<CategorySpend> get overCategories =>
      categories.where((c) => c.cap > 0 && c.spent > c.cap).toList();

  /// Today's limit as of the start of today: what's left of the month
  /// before today, spread over the days left including today. Null without
  /// a budget.
  int? get dailyLimit {
    if (budget <= 0) return null;
    final daysInMonth = DateTime(computedAt.year, computedAt.month + 1, 0).day;
    final daysLeft = daysInMonth - computedAt.day + 1;
    final left = budget - (spent - todaySpent);
    return left <= 0 ? 0 : left ~/ daysLeft;
  }

  Map<String, Object> toJson() => {
    'v': 1,
    'computedAt': computedAt.millisecondsSinceEpoch,
    'month': month,
    'day': day,
    'currency': currency,
    'budget': budget,
    'spent': spent,
    'todaySpent': todaySpent,
    'categories': [for (final c in categories) c.toJson()],
  };
}
