import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:quick_actions/quick_actions.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';

import 'core/theme/app_theme.dart';
import 'core/utils/app_lock_service.dart';
import 'core/utils/error_reporting.dart';
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
import 'features/reminders/reminders_controller.dart';
import 'features/security/lock_screen.dart';
import 'features/sms_import/sms_import_controller.dart';
import 'features/settings/settings_controller.dart';
import 'features/splash/splash_screen.dart';
import 'features/splash/startup_failure_screen.dart';
import 'features/wishlist/wishlist_controller.dart';

/// Lets the app-icon long-press shortcut ("Add expense") reach the add-sheet
/// even when it fires before HomeShell has built any local context.
final navigatorKey = GlobalKey<NavigatorState>();

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  installErrorHandlers(navigatorKey);
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
        ChangeNotifierProvider(create: (_) => RemindersController()),
        ChangeNotifierProvider(create: (_) => SmsImportController()),
      ],
      child: MaterialApp(
        navigatorKey: navigatorKey,
        title: 'Spendo',
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
  StreamSubscription<List<SharedMediaFile>>? _shareSub;

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
    _shareSub?.cancel();
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

  /// The splash's entrance animation runs for about this long — on a fast
  /// device the real bootstrap work below finishes well before that, which
  /// would otherwise cut the animation off mid-sequence.
  static const _minSplashDuration = Duration(milliseconds: 1400);

  Future<void> _bootstrap() async {
    final minDuration = Future.delayed(_minSplashDuration);
    // One controller failing to load (a corrupt row, a migration that threw)
    // used to leave `_ready` false forever — the splash just never ended.
    // Surface it instead, with a way back.
    Object? failure;
    try {
      await _loadAppState();
    } catch (e, stack) {
      failure = e;
      if (kDebugMode) debugPrintStack(stackTrace: stack, label: '$e');
    }
    await minDuration;
    if (mounted) {
      setState(() {
        _startupError = failure;
        _ready = true;
        _locked = _pendingLocked;
      });
    }
  }

  Object? _startupError;
  bool _pendingLocked = false;

  Future<void> _loadAppState() async {
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
    final reminders = context.read<RemindersController>();
    final smsImport = context.read<SmsImportController>();

    await settings.init();
    await Future.wait([
      expenses.init(),
      accounts.init(),
      lending.init(),
      recurring.init(),
      loans.init(),
      wishlist.init(),
      goals.init(),
      reminders.init(),
      smsImport.init(),
    ]);
    await _checkDueBills();
    _initQuickActions();
    _initShareIntent();
    _pendingLocked = await AppLockService.instance.isEnabled();
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

  /// Lets other apps (a UPI app's payment confirmation "Share" option, SMS,
  /// etc.) hand text straight to the add-transaction sheet via Android's
  /// share sheet — the text is only parsed into a preview, never logged
  /// without the user confirming it, same as the quick-add text field.
  void _initShareIntent() {
    _shareSub = ReceiveSharingIntent.instance.getMediaStream().listen(
      _handleSharedFiles,
    );
    ReceiveSharingIntent.instance.getInitialMedia().then((files) {
      _handleSharedFiles(files);
      ReceiveSharingIntent.instance.reset();
    });
  }

  void _handleSharedFiles(List<SharedMediaFile> files) {
    for (final file in files) {
      if (file.type == SharedMediaType.text && file.path.trim().isNotEmpty) {
        final ctx = navigatorKey.currentContext;
        if (ctx != null) {
          showAddTransactionSheet(ctx, initialText: file.path);
        }
        return;
      }
    }
  }

  /// Refreshes which recurring bills are due so the "Due now" section on
  /// the Recurring screen stays current. Deliberately silent otherwise —
  /// due bills already get a real push notification
  /// (RecurringController.addBill schedules one), so a second, in-app
  /// "X due" banner on every launch/resume was just a redundant nag.
  Future<void> _checkDueBills() async {
    if (!mounted) return;
    await context.read<RecurringController>().refreshDue();
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready) {
      return const SplashScreen();
    }
    if (_startupError != null) {
      return StartupFailureScreen(
        onRetry: () {
          setState(() {
            _ready = false;
            _startupError = null;
          });
          _bootstrap();
        },
      );
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
