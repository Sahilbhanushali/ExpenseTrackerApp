import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/money_formatter.dart';
import '../../core/utils/notification_service.dart';
import '../../core/widgets/app_card.dart';
import '../../core/widgets/app_chip.dart';
import '../../core/widgets/budget_progress_bar.dart';
import '../../core/widgets/list_row.dart';
import '../../core/widgets/page_transitions.dart';
import '../../core/widgets/responsive.dart';
import '../../core/widgets/settings_group.dart';
import '../settings/budget_planner_screen.dart';
import 'guardian_controller.dart';
import 'guardian_models.dart';

const _cooldowns = <(int, String)>[
  (0, 'Every opening'),
  (5, '5 min'),
  (15, '15 min'),
  (30, '30 min'),
  (60, '1 hour'),
  (180, '3 hours'),
];

class GuardianScreen extends StatefulWidget {
  const GuardianScreen({super.key});

  @override
  State<GuardianScreen> createState() => _GuardianScreenState();
}

class _GuardianScreenState extends State<GuardianScreen> {
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final guardian = context.read<GuardianController>();
    await guardian.refreshState();
    if (guardian.available) await guardian.sync();
    if (mounted) setState(() => _loading = false);
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _setEnabled(bool on) async {
    final guardian = context.read<GuardianController>();
    final perms = guardian.state!.permissions;
    if (on && !perms.canMonitor) {
      await _explainPermissions(perms);
      return;
    }
    final error = await guardian.setEnabled(on);
    if (!mounted) return;
    switch (error) {
      case null:
        _snack(on ? 'Monitoring is on.' : 'Monitoring stopped.');
      case 'usageAccess' || 'overlay':
        await _explainPermissions(guardian.state!.permissions);
      default:
        _snack("Android didn't allow monitoring to start. Try again.");
    }
  }

  Future<void> _explainPermissions(GuardianPermissions perms) {
    return showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheet) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.page,
            0,
            AppSpacing.page,
            AppSpacing.lg,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Two permissions needed',
                style: Theme.of(sheet).textTheme.titleLarge,
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                'Turn these on in Android settings, then come back and switch '
                'monitoring on.',
                style: Theme.of(sheet).textTheme.bodyMedium,
              ),
              const SizedBox(height: AppSpacing.md),
              _PermissionRow(
                icon: Icons.query_stats_rounded,
                title: 'Usage access',
                explanation: 'To notice when you open a UPI app you selected.',
                granted: perms.usageAccess,
                onOpen: () => _open('usageAccess'),
              ),
              const Divider(),
              _PermissionRow(
                icon: Icons.layers_outlined,
                title: 'Display over other apps',
                explanation: 'To show the budget card on top of that app.',
                granted: perms.overlay,
                onOpen: () => _open('overlay'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _open(String kind) async {
    final ok = await context.read<GuardianController>().openSettings(kind);
    if (!ok && mounted) _snack("Couldn't open that settings page.");
  }

  Future<void> _requestNotifications() async {
    final granted = await NotificationService.instance.requestPermission();
    if (!mounted) return;
    if (!granted) await _open('notifications');
    if (mounted) await context.read<GuardianController>().refreshState();
  }

  Future<void> _preview() async {
    final result = await context.read<GuardianController>().preview();
    if (!mounted) return;
    switch (result) {
      case 'ok':
        break;
      case 'overlay':
        _snack('Allow "Display over other apps" to preview the alert.');
      case 'noBudget':
        _snack('Set a monthly or category budget first.');
      default:
        _snack('No budget figures yet. Add a transaction or set a budget.');
    }
  }

  Future<void> _confirmReset() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('Reset statistics?'),
        content: const Text(
          'Clears the alert, budget-exceeded and app-opening counts. '
          'Your settings stay as they are.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialog, true),
            child: const Text('Reset'),
          ),
        ],
      ),
    );
    if (ok == true && mounted) {
      await context.read<GuardianController>().resetStats();
    }
  }

  @override
  Widget build(BuildContext context) {
    final guardian = context.watch<GuardianController>();
    final state = guardian.state;

    return Scaffold(
      appBar: AppBar(title: const Text('Smart Spending Guardian')),
      body: !guardian.supported
          ? const EmptyState(
              icon: Icons.android_rounded,
              title: 'Android only',
              message:
                  'Spending Guardian relies on Android features that other '
                  'platforms don’t offer.',
            )
          : state == null
          ? (_loading
                ? const Padding(
                    padding: EdgeInsets.all(AppSpacing.page),
                    child: SkeletonList(),
                  )
                : ErrorState(
                    message: "Couldn't reach the monitoring service.",
                    onRetry: () {
                      setState(() => _loading = true);
                      _load();
                    },
                  ))
          : ResponsivePage(
              builder: (context, gutter) => ListView(
                padding: EdgeInsets.fromLTRB(
                  gutter,
                  AppSpacing.sm,
                  gutter,
                  AppSpacing.xl,
                ),
                children: [
                  _StatusCard(
                    state: state,
                    snapshot: guardian.snapshot,
                    onToggle: _setEnabled,
                    onPreview: _preview,
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  _AppsGroup(state: state),
                  _AlertsGroup(settings: state.settings),
                  _PermissionsGroup(
                    state: state,
                    onOpen: _open,
                    onRequestNotifications: _requestNotifications,
                  ),
                  _StatsGroup(
                    state: state,
                    snapshot: guardian.snapshot,
                    onReset: _confirmReset,
                  ),
                  const _PrivacyGroup(),
                ],
              ),
            ),
    );
  }
}

