import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/finance/salary_cycle.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/utils/money_formatter.dart';
import '../../core/widgets/app_card.dart';
import '../../core/widgets/list_row.dart';
import '../../core/widgets/responsive.dart';
import '../../core/widgets/section_header.dart';
import '../../core/widgets/settings_group.dart';
import '../../data/repositories/cycle_repository.dart';
import '../settings/settings_controller.dart';
import '../../core/widgets/page_transitions.dart';
import 'cycle_card.dart';
import 'cycle_closing_screen.dart';
import 'cycle_controller.dart';
import 'salary_sheets.dart';

class SalaryCyclesScreen extends StatefulWidget {
  const SalaryCyclesScreen({super.key});

  @override
  State<SalaryCyclesScreen> createState() => _SalaryCyclesScreenState();
}

class _SalaryCyclesScreenState extends State<SalaryCyclesScreen> {
  /// Past cycles' totals, newest first; loaded once per change.
  List<CycleSummary> _history = [];
  late final CycleController _cycles;

  @override
  void initState() {
    super.initState();
    _cycles = context.read<CycleController>()..addListener(_loadHistory);
    _loadHistory();
  }

  @override
  void dispose() {
    _cycles.removeListener(_loadHistory);
    super.dispose();
  }

  Future<void> _loadHistory() async {
    final past = _cycles.cycles.reversed.skip(1).toList();
    final summaries = [for (final c in past) await _cycles.summaryFor(c)];
    if (mounted) setState(() => _history = summaries);
  }

