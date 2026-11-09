import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/widgets/app_bottom_nav.dart';
import '../../core/widgets/app_card.dart';
import '../../core/widgets/list_row.dart';
import '../../core/widgets/page_transitions.dart';
import '../../core/widgets/section_header.dart';
import '../accounts/accounts_screen.dart';
import '../cards/cards_screen.dart';
import '../cycles/salary_cycles_screen.dart';
import '../income/income_screen.dart';
import '../expenses/add_transaction_sheet.dart';
import '../expenses/transactions_screen.dart';
import '../goals/goals_controller.dart';
import '../goals/goals_screen.dart';
import '../guardian/guardian_screen.dart';
import '../lending/lending_controller.dart';
import '../lending/lending_screen.dart';
import '../loans/loans_controller.dart';
import '../loans/loans_screen.dart';
import '../recurring/recurring_screen.dart';
import '../reminders/reminders_controller.dart';
import '../reminders/reminders_screen.dart';
import '../reports/reports_screen.dart';
import '../budgets/budgets_screen.dart';
import '../settings/settings_screen.dart';
import '../sms_import/sms_import_controller.dart';
import '../sms_import/sms_review_screen.dart';
import '../wishlist/wishlist_controller.dart';
import '../wishlist/wishlist_screen.dart';
import 'dashboard_screen.dart';

const _navItems = [
  AppNavItem(
    icon: Icons.home_outlined,
    selectedIcon: Icons.home_rounded,
    label: 'Home',
  ),
  AppNavItem(
    icon: Icons.receipt_long_outlined,
    selectedIcon: Icons.receipt_long_rounded,
    label: 'Transactions',
  ),
  AppNavItem(
    icon: Icons.insights_outlined,
    selectedIcon: Icons.insights_rounded,
    label: 'Reports',
  ),
  AppNavItem(
    icon: Icons.grid_view_outlined,
    selectedIcon: Icons.grid_view_rounded,
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

  void _select(int i) => setState(() => _index = i);

  late final List<Widget> _screens = [
    DashboardScreen(
      onSeeAllTransactions: () => _select(1),
      onOpenReports: () => _select(2),
    ),
    const TransactionsScreen(),
    const ReportsScreen(),
    const _MoreScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // The nav pill floats over content; screens pad their scroll views by
      // AppSpacing.navClearance so the last row can scroll clear of it.
      extendBody: true,
      body: IndexedStack(index: _index, children: _screens),
      bottomNavigationBar: AppBottomNav(
        items: _navItems,
        selectedIndex: _index,
        onSelected: _select,
        onAdd: () => showAddTransactionSheet(context),
      ),
    );
  }
}

class _MoreItem {
  final IconData icon;
  final Color color;
  final String label;
  final String subtitle;
  final void Function(BuildContext) open;
  const _MoreItem(this.icon, this.color, this.label, this.subtitle, this.open);
}

void _push(BuildContext context, Widget page) =>
    Navigator.of(context).push(FadeSlideRoute(page: page));

final _moreSections = <(String, List<_MoreItem>)>[
  (
    'Money',
    [
      _MoreItem(
        Icons.payments_rounded,
        AppColors.categoryPalette[2],
        'Salary & cycles',
        'Record salary, see each pay cycle',
        (c) => _push(c, const SalaryCyclesScreen()),
      ),
      _MoreItem(
        Icons.south_west_rounded,
        AppColors.categoryPalette[9],
        'Income',
        'By source, plus income you expect',
        (c) => _push(c, const IncomeScreen()),
      ),
      _MoreItem(
        Icons.account_balance_wallet_rounded,
        AppColors.categoryPalette[1],
        'Accounts',
        'Balances, transfers and pots',
        (c) => _push(c, const AccountsScreen()),
      ),
      _MoreItem(
        Icons.handshake_rounded,
        AppColors.categoryPalette[6],
        'Owed',
        'Money lent and borrowed',
        (c) {
          c.read<LendingController>().refresh();
          _push(c, const LendingScreen());
        },
      ),
      _MoreItem(
        Icons.credit_card_rounded,
        AppColors.categoryPalette[5],
        'Credit cards',
        'Statements, due dates, card EMIs',
        (c) => _push(c, const CardsScreen()),
      ),
      _MoreItem(
        Icons.account_balance_rounded,
        AppColors.categoryPalette[0],
        'Loans & EMI',
        'Repayment schedules',
        (c) {
          c.read<LoansController>().refresh();
          _push(c, const LoansScreen());
        },
      ),
      _MoreItem(
        Icons.event_repeat_rounded,
        AppColors.categoryPalette[5],
        'Recurring bills',
        'Subscriptions and fixed costs',
        (c) => _push(c, const RecurringScreen()),
      ),
    ],
  ),
  (
    'Planning',
    [
      _MoreItem(
        Icons.pie_chart_rounded,
        AppColors.categoryPalette[2],
        'Budgets',
        'Cycle, month, week, day and custom',
        (c) => _push(c, const BudgetsScreen()),
      ),
      if (defaultTargetPlatform == TargetPlatform.android)
        _MoreItem(
          Icons.shield_outlined,
          AppColors.categoryPalette[8],
          'Spending Guardian',
          'Budget alerts when you open a UPI app',
          (c) => _push(c, const GuardianScreen()),
        ),
      _MoreItem(
        Icons.flag_rounded,
        AppColors.categoryPalette[7],
        'Savings goals',
        'Track progress toward targets',
        (c) {
          c.read<GoalsController>().refresh();
          _push(c, const GoalsScreen());
        },
      ),
      _MoreItem(
        Icons.stars_rounded,
        AppColors.categoryPalette[4],
        'Wishlist',
        'Things you are saving for',
        (c) {
          c.read<WishlistController>().refresh();
          _push(c, const WishlistScreen());
        },
      ),
      _MoreItem(
        Icons.notifications_rounded,
        AppColors.categoryPalette[3],
        'Reminders',
        'Custom nudges',
        (c) {
          c.read<RemindersController>().refresh();
          _push(c, const RemindersScreen());
        },
      ),
    ],
  ),
  (
    'App',
    [
      _MoreItem(
        Icons.sms_rounded,
        AppColors.categoryPalette[9],
        'SMS import',
        'Review bank and UPI messages',
        (c) {
          c.read<SmsImportController>().refresh();
          _push(c, const SmsReviewScreen());
        },
      ),
      _MoreItem(
        Icons.settings_rounded,
        AppColors.categoryPalette[11],
        'Settings',
        'Currency, theme, security, data',
        (c) => _push(c, const SettingsScreen()),
      ),
    ],
  ),
];

class _MoreScreen extends StatelessWidget {
  const _MoreScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('More')),
      body: ListView.builder(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.page,
          AppSpacing.sm,
          AppSpacing.page,
          AppSpacing.navClearance,
        ),
        itemCount: _moreSections.length,
        itemBuilder: (context, i) {
          final (title, items) = _moreSections[i];
          return Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SectionHeader(title),
                AppCard(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.sm,
                    vertical: AppSpacing.xs,
                  ),
                  child: Column(
                    children: [
                      for (var j = 0; j < items.length; j++) ...[
                        if (j > 0)
                          Divider(
                            indent: AppSizes.iconBadge + AppSpacing.md + 4,
                            color: context.palette.border,
                          ),
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.xs,
                          ),
                          child: ListRow(
                            icon: items[j].icon,
                            iconColor: items[j].color,
                            title: items[j].label,
                            subtitle: items[j].subtitle,
                            trailing: const RowChevron(),
                            onTap: () => items[j].open(context),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
