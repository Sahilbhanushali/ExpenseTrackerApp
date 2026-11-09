import 'dart:async';
import 'dart:convert';

import 'package:flutter/widgets.dart';

import '../expenses/expenses_controller.dart';
import '../settings/settings_controller.dart';
import 'guardian_models.dart';
import 'guardian_platform.dart';

/// UI state for Smart Spending Guardian, and the one place that keeps the
/// native monitor's budget figures current.
///
/// Sync: whenever the ledger ([ExpensesController]) or budgets
/// ([SettingsController]) change, a fresh [BudgetSnapshot] is computed from
/// the database and written to native storage. The native service reads only
/// that stored copy, so it works with no Flutter engine running, and every
/// copy carries its timestamp so old figures are labelled as such.
class GuardianController extends ChangeNotifier with WidgetsBindingObserver {
  final GuardianPlatform _platform;
  GuardianController([this._platform = const GuardianPlatform()]);

  ExpensesController? _expenses;
  SettingsController? _settings;
  Timer? _debounce;

  GuardianState? _state;

  /// Null until loaded, and always null where the Guardian isn't available.
  GuardianState? get state => _state;

  BudgetSnapshot? _snapshot;
  BudgetSnapshot? get snapshot => _snapshot;

  bool get supported => _platform.supported;
  bool get available => _state != null;

  /// When true, the native side posts the 80%/100%/over notifications, so
  /// the add-transaction flow must not post its own copy.
  bool get handlesBudgetNotifications =>
      _state?.settings.notifyThresholds ?? false;

  Future<void> attach(
    ExpensesController expenses,
    SettingsController settings,
  ) async {
    if (!_platform.supported) return;
    _expenses = expenses..addListener(_scheduleSync);
    _settings = settings..addListener(_scheduleSync);
    WidgetsBinding.instance.addObserver(this);
    await refreshState();
    await sync();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    // Permissions may have changed in system settings, and the day or
    // month may have rolled over while the app was in the background.
    refreshState();
    _scheduleSync();
  }

  void _scheduleSync() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), sync);
  }

  Future<void> sync() async {
    final expenses = _expenses, settings = _settings;
    if (expenses == null || settings == null) return;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final month = '${now.year}-${now.month.toString().padLeft(2, '0')}';
    try {
      // Queried for this exact month and day rather than read from the
      // controller's cache, which may predate a month rollover.
      final (total, cats, todayTotal) = await (
        expenses.monthTotalFor(month),
        expenses.categoryTotalsFor(month),
        expenses.totalsRange(today, today),
      ).wait;
      final config = settings.config;
      _snapshot = BudgetSnapshot(
        computedAt: now,
        currency: config.currency,
        budget: config.monthlyBudgetPaise,
        spent: total.expense,
        todaySpent: todayTotal.expense,
        categories: [
          for (final e in config.budgets.entries)
            if (e.value > 0) CategorySpend(e.key, e.value, cats[e.key] ?? 0),
        ],
      );
      notifyListeners();
      await _platform.pushSnapshot(jsonEncode(_snapshot!.toJson()));
    } catch (e) {
      debugPrint('Guardian sync failed: ${e.runtimeType}');
    }
  }

  Future<void> refreshState() async {
    final s = await _platform.getState();
    if (s == null) return;
    _state = s;
    notifyListeners();
  }

  /// Returns null on success, otherwise what's missing:
  /// 'usageAccess' | 'overlay' | 'startFailed' | 'unavailable'.
  Future<String?> setEnabled(bool enabled) async {
    if (enabled) await sync();
    final result = await _platform.setEnabled(enabled);
    await refreshState();
    if (result == null) return 'unavailable';
    return result == 'ok' ? null : result;
  }

  Future<void> update(Map<String, Object> values) async {
    final s = await _platform.updateSettings(values);
    if (s == null) return;
    _state = s;
    notifyListeners();
  }

  Future<void> toggleApp(String package, bool selected) {
    final apps = {...?_state?.settings.apps};
    selected ? apps.add(package) : apps.remove(package);
    return update({'apps': apps.toList()});
  }

  Future<bool> openSettings(String kind) => _platform.openSettings(kind);

  Future<String?> preview() async {
    await sync();
    return _platform.previewOverlay();
  }

  Future<void> resetStats() async {
    final s = await _platform.resetStats();
    if (s == null) return;
    _state = s;
    notifyListeners();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _expenses?.removeListener(_scheduleSync);
    _settings?.removeListener(_scheduleSync);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}
