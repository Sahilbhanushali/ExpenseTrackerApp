import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/constants/calendar.dart';
import '../../core/finance/calendar_events.dart';
import '../../core/finance/salary_cycle.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/money_formatter.dart';
import '../../core/widgets/app_card.dart';
import '../../core/widgets/category_icon.dart';
import '../../core/widgets/form_sheet.dart';
import '../../core/widgets/page_transitions.dart';
import '../../core/widgets/responsive.dart';
import '../../core/widgets/section_header.dart';
import '../cycles/cycle_card.dart';
import '../settings/settings_controller.dart';
import 'calendar_controller.dart';

IconData eventIcon(EventKind k) => switch (k) {
  EventKind.salary => Icons.payments_rounded,
  EventKind.income => Icons.south_west_rounded,
  EventKind.emi => Icons.account_balance_rounded,
  EventKind.cardDue => Icons.credit_card_rounded,
  EventKind.statement => Icons.receipt_long_rounded,
  EventKind.bill => Icons.event_repeat_rounded,
  EventKind.billIncome => Icons.savings_outlined,
  EventKind.transfer => Icons.swap_horiz_rounded,
};

Color eventColor(FinEvent e, AppPalette p, DateTime today) {
  if (e.overdue(today)) return p.expense;
  return switch (e.flow) {
    MoneyFlow.outgoing => p.warning,
    MoneyFlow.incoming => p.income,
    MoneyFlow.info => p.savings,
  };
}

String dayLabel(DateTime d, DateTime today) {
  final diff = dateOnly(d).difference(dateOnly(today)).inDays;
  if (diff == 0) return 'Today';
  if (diff == 1) return 'Tomorrow';
  return '${kWeekdayNames[d.weekday - 1].substring(0, 3)}, ${shortDate(d)}';
}

class CalendarScreen extends StatefulWidget {
  const CalendarScreen({super.key});

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  int _days = 15;

  Future<void> _reminders(BuildContext context) async {
    final settings = context.read<SettingsController>();
    var on = settings.config.remindersOn;
    var days = settings.config.reminderDaysBefore;
    final ok = await showFormSheet(
      context,
      title: const Text('Reminders'),
      subtitle:
          'One reminder per EMI, card due, statement day, expected income and '
          'salary. Recurring bills keep their own reminder.',
      submitLabel: 'Save',
      builder: (context, setState) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: on,
            onChanged: (v) => setState(() => on = v),
            title: const Text('Remind me'),
          ),
          if (on)
            SegmentedButton<int>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: 0, label: Text('On the day')),
                ButtonSegment(value: 1, label: Text('1 day')),
                ButtonSegment(value: 3, label: Text('3 days')),
                ButtonSegment(value: 7, label: Text('A week')),
              ],
              selected: {days},
              onSelectionChanged: (s) => setState(() => days = s.first),
            ),
        ],
      ),
    );
    if (!ok || !context.mounted) return;
    await settings.setReminders(on: on, daysBefore: days);
  }

  @override
  Widget build(BuildContext context) {
    final calendar = context.watch<CalendarController>();
    final currency = context.select<SettingsController, String>(
      (s) => s.config.currency,
    );
    final text = Theme.of(context).textTheme;
    final p = context.palette;
    final today = dateOnly(DateTime.now());
    final events = calendar.upcoming(_days);
    final overdue = events.where((e) => e.overdue(today)).toList();
    final ahead = events.where((e) => !e.overdue(today)).toList();
    final totals = windowTotals(events);
    final byDay = <DateTime, List<FinEvent>>{};
    for (final e in ahead) {
      (byDay[dateOnly(e.date)] ??= []).add(e);
    }
    String fmt(int v) => formatMoney(v, currency);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Financial calendar'),
        actions: [
          IconButton(
            tooltip: 'Reminders',
            icon: const Icon(Icons.notifications_active_outlined),
            onPressed: () => _reminders(context),
          ),
        ],
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
            SegmentedButton<int>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: 7, label: Text('7 days')),
                ButtonSegment(value: 15, label: Text('15 days')),
                ButtonSegment(value: 30, label: Text('30 days')),
              ],
              selected: {_days},
              onSelectionChanged: (s) => setState(() => _days = s.first),
            ),
            const SizedBox(height: AppSpacing.md),
            AppCard(
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Due to pay', style: text.labelMedium),
                        Text(
                          fmt(totals.outgoing),
                          style: text.moneyStyle(20, color: p.expense),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text('Expected in', style: text.labelMedium),
                        Text(
                          fmt(totals.incoming),
                          style: text.moneyStyle(20, color: p.income),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            if (overdue.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.lg),
              const SectionHeader('Overdue'),
              for (final e in overdue)
                _EventRow(event: e, currency: currency, today: today),
            ],
            if (events.isEmpty) ...[
              const SizedBox(height: AppSpacing.lg),
              const AppCard(
                child: EmptyState(
                  icon: Icons.event_available_rounded,
                  title: 'Nothing coming up',
                  message:
                      'Salary, EMIs, card dues, statements, bills and expected '
                      'income show up here once you add them.',
                ),
              ),
            ],
            for (final MapEntry(key: day, value: list) in byDay.entries) ...[
              const SizedBox(height: AppSpacing.lg),
              SectionHeader(dayLabel(day, today)),
              for (final e in list)
                _EventRow(event: e, currency: currency, today: today),
            ],
          ],
        ),
      ),
    );
  }
}

