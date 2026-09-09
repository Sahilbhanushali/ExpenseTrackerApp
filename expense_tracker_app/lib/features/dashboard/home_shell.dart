import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_spacing.dart';
import '../../core/widgets/app_bottom_nav.dart';
import '../../core/widgets/app_card.dart';
import '../../core/widgets/list_row.dart';
import '../../core/widgets/page_transitions.dart';
import '../../core/widgets/staggered_list.dart';
import '../accounts/accounts_screen.dart';
import '../expenses/add_transaction_sheet.dart';
import '../expenses/transactions_screen.dart';
import '../goals/goals_controller.dart';
import '../goals/goals_screen.dart';
import '../lending/lending_screen.dart';
import '../loans/loans_controller.dart';
import '../loans/loans_screen.dart';
import '../recurring/recurring_screen.dart';
import '../reminders/reminders_controller.dart';
import '../reminders/reminders_screen.dart';
import '../reports/reports_screen.dart';
import '../settings/settings_screen.dart';
import '../sms_import/sms_import_controller.dart';
import '../sms_import/sms_review_screen.dart';
import '../wishlist/wishlist_controller.dart';
import '../wishlist/wishlist_screen.dart';
import 'dashboard_screen.dart';

const _navItems = [
  AppNavItem(
    icon: Icons.dashboard_outlined,
    selectedIcon: Icons.dashboard,
    label: 'Dashboard',
  ),
  AppNavItem(
    icon: Icons.receipt_long_outlined,
    selectedIcon: Icons.receipt_long,
    label: 'Transactions',
  ),
  AppNavItem(
    icon: Icons.account_balance_wallet_outlined,
    selectedIcon: Icons.account_balance_wallet,
    label: 'Accounts',
  ),
  AppNavItem(
    icon: Icons.handshake_outlined,
    selectedIcon: Icons.handshake,
    label: 'Owed',
  ),
  AppNavItem(
    icon: Icons.more_horiz,
    selectedIcon: Icons.more_horiz,
    label: 'More',
  ),
];

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  static const _screens = [
    DashboardScreen(),
    TransactionsScreen(),
    AccountsScreen(),
    LendingScreen(),
    _MoreScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _index, children: _screens),
      // Explicit heroTag — every FAB in the app needs a unique one, since
      // IndexedStack keeps every tab mounted at once, and any two
      // FloatingActionButtons sharing the implicit default tag crash the
      // hero animation the moment they're both in the tree simultaneously
      // (e.g. this FAB plus a pushed screen's own FAB).
      floatingActionButton: _index == 0
          ? FloatingActionButton(
              heroTag: 'home_add_transaction',
              onPressed: () => showAddTransactionSheet(context),
              child: const Icon(Icons.add),
            )
          : null,
      bottomNavigationBar: AppBottomNav(
        items: _navItems,
        selectedIndex: _index,
        onSelected: (i) => setState(() => _index = i),
      ),
    );
  }
}

class _MoreScreen extends StatelessWidget {
  const _MoreScreen();

  @override
  Widget build(BuildContext context) {
    final tiles = [
      _MoreTile(
        icon: Icons.stars_outlined,
        label: 'Wishlist',
        onTap: () {
          context.read<WishlistController>().refresh();
          Navigator.of(context)
              .push(FadeSlideRoute(page: const WishlistScreen()));
        },
      ),
      _MoreTile(
        icon: Icons.bar_chart_outlined,
        label: 'Reports',
        onTap: () =>
            Navigator.of(context)
                .push(FadeSlideRoute(page: const ReportsScreen())),
      ),
      _MoreTile(
        icon: Icons.event_repeat_outlined,
        label: 'Recurring bills',
        onTap: () =>
            Navigator.of(context)
                .push(FadeSlideRoute(page: const RecurringScreen())),
      ),
      _MoreTile(
        icon: Icons.account_balance_outlined,
        label: 'Loans & EMI',
        onTap: () {
          context.read<LoansController>().refresh();
          Navigator.of(context).push(FadeSlideRoute(page: const LoansScreen()));
        },
      ),
      _MoreTile(
        icon: Icons.flag_outlined,
        label: 'Savings goals',
        onTap: () {
          context.read<GoalsController>().refresh();
          Navigator.of(context).push(FadeSlideRoute(page: const GoalsScreen()));
        },
      ),
      _MoreTile(
        icon: Icons.notifications_outlined,
        label: 'Reminders',
        onTap: () {
          context.read<RemindersController>().refresh();
          Navigator.of(context)
              .push(FadeSlideRoute(page: const RemindersScreen()));
        },
      ),
      _MoreTile(
        icon: Icons.sms_outlined,
        label: 'SMS import',
        onTap: () {
          context.read<SmsImportController>().refresh();
          Navigator.of(context)
              .push(FadeSlideRoute(page: const SmsReviewScreen()));
        },
      ),
      _MoreTile(
        icon: Icons.settings_outlined,
        label: 'Settings',
        onTap: () =>
            Navigator.of(context)
                .push(FadeSlideRoute(page: const SettingsScreen())),
      ),
    ];

    return Scaffold(
      appBar: AppBar(title: const Text('More')),
      body: ListView.separated(
        padding: const EdgeInsets.all(AppSpacing.lg),
        itemCount: tiles.length,
        separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.sm),
        itemBuilder: (context, i) =>
            StaggeredListItem(index: i, child: tiles[i]),
      ),
    );
  }
}

class _MoreTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _MoreTile({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: ListRow(
        icon: icon,
        title: label,
        onTap: onTap,
        trailing: Icon(
          Icons.chevron_right,
          color: Theme.of(context).colorScheme.outline,
        ),
      ),
    );
  }
}