/// A — on/off, health, selected apps and where spending stands right now.
class _StatusCard extends StatelessWidget {
  final GuardianState state;
  final BudgetSnapshot? snapshot;
  final ValueChanged<bool> onToggle;
  final VoidCallback onPreview;

  const _StatusCard({
    required this.state,
    required this.snapshot,
    required this.onToggle,
    required this.onPreview,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final text = Theme.of(context).textTheme;
    final s = state.settings;
    final selected = [
      for (final app in kGuardianApps)
        if (s.apps.contains(app.package) &&
            state.installed[app.package] != false)
          app.label,
    ];

    final (String status, Color statusColor) = switch (state) {
      _ when !s.enabled => ('Off', p.textSecondary),
      _ when !state.permissions.canMonitor => (
        'Paused: a permission was turned off',
        p.warning,
      ),
      _ when !state.running => (
        'Stopped by Android. Switch off and on to restart.',
        p.warning,
      ),
      _ when selected.isEmpty => (
        'On, but no installed apps selected',
        p.warning,
      ),
      _ => ('On, watching ${selected.join(', ')}', p.income),
    };

    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.md + 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: AppSizes.iconBadge,
                height: AppSizes.iconBadge,
                decoration: BoxDecoration(
                  color: p.savings.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                ),
                child: Icon(Icons.shield_outlined, color: p.savings),
              ),
              const SizedBox(width: AppSpacing.md - 4),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Monitoring', style: text.titleMedium),
                    const SizedBox(height: AppSpacing.xxs),
                    Text(
                      status,
                      style: text.bodySmall?.copyWith(color: statusColor),
                    ),
                  ],
                ),
              ),
              Semantics(
                label: 'Spending Guardian monitoring',
                child: Switch(value: s.enabled, onChanged: onToggle),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          const Divider(height: 1),
          const SizedBox(height: AppSpacing.md),
          _SpendingStatus(snapshot: snapshot, cautionPercent: s.cautionPercent),
          const SizedBox(height: AppSpacing.md),
          OutlinedButton.icon(
            onPressed: onPreview,
            icon: const Icon(Icons.visibility_outlined),
            label: const Text('Preview alert'),
          ),
        ],
      ),
    );
  }
}