class _EventRow extends StatelessWidget {
  final FinEvent event;
  final String currency;
  final DateTime today;
  const _EventRow({
    required this.event,
    required this.currency,
    required this.today,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final text = Theme.of(context).textTheme;
    final color = eventColor(event, p, today);
    final e = event;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
      child: AppCard(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CategoryIcon(
              category: e.kind.name,
              icon: eventIcon(e.kind),
              color: color,
              size: 36,
            ),
            const SizedBox(width: AppSpacing.md - 4),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(e.title, style: text.titleSmall),
                  Text(
                    e.overdue(today)
                        ? '${eventKindLabel(e.kind)} · was due ${shortDate(e.date)}'
                        : eventKindLabel(e.kind),
                    style: text.bodySmall?.copyWith(
                      color: e.overdue(today) ? p.expense : null,
                    ),
                  ),
                  if (e.detail != null) Text(e.detail!, style: text.bodySmall),
                ],
              ),
            ),
            if (e.amount != null)
              Text(
                '${e.flow == MoneyFlow.incoming ? '+' : ''}${formatMoney(e.amount!, currency)}',
                style: text.moneyStyle(
                  14,
                  color: e.flow == MoneyFlow.incoming ? p.income : null,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Home / cycle view: the next seven days in a few lines.
class ComingUp extends StatelessWidget {
  const ComingUp({super.key});

  @override
  Widget build(BuildContext context) {
    final calendar = context.watch<CalendarController?>();
    if (calendar == null) return const SizedBox.shrink();
    final currency = context.select<SettingsController, String>(
      (s) => s.config.currency,
    );
    final today = dateOnly(DateTime.now());
    final events = calendar.upcoming(7);
    if (events.isEmpty) return const SizedBox.shrink();
    final totals = windowTotals(events);
    final text = Theme.of(context).textTheme;
    final p = context.palette;
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionHeader(
            'Coming up this week',
            action: 'Calendar',
            onAction: () =>
                Navigator.of(context)
                    .push(FadeSlideRoute(page: const CalendarScreen())),
          ),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final e in events.take(4))
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      vertical: AppSpacing.xxs + 1,
                    ),
                    child: Row(
                      children: [
                        Icon(
                          eventIcon(e.kind),
                          size: AppIconSize.md,
                          color: eventColor(e, p, today),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(
                          child: Text(
                            '${e.title} · ${e.overdue(today) ? 'overdue' : dayLabel(e.date, today)}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: text.bodyMedium,
                          ),
                        ),
                        if (e.amount != null)
                          Text(
                            formatMoneyCompact(e.amount!, currency),
                            style: text.moneyStyle(14),
                          ),
                      ],
                    ),
                  ),
                if (events.length > 4)
                  Text('+${events.length - 4} more', style: text.bodySmall),
                if (totals.outgoing > 0) ...[
                  const Divider(),
                  Text(
                    '${formatMoney(totals.outgoing, currency)} due in the next 7 days',
                    style: text.labelMedium,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
