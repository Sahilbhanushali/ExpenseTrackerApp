import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'core/theme/app_theme.dart';
import 'core/utils/notification_service.dart';
import 'core/widgets/aurora_background.dart';
import 'features/accounts/accounts_controller.dart';
import 'features/dashboard/home_shell.dart';
import 'features/expenses/expenses_controller.dart';
import 'features/goals/goals_controller.dart';
import 'features/lending/lending_controller.dart';
import 'features/recurring/recurring_controller.dart';
import 'features/settings/settings_controller.dart';
import 'features/wishlist/wishlist_controller.dart';

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
        ChangeNotifierProvider(create: (_) => WishlistController()),
        ChangeNotifierProvider(create: (_) => GoalsController()),
      ],
      child: MaterialApp(
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
/// manually from the Recurring & EMI screen, so re-opening the app can never
/// double-add a bill.
class _AppBootstrap extends StatefulWidget {
  const _AppBootstrap();

  @override
  State<_AppBootstrap> createState() => _AppBootstrapState();
}

class _AppBootstrapState extends State<_AppBootstrap>
    with WidgetsBindingObserver {
  bool _ready = false;

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
    if (state == AppLifecycleState.resumed && _ready) {
      _checkDueBills();
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
    final wishlist = context.read<WishlistController>();
    final goals = context.read<GoalsController>();

    await settings.init();
    await Future.wait([
      expenses.init(),
      accounts.init(),
      lending.init(),
      recurring.init(),
      wishlist.init(),
      goals.init(),
    ]);
    await _checkDueBills();
    if (mounted) setState(() => _ready = true);
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
    return const HomeShell();
  }
}