class _SpendingStatus extends StatelessWidget {
  final BudgetSnapshot? snapshot;
  final int cautionPercent;
  const _SpendingStatus({required this.snapshot, required this.cautionPercent});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final text = Theme.of(context).textTheme;
    final snap = snapshot;
    if (snap == null || snap.budget <= 0) {
      return Row(
        children: [
          Expanded(
            child: Text(
              'Set a monthly budget so the Guardian knows when to warn you.',
              style: text.bodyMedium,
            ),
          ),
          TextButton(
            onPressed: () =>
                Navigator.of(context)
                    .push(FadeSlideRoute(page: const BudgetPlannerScreen())),
            child: const Text('Set budget'),
          ),
        ],
      );
    }
    final cur = snap.currency;
    final level = guardianLevel(snap.spent, snap.budget, cautionPercent);
    final (String label, Color color) = switch (level) {
      GuardianLevel.exceeded => (
        'Over by ${formatMoney(snap.spent - snap.budget, cur)}',
        p.expense,
      ),
      GuardianLevel.reached => ('Limit reached', p.expense),
      GuardianLevel.caution => ('Close to limit', p.warning),
      GuardianLevel.none => ('On track', p.income),
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Spent this month', style: text.labelMedium),
                  const SizedBox(height: AppSpacing.xxs),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      '${formatMoney(snap.spent, cur)} of ${formatMoney(snap.budget, cur)}',
                      style: text.moneyStyle(18),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Text(
              '${snap.percent}%',
              style: text.titleMedium?.copyWith(color: color),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        BudgetProgressBar(spent: snap.spent, budget: snap.budget, color: color),
        const SizedBox(height: AppSpacing.xs + 2),
        Text(label, style: text.labelMedium?.copyWith(color: color)),
      ],
    );
  }
}

/// B — which UPI apps to watch.
class _AppsGroup extends StatelessWidget {
  final GuardianState state;
  const _AppsGroup({required this.state});

  @override
  Widget build(BuildContext context) {
    final guardian = context.read<GuardianController>();
    final p = context.palette;
    return SettingsGroup(
      title: 'Apps to watch',
      children: [
        for (final (i, app) in kGuardianApps.indexed)
          Builder(
            builder: (context) {
              final installed = state.installed[app.package] ?? false;
              final selected = state.settings.apps.contains(app.package);
              return ListRow(
                icon: Icons.account_balance_wallet_outlined,
                iconColor: AppColors.categoryPalette[i],
                title: app.label,
                subtitle: installed
                    ? 'Installed'
                    : 'Not installed on this phone',
                trailing: Switch(
                  value: selected,
                  // An app that isn't installed can be unticked but not ticked.
                  onChanged: installed || selected
                      ? (v) => guardian.toggleApp(app.package, v)
                      : null,
                ),
              );
            },
          ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
          child: Text(
            'Only these apps are watched. Others are never alerted on.',
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(color: p.textSecondary),
          ),
        ),
      ],
    );
  }
}

/// C — what to alert on, and how often.
class _AlertsGroup extends StatelessWidget {
  final GuardianSettings settings;
  const _AlertsGroup({required this.settings});

  @override
  Widget build(BuildContext context) {
    final guardian = context.read<GuardianController>();
    final text = Theme.of(context).textTheme;
    Widget toggle(
      IconData icon,
      String title,
      String subtitle,
      bool value,
      String key,
    ) => ListRow(
      icon: icon,
      title: title,
      subtitle: subtitle,
      trailing: Switch(
        value: value,
        onChanged: (v) => guardian.update({key: v}),
      ),
    );

    return SettingsGroup(
      title: 'Budget alerts',
      children: [
        _ThresholdSlider(
          value: settings.cautionPercent,
          onChanged: (v) => guardian.update({'cautionPercent': v}),
        ),
        toggle(
          Icons.warning_amber_rounded,
          'Caution alerts',
          'When ${settings.cautionPercent}% of your monthly budget is used',
          settings.alertCaution,
          'alertCaution',
        ),
        toggle(
          Icons.block_rounded,
          'Limit reached and exceeded',
          'At 100% of your monthly budget and beyond',
          settings.alertLimit,
          'alertLimit',
        ),
        toggle(
          Icons.category_outlined,
          'Category budgets',
          'When a category goes over its own budget',
          settings.alertCategory,
          'alertCategory',
        ),
        toggle(
          Icons.today_rounded,
          'Daily limit',
          "When today's spending passes your fair share of what's left this month",
          settings.alertDaily,
          'alertDaily',
        ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const ListRow(
                icon: Icons.timer_outlined,
                title: 'Quiet time after an alert',
                subtitle:
                    'No repeat alert for this long, unless things get worse',
              ),
              const SizedBox(height: AppSpacing.sm),
              ChipRow(
                children: [
                  for (final (minutes, label) in _cooldowns)
                    AppChoiceChip(
                      label: label,
                      selected: settings.cooldownMinutes == minutes,
                      onTap: () =>
                          guardian.update({'cooldownMinutes': minutes}),
                    ),
                ],
              ),
            ],
          ),
        ),
        toggle(
          Icons.notifications_active_outlined,
          'Budget notifications',
          'Notify once at ${settings.cautionPercent}%, 100% and over, even '
              'with monitoring off',
          settings.notifyThresholds,
          'notifyThresholds',
        ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
          child: Text(
            'Alerts never guess what you are about to buy. Category alerts '
            'use only spending you have already recorded.',
            style: text.bodySmall,
          ),
        ),
      ],
    );
  }
}