  void _snack(String m) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(m)));

  Future<void> _guard(Future<void> Function() action, String done) async {
    try {
      await action();
      _snack(done);
    } on CycleException catch (e) {
      _snack(e.message);
    }
  }

  Future<void> _startWithoutSalary() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: now,
      firstDate: DateTime(now.year - 2),
      lastDate: now,
      helpText: 'Cycle starts on',
    );
    if (picked == null || !mounted) return;
    await _guard(() => _cycles.startCycle(picked), 'Cycle started.');
  }

  Future<void> _cycleActions(CycleRange c) async {
    if (c.record.isClosed) {
      await Navigator.of(context)
          .push(FadeSlideRoute(page: ClosedCycleScreen(cycleId: c.record.id!)));
      return;
    }
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (sheet) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!c.isOpen)
              ListTile(
                leading: const Icon(Icons.task_alt_rounded),
                title: const Text('Close this cycle'),
                subtitle: const Text('Decide what to do with the leftover'),
                onTap: () => Navigator.pop(sheet, 'close'),
              ),
            ListTile(
              leading: const Icon(Icons.edit_calendar_rounded),
              title: const Text('Change start date'),
              subtitle: const Text('Also moves the previous cycle’s end'),
              onTap: () => Navigator.pop(sheet, 'move'),
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline_rounded),
              title: const Text('Remove this cycle'),
              subtitle: const Text(
                'The previous cycle runs on; the salary entry stays',
              ),
              onTap: () => Navigator.pop(sheet, 'remove'),
            ),
          ],
        ),
      ),
    );
    if (!mounted || action == null) return;
    if (action == 'close') {
      await Navigator.of(
        context,
      ).push(FadeSlideRoute(page: CycleClosingScreen(cycleId: c.record.id!)));
      return;
    }
    if (action == 'move') {
      final now = DateTime.now();
      final picked = await showDatePicker(
        context: context,
        initialDate: c.start,
        firstDate: DateTime(now.year - 2),
        lastDate: now,
        helpText: 'New start date',
      );
      if (picked == null || !mounted) return;
      await _guard(
        () => _cycles.moveStart(c.record.id!, picked),
        'Start date changed.',
      );
    } else {
      final ok = await showDialog<bool>(
        context: context,
        builder: (d) => AlertDialog(
          title: const Text('Remove this cycle?'),
          content: Text(
            'The cycle starting ${shortDate(c.start)} is merged into the one '
            'before it. Your transactions, including the salary, are kept.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(d, false),
              child: const Text('Cancel'),
            ),
            FilledButton.tonal(
              onPressed: () => Navigator.pop(d, true),
              child: const Text('Remove'),
            ),
          ],
        ),
      );
      if (ok == true) {
        await _guard(() => _cycles.remove(c.record.id!), 'Cycle removed.');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cycles = context.watch<CycleController>();
    final currency = context.select<SettingsController, String>(
      (s) => s.config.currency,
    );
    final current = cycles.current;
    final profile = cycles.profile;
    final text = Theme.of(context).textTheme;
    String money(int? p) => p == null ? 'Not set' : formatMoney(p, currency);

    return Scaffold(
      appBar: AppBar(title: const Text('Salary & cycles')),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'record_salary',
        onPressed: () => showRecordSalarySheet(context),
        icon: const Icon(Icons.payments_rounded),
        label: const Text('Record salary'),
      ),
      body: ResponsivePage(
        builder: (context, gutter) => ListView(
          padding: EdgeInsets.fromLTRB(
            gutter,
            AppSpacing.sm,
            gutter,
            AppSpacing.navClearance,
          ),
          children: [
            for (final c in cycles.needsClosing)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.md),
                child: CloseCyclePrompt(cycle: c),
              ),
            if (current == null)
              AppCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('No salary cycle yet', style: text.titleMedium),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      'Record the salary you last received. Its date starts '
                      'your first cycle, which runs until the next salary.',
                      style: text.bodyMedium,
                    ),
                    const SizedBox(height: AppSpacing.md),
                    FilledButton(
                      onPressed: () => showRecordSalarySheet(context),
                      child: const Text('Record salary received'),
                    ),
                    TextButton(
                      onPressed: _startWithoutSalary,
                      child: const Text('Start a cycle without a salary'),
                    ),
                  ],
                ),
              )
            else
              GestureDetector(
                onLongPress: () => _cycleActions(current.cycle),
                child: CycleCard(summary: current, currency: currency),
              ),
            const SizedBox(height: AppSpacing.lg),
            SettingsGroup(
              title: 'Salary details',
              children: [
                ListRow(
                  icon: Icons.payments_outlined,
                  title: 'Expected take-home',
                  subtitle: 'Per month · expected, not received',
                  trailing: Text(
                    money(profile.expectedNetPaise),
                    style: text.titleSmall,
                  ),
                ),
                ListRow(
                  icon: Icons.receipt_long_outlined,
                  title: 'Gross per month',
                  trailing: Text(
                    money(profile.grossMonthlyPaise),
                    style: text.titleSmall,
                  ),
                ),
                ListRow(
                  icon: Icons.work_outline_rounded,
                  title: 'CTC per year',
                  subtitle: 'Not spendable income',
                  trailing: Text(
                    money(profile.ctcAnnualPaise),
                    style: text.titleSmall,
                  ),
                ),
                ListRow(
                  icon: Icons.event_rounded,
                  title: 'Usually arrives',
                  subtitle: profile.account == null
                      ? null
                      : 'Into ${profile.account}',
                  trailing: Text(
                    'Day ${profile.dayFrom}–${profile.dayTo}',
                    style: text.titleSmall,
                  ),
                ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                    onPressed: () => showSalaryProfileSheet(context),
                    child: const Text('Edit salary details'),
                  ),
                ),
              ],
            ),
            if (current != null)
              SectionHeader(
                'Cycles',
                action: 'Start without salary',
                onAction: _startWithoutSalary,
              ),
            if (current != null)
              _CycleRow(
                summary: current,
                currency: currency,
                onTap: () => _cycleActions(current.cycle),
              ),
            for (final s in _history)
              _CycleRow(
                summary: s,
                currency: currency,
                onTap: () => _cycleActions(s.cycle),
              ),
          ],
        ),
      ),
    );
  }
}

class _CycleRow extends StatelessWidget {
  final CycleSummary summary;
  final String currency;
  final VoidCallback onTap;
  const _CycleRow({
    required this.summary,
    required this.currency,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final text = Theme.of(context).textTheme;
    final c = summary.cycle;
    final left = summary.leftFromIncome;
    final status = c.record.isClosed
        ? 'Closed'
        : c.isOpen
        ? 'Current'
        : 'Ended';
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: AppCard(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(child: Text(cycleLabel(c), style: text.titleSmall)),
                Text(status, style: text.labelMedium),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.md,
              runSpacing: AppSpacing.xs,
              children: [
                Text(
                  'Income ${formatMoney(summary.income.total, currency)}',
                  style: text.bodySmall,
                ),
                Text(
                  'Spent ${formatMoney(summary.spent, currency)}',
                  style: text.bodySmall,
                ),
                Text(
                  left >= 0
                      ? 'Left ${formatMoney(left, currency)}'
                      : 'Short ${formatMoney(-left, currency)}',
                  style: text.bodySmall?.copyWith(
                    color: left >= 0 ? p.income : p.expense,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
