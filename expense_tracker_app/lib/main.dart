import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:quick_actions/quick_actions.dart';

import 'core/theme/app_theme.dart';
import 'core/utils/app_lock_service.dart';
import 'core/utils/notification_service.dart';
import 'core/widgets/aurora_background.dart';
import 'features/accounts/accounts_controller.dart';
import 'features/dashboard/home_shell.dart';
import 'features/expenses/add_transaction_sheet.dart';
import 'features/expenses/expenses_controller.dart';
import 'features/goals/goals_controller.dart';
import 'features/lending/lending_controller.dart';
import 'features/loans/loans_controller.dart';
import 'features/recurring/recurring_controller.dart';
import 'features/security/lock_screen.dart';
import 'features/settings/settings_controller.dart';
import 'features/wishlist/wishlist_controller.dart';

/// Lets the app-icon long-press shortcut ("Add expense") reach the add-sheet
/// even when it fires before HomeShell has built any local context.
final navigatorKey = GlobalKey<NavigatorState>();

void main() {
  runApp(const ExpenseTrackerApp());
}

class ExpenseTrackerApp extends StatelessWidget {
  const ExpenseTrackerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => SettingsController()),
        ChangeNotifierProvider(create: (_) => ExpensesController()),
        ChangeNotifierProvider(create: (_) => AccountsController()),
        ChangeNotifierProvider(create: (_) => LendingController()),
        ChangeNotifierProvider(create: (_) => RecurringController()),
        ChangeNotifierProvider(create: (_) => LoansController()),
        ChangeNotifierProvider(create: (_) => WishlistController()),
        ChangeNotifierProvider(create: (_) => GoalsController()),
      ],
      child: MaterialApp(
        navigatorKey: navigatorKey,
        title: 'Expense Tracker',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(),
        darkTheme: AppTheme.dark(),
        // A single AuroraBackground behind the whole Navigator, so it never
        // rebuilds or restarts its animation as screens push/pop — every
        // Scaffold is transparent (see AppTheme) and lets it show through.
        builder: (context, child) => Stack(
          children: [
            const Positioned.fill(child: AuroraBackground()),
            ?child,
          ],
        ),
        home: const _AppBootstrap(),
      ),
    );
  }
}

/// Loads config + initial data, then checks (read-only) which recurring
/// bills have come due — nothing is auto-logged. The user confirms each one
/// manually from the Recurring bills screen, so re-opening the app can never
/// double-add a bill.
class _AppBootstrap extends StatefulWidget {
  const _AppBootstrap();

  @override
  State<_AppBootstrap> createState() => _AppBootstrapState();
}

class _AppBootstrapState extends State<_AppBootstrap>
    with WidgetsBindingObserver {
  bool _ready = false;
  bool _locked = false;
  DateTime? _pausedAt;

  /// How long the app can sit backgrounded before the next resume re-locks
  /// it. Below this, a resume is treated as "still using the app" — e.g.
  /// the receipt camera, a share sheet, or a file picker all briefly pause
  /// the app without the user actually having left it.
  static const _lockGracePeriod = Duration(seconds: 30);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _bootstrap();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_ready) return;
    if (state == AppLifecycleState.resumed) {
      _checkDueBills();
      _maybeRelock();
    }
    if (state == AppLifecycleState.paused) {
      _pausedAt = DateTime.now();
    }
  }

  Future<void> _maybeRelock() async {
    final pausedAt = _pausedAt;
    _pausedAt = null;
    if (pausedAt == null) return;
    if (DateTime.now().difference(pausedAt) < _lockGracePeriod) return;
    if (await AppLockService.instance.isEnabled() && mounted) {
      setState(() => _locked = true);
    }
  }

  Future<void> _bootstrap() async {
    await NotificationService.instance.init();
    if (!mounted) return;
    final settings = context.read<SettingsController>();
    final expenses = context.read<ExpensesController>();
    final accounts = context.read<AccountsController>();
    final lending = context.read<LendingController>();
    final recurring = context.read<RecurringController>();
    final loans = context.read<LoansController>();
    final wishlist = context.read<WishlistController>();
    final goals = context.read<GoalsController>();

    await settings.init();
    await Future.wait([
      expenses.init(),
      accounts.init(),
      lending.init(),
      recurring.init(),
      loans.init(),
      wishlist.init(),
      goals.init(),
    ]);
    await _checkDueBills();
    _initQuickActions();
    final locked = await AppLockService.instance.isEnabled();
    if (mounted) {
      setState(() {
        _ready = true;
        _locked = locked;
      });
    }
  }

  /// Wires the "Add expense" long-press app-icon shortcut straight to the
  /// add-transaction sheet, skipping the dashboard entirely.
  void _initQuickActions() {
    const quickActions = QuickActions();
    quickActions.initialize((type) {
      if (type != 'add_expense') return;
      final ctx = navigatorKey.currentContext;
      if (ctx != null) showAddTransactionSheet(ctx);
    });
    quickActions.setShortcutItems([
      const ShortcutItem(type: 'add_expense', localizedTitle: 'Add expense'),
    ]);
  }

  Future<void> _checkDueBills() async {
    if (!mounted) return;
    final due = await context.read<RecurringController>().refreshDue();
    if (due.isNotEmpty && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${due.length} recurring item(s) due — log them from Recurring & EMI',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    // HomeShell stays mounted underneath even while locked, so its selected
    // tab, scroll positions, etc. survive a lock/unlock cycle instead of
    // resetting to the dashboard every time.
    return Stack(
      children: [
        const HomeShell(),
        if (_locked)
          Positioned.fill(
            child: UnlockScreen(
              onUnlocked: () => setState(() => _locked = false),
            ),
          ),
      ],
    );
  }
}