class _ThresholdSlider extends StatefulWidget {
  final int value;
  final ValueChanged<int> onChanged;
  const _ThresholdSlider({required this.value, required this.onChanged});

  @override
  State<_ThresholdSlider> createState() => _ThresholdSliderState();
}

class _ThresholdSliderState extends State<_ThresholdSlider> {
  late double _value = widget.value.toDouble();

  @override
  void didUpdateWidget(_ThresholdSlider oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value) _value = widget.value.toDouble();
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ListRow(
            icon: Icons.tune_rounded,
            title: 'Caution threshold',
            subtitle: 'Warn once spending reaches this share of the budget',
            trailing: Text('${_value.round()}%', style: text.titleMedium),
          ),
          Slider(
            value: _value,
            min: 50,
            max: 95,
            divisions: 9,
            label: '${_value.round()}%',
            semanticFormatterCallback: (v) => '${v.round()} percent',
            onChanged: (v) => setState(() => _value = v),
            onChangeEnd: (v) => widget.onChanged(v.round()),
          ),
        ],
      ),
    );
  }
}

/// D — each permission, why it's needed, and a way to grant it.
class _PermissionsGroup extends StatelessWidget {
  final GuardianState state;
  final ValueChanged<String> onOpen;
  final VoidCallback onRequestNotifications;

  const _PermissionsGroup({
    required this.state,
    required this.onOpen,
    required this.onRequestNotifications,
  });

  @override
  Widget build(BuildContext context) {
    final perms = state.permissions;
    return SettingsGroup(
      title: 'Permissions',
      children: [
        _PermissionRow(
          icon: Icons.query_stats_rounded,
          title: 'Usage access',
          explanation:
              'Tells Spendo which app is open, by name only, so it knows when '
              'you open a UPI app you selected. Required.',
          granted: perms.usageAccess,
          onOpen: () => onOpen('usageAccess'),
        ),
        _PermissionRow(
          icon: Icons.layers_outlined,
          title: 'Display over other apps',
          explanation:
              'Lets the budget card appear on top of the UPI app. Required.',
          granted: perms.overlay,
          onOpen: () => onOpen('overlay'),
        ),
        _PermissionRow(
          icon: Icons.notifications_outlined,
          title: 'Notifications',
          explanation:
              'For the "monitoring is on" notification and budget alerts.',
          granted: perms.notifications,
          onOpen: onRequestNotifications,
        ),
        _PermissionRow(
          icon: Icons.battery_saver_outlined,
          title: 'Battery: unrestricted',
          explanation:
              'Optional. Some phones (Xiaomi, Oppo, Vivo, Samsung and others) '
              'stop background apps to save power. Allowing Spendo to run '
              'unrestricted keeps alerts reliable. Android may still pause '
              'monitoring.',
          granted: perms.batteryUnrestricted,
          grantedLabel: 'Unrestricted',
          deniedLabel: 'Optimised',
          onOpen: () => onOpen('battery'),
        ),
        _PermissionRow(
          icon: Icons.sync_rounded,
          title: 'Monitoring service',
          explanation: state.running
              ? 'Running, with a notification you can stop it from.'
              : state.settings.enabled
              ? 'Not running. Android may have stopped it. Switch monitoring '
                    'off and on to restart.'
              : 'Starts when you turn monitoring on.',
          granted: state.running,
          grantedLabel: 'Running',
          deniedLabel: 'Stopped',
        ),
      ],
    );
  }
}

