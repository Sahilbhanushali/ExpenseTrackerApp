import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_spacing.dart';
import '../../core/widgets/app_bottom_nav.dart';
import '../../core/widgets/page_transitions.dart';
import '../../core/widgets/press_scale.dart';
import '../accounts/accounts_screen.dart';
import '../expenses/add_transaction_sheet.dart';
import '../expenses/transactions_screen.dart';
import '../goals/goals_controller.dart';
import '../goals/goals_screen.dart';
import '../lending/lending_screen.dart';
import '../recurring/recurring_screen.dart';
import '../settings/settings_screen.dart';
import '../wishlist/wishlist_controller.dart';
import '../wishlist/wishlist_screen.dart';
import 'dashboard_screen.dart';

const _navItems = [
  AppNavItem(icon: Icons.dashboard_outlined, selectedIcon: Icons.dashboard, label: 'Dashboard'),
  AppNavItem(icon: Icons.receipt_long_outlined, selectedIcon: Icons.receipt_long, label: 'Transactions'),
  AppNavItem(icon: Icons.account_balance_wallet_outlined, selectedIcon: Icons.account_balance_wallet, label: 'Accounts'),
  AppNavItem(icon: Icons.handshake_outlined, selectedIcon: Icons.handshake, label: 'Owed'),
  AppNavItem(icon: Icons.more_horiz, selectedIcon: Icons.more_horiz, label: 'More'),
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
      floatingActionButton: _index == 0
          ? FloatingActionButton(
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
    return Scaffold(
      appBar: AppBar(title: const Text('More')),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
        children: [
          _MoreTile(
            icon: Icons.stars_outlined,
            label: 'Wishlist',
            onTap: () {
              context.read<WishlistController>().refresh();
              Navigator.of(context).push(FadeSlideRoute(page: const WishlistScreen()));
            },
          ),
          _MoreTile(
            icon: Icons.event_repeat_outlined,
            label: 'Recurring & EMI',
            onTap: () => Navigator.of(context).push(FadeSlideRoute(page: const RecurringScreen())),
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
            icon: Icons.settings_outlined,
            label: 'Settings',
            onTap: () => Navigator.of(context).push(FadeSlideRoute(page: const SettingsScreen())),
          ),
        ],
      ),
    );
  }
}

class _MoreTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _MoreTile({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return PressScale(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.sm),
        child: Row(
          children: [
            Icon(icon, color: Theme.of(context).colorScheme.outline),
            const SizedBox(width: AppSpacing.md),
            Expanded(child: Text(label, style: Theme.of(context).textTheme.bodyLarge)),
            Icon(Icons.chevron_right, color: Theme.of(context).colorScheme.outline),
          ],
        ),
      ),
    );
  }
}
