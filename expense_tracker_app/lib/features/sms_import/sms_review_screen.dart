import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/utils/money_formatter.dart';
import '../../core/utils/sms_parser.dart';
import '../../core/widgets/app_card.dart';
import '../../core/widgets/staggered_list.dart';
import '../../data/models/pending_transaction.dart';
import '../accounts/accounts_controller.dart';
import '../expenses/expenses_controller.dart';
import '../settings/settings_controller.dart';
import 'sms_import_controller.dart';

/// Review queue for transactions detected from bank SMS that weren't
/// confident enough to log on their own, plus the on/off switch for the
/// whole feature.
class SmsReviewScreen extends StatelessWidget {
  const SmsReviewScreen({super.key});

  Future<void> _enable(BuildContext context) async {
    final sms = context.read<SmsImportController>();
    final messenger = ScaffoldMessenger.of(context);

    final granted = await sms.enable();
    if (!context.mounted) return;
    if (!granted) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text(
            'SMS access denied. Enable it in Settings › Apps › Spendo › '
            'Permissions to import bank messages.',
          ),
        ),
      );
      return;
    }
    await _refreshLedger(context);
  }

  Future<void> _rescan(BuildContext context) async {
    final sms = context.read<SmsImportController>();
    final messenger = ScaffoldMessenger.of(context);

    final result = await sms.scan();
    if (!context.mounted) return;
    await _refreshLedger(context);
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          result.total == 0
              ? 'No new transactions found.'
              : '${result.logged} logged, ${result.queued} to review.',
        ),
      ),
    );
  }

  /// Removes everything SMS import has written and imports again with the
  /// current detection rules — the fix for junk logged by an older, looser
  /// version of the parser.
  Future<void> _reimport(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Re-import from scratch?'),
        content: const Text(
          'Removes every transaction Spendo detected from SMS, then reads '
          'your inbox again using the current rules. Transactions you '
          'entered yourself are not touched.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Re-import'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    final sms = context.read<SmsImportController>();
    final messenger = ScaffoldMessenger.of(context);

    final result = await sms.reimport();
    if (!context.mounted) return;
    await _refreshLedger(context);
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          'Removed ${result.removed}, re-imported ${result.logged}, '
          '${result.queued} to review.',
        ),
      ),
    );
  }

  /// Sends the user to the system "Notification access" screen. UPI apps
  /// increasingly confirm a payment in-app without ever texting, so SMS
  /// alone misses them.
  Future<void> _enableNotifications(BuildContext context) async {
    final sms = context.read<SmsImportController>();
    final messenger = ScaffoldMessenger.of(context);
    final granted = await sms.enableNotifications();
    if (!context.mounted) return;
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          granted
              ? 'Reading payment notifications now.'
              : 'Not enabled. Find Spendo under Notification access in '
                    'system settings to turn it on.',
        ),
      ),
    );
  }

  /// Stops importing and empties the review queue. Transactions already
  /// logged stay — removing those is what "Re-import" is for.
  Future<void> _disable(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Turn off SMS import?'),
        content: const Text(
          'Spendo stops reading your messages and clears the review queue. '
          'Transactions already logged stay in your ledger.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Turn off'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    await context.read<SmsImportController>().disable();
  }

  /// Auto-logged rows land straight in the ledger, so the rest of the app
  /// has to be told to re-read.
  Future<void> _refreshLedger(BuildContext context) async {
    await context.read<ExpensesController>().refresh();
    if (!context.mounted) return;
    await context.read<AccountsController>().refresh();
  }

  @override
  Widget build(BuildContext context) {
    final sms = context.watch<SmsImportController>();
    final currency = context.watch<SettingsController>().config.currency;

    return Scaffold(
      appBar: AppBar(
        title: const Text('SMS import'),
        actions: [
          if (sms.isEnabled) ...[
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: 'Scan for new messages',
              onPressed: sms.isScanning ? null : () => _rescan(context),
            ),
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert),
              onSelected: (v) {
                if (v == 'reimport') _reimport(context);
                if (v == 'disable') _disable(context);
                if (v == 'notifications') _enableNotifications(context);
              },
              itemBuilder: (context) => [
                if (sms.notificationsSupported && !sms.notificationsEnabled)
                  const PopupMenuItem(
                    value: 'notifications',
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.notifications_none),
                      title: Text('Read payment notifications'),
                      subtitle: Text('For UPI apps that never text you'),
                    ),
                  ),
                const PopupMenuItem(
                  value: 'reimport',
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.cleaning_services_outlined),
                    title: Text('Re-import from scratch'),
                    subtitle: Text('Clears anything wrongly imported'),
                  ),
                ),
                const PopupMenuItem(
                  value: 'disable',
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.block),
                    title: Text('Turn off SMS import'),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
      body: !sms.isSupported
          ? const EmptyState(
              icon: Icons.phonelink_erase_outlined,
              message:
                  'Reading SMS is only possible on Android — iOS does not '
                  'allow any app to access messages.',
            )
          : sms.isScanning
          ? const Center(child: CircularProgressIndicator())
          : !sms.isEnabled
          ? _SetupPanel(onEnable: () => _enable(context))
          : sms.pending.isEmpty
          ? ListView(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.page,
                AppSpacing.sm,
                AppSpacing.page,
                AppSpacing.navClearance,
              ),
              children: [
                const EmptyState(
                  icon: Icons.mark_email_read_outlined,
                  message:
                      'Nothing waiting for review. Confident bank messages '
                      'are logged automatically.',
                ),
                if (sms.notificationsSupported) ...[
                  const SizedBox(height: AppSpacing.md),
                  _NotificationPanel(
                    enabled: sms.notificationsEnabled,
                    onEnable: () => _enableNotifications(context),
                  ),
                ],
              ],
            )
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.page,
                AppSpacing.sm,
                AppSpacing.page,
                AppSpacing.navClearance,
              ),
              itemCount: sms.pending.length,
              separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.sm),
              itemBuilder: (context, i) => StaggeredListItem(
                index: i,
                child: _PendingCard(
                  pending: sms.pending[i],
                  currency: currency,
                  onApprove: () async {
                    await sms.approve(sms.pending[i]);
                    if (context.mounted) await _refreshLedger(context);
                  },
                  onDismiss: () => sms.dismiss(sms.pending[i]),
                ),
              ),
            ),
    );
  }
}