class _PermissionRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String explanation;
  final bool granted;
  final String grantedLabel;
  final String deniedLabel;
  final VoidCallback? onOpen;

  const _PermissionRow({
    required this.icon,
    required this.title,
    required this.explanation,
    required this.granted,
    this.grantedLabel = 'Allowed',
    this.deniedLabel = 'Not allowed',
    this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final text = Theme.of(context).textTheme;
    final color = granted ? p.income : p.warning;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ListRow(icon: icon, title: title, subtitle: explanation),
          const SizedBox(height: AppSpacing.xs),
          Padding(
            padding: const EdgeInsets.only(
              left: AppSizes.iconBadge + AppSpacing.md - 4,
            ),
            // Wraps the button under the status at large text sizes.
            child: Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: AppSpacing.sm,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      granted
                          ? Icons.check_circle_rounded
                          : Icons.error_outline,
                      size: AppIconSize.sm,
                      color: color,
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    Text(
                      granted ? grantedLabel : deniedLabel,
                      style: text.labelMedium?.copyWith(color: color),
                    ),
                  ],
                ),
                if (onOpen != null)
                  TextButton(
                    onPressed: onOpen,
                    child: Text(granted ? 'Settings' : 'Allow'),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// E — counts kept on this phone only.
class _StatsGroup extends StatelessWidget {
  final GuardianState state;
  final BudgetSnapshot? snapshot;
  final VoidCallback onReset;

  const _StatsGroup({
    required this.state,
    required this.snapshot,
    required this.onReset,
  });

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    Widget stat(IconData icon, String title, String value) => ListRow(
      icon: icon,
      title: title,
      trailing: Text(value, style: text.titleMedium),
    );
    final opens = [
      for (final app in kGuardianApps)
        if ((state.opens[app.package] ?? 0) > 0)
          (app.label, state.opens[app.package]!),
    ]..sort((a, b) => b.$2.compareTo(a.$2));
    final snap = snapshot;

    return SettingsGroup(
      title: 'Statistics',
      children: [
        stat(
          Icons.notifications_rounded,
          'Alerts shown',
          '${state.alertsShown}',
        ),
        stat(
          Icons.trending_up_rounded,
          'Times budget was exceeded',
          '${state.budgetExceeded}',
        ),
        stat(
          Icons.donut_large_rounded,
          'Budget used this month',
          snap != null && snap.budget > 0 ? '${snap.percent}%' : '—',
        ),
        for (final (label, count) in opens)
          stat(Icons.open_in_new_rounded, '$label opened', '$count'),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            onPressed: onReset,
            child: const Text('Reset statistics'),
          ),
        ),
      ],
    );
  }
}

/// F — plain-language account of what is and isn't collected.
class _PrivacyGroup extends StatelessWidget {
  const _PrivacyGroup();

  static const _points = <(IconData, String, String)>[
    (
      Icons.visibility_outlined,
      'What is detected',
      'Only the name of the app on screen, compared against the UPI apps you '
          'selected. Nothing shown inside any app is read.',
    ),
    (
      Icons.query_stats_rounded,
      'Why Usage access',
      'Android reports which app is in front only to apps with Usage access. '
          'Spendo uses it for this check and nothing else.',
    ),
    (
      Icons.layers_outlined,
      'Why display over apps',
      'So the budget card can appear while the UPI app is open. The card '
          "can't see or touch the app underneath.",
    ),
    (
      Icons.storage_rounded,
      'What is stored',
      'On this phone only: these settings, a copy of this month’s budget '
          'totals, when the last alert appeared, and counts of alerts and app '
          'openings. Nothing is uploaded.',
    ),
    (
      Icons.lock_outline_rounded,
      'What is never accessed',
      'UPI PINs, OTPs, passwords, payment screens, recipients and amounts. '
          'Spendo cannot block, cancel or change a payment.',
    ),
    (
      Icons.power_settings_new_rounded,
      'How to stop',
      'Turn off the switch at the top, tap "Stop monitoring" on its '
          'notification, or remove Usage access in Android settings.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return SettingsGroup(
      title: 'Privacy',
      children: [
        for (final (icon, title, body) in _points)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
            child: ListRow(icon: icon, title: title, subtitle: body),
          ),
      ],
    );
  }
}