/// The second, broader switch: reading payment-app notifications.
class _NotificationPanel extends StatelessWidget {
  final bool enabled;
  final VoidCallback onEnable;

  const _NotificationPanel({required this.enabled, required this.onEnable});

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                enabled
                    ? Icons.notifications_active_outlined
                    : Icons.notifications_off_outlined,
                color: enabled
                    ? context.palette.income
                    : context.palette.savings,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  enabled
                      ? 'Reading payment notifications'
                      : 'Also read payment notifications',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            enabled
                ? 'Payments confirmed only inside GPay, PhonePe, Paytm and '
                      'banking apps are picked up too.'
                : 'UPI apps often confirm a payment in the app without '
                      'texting you, so those spends never reach Spendo. '
                      'Only notifications from payment and banking apps are '
                      'read — nothing else is looked at.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          if (!enabled) ...[
            const SizedBox(height: AppSpacing.md),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: onEnable,
                icon: const Icon(Icons.notifications_none),
                label: const Text('Turn on notification access'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _SetupPanel extends StatelessWidget {
  final VoidCallback onEnable;
  const _SetupPanel({required this.onEnable});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.page,
        AppSpacing.sm,
        AppSpacing.page,
        AppSpacing.navClearance,
      ),
      children: [
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.sms_outlined, color: context.palette.savings),
                  const SizedBox(width: AppSpacing.sm),
                  Text(
                    'Log spending automatically',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              Text(
                'Spendo can read your bank and card SMS to log transactions '
                'for you. Messages that clearly come from a bank are logged '
                'straight away; anything uncertain waits here for your '
                'approval.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: AppSpacing.md),
              Text(
                'Turning this on imports the last 6 months so your history '
                'and reports are useful immediately. Messages are read on '
                'this device only and are never uploaded anywhere.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: AppSpacing.lg),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: onEnable,
                  icon: const Icon(Icons.download_outlined),
                  label: const Text('Turn on SMS import'),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _PendingCard extends StatelessWidget {
  final PendingTransaction pending;
  final String currency;
  final VoidCallback onApprove;
  final VoidCallback onDismiss;

  const _PendingCard({
    required this.pending,
    required this.currency,
    required this.onApprove,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    final isCredit = pending.direction == SmsDirection.credit;
    final color = isCredit ? context.palette.income : context.palette.expense;
    final d = pending.occurredAt;
    final dateLabel =
        '${d.day.toString().padLeft(2, '0')}/'
        '${d.month.toString().padLeft(2, '0')}/${d.year}';

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  pending.displayTitle,
                  style: Theme.of(context).textTheme.titleMedium,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(
                '${isCredit ? '+' : '-'}${formatMoney(pending.amountPaise, currency)}',
                style: Theme.of(context).textTheme.titleMedium
                    ?.copyWith(color: color, fontWeight: FontWeight.w800),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            [
              dateLabel,
              pending.category,
              if (pending.accountTail != null) '••${pending.accountTail}',
            ].join(' · '),
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: AppSpacing.sm),
          // The original message, so an ambiguous parse can be judged
          // against what the bank actually said.
          Text(
            pending.rawBody,
            style: Theme.of(context).textTheme.bodySmall,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: onDismiss,
                child: const Text('Not a spend'),
              ),
              const SizedBox(width: AppSpacing.sm),
              FilledButton(onPressed: onApprove, child: const Text('Log it')),
            ],
          ),
        ],
      ),
    );
  }
}
