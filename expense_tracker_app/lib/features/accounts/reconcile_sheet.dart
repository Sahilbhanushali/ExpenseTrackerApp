import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/money.dart';
import '../../core/utils/money_formatter.dart';
import '../../core/widgets/form_sheet.dart';
import '../cycles/cycle_card.dart';

/// What the user decided in [showReconcileSheet].
class ReconcileInput {
  final DateTime asOf;
  final int actualPaise;
  final bool adjust;
  final String? note;
  const ReconcileInput(this.asOf, this.actualPaise, this.adjust, this.note);
}

/// Compare the app's figure with the bank's.
///
/// [appFigureOn] gives the app's balance (or, for a card, what's owed) for
/// a date. [datePicker] is false for cards, which are checked as of today.
Future<ReconcileInput?> showReconcileSheet(
  BuildContext context, {
  required String title,
  required String actualLabel,
  required String currency,
  required Future<int> Function(DateTime date) appFigureOn,
  bool datePicker = true,
}) async {
  var asOf = DateTime.now();
  var app = await appFigureOn(asOf);
  if (!context.mounted) return null;
  final actual = TextEditingController();
  final note = TextEditingController();
  var adjust = false;

  final ok = await showFormSheet(
    context,
    title: Text(title),
    subtitle:
        'Enter what your bank shows. If it differs, look for a missing or '
        'wrong entry first; record an adjustment only for what’s left.',
    submitLabel: 'Save check',
    validate: () => parseRupeesToPaise(actual.text) == null
        ? 'Enter the bank’s figure.'
        : null,
    builder: (context, setState) {
      final p = context.palette;
      final text = Theme.of(context).textTheme;
      final entered = parseRupeesToPaise(actual.text);
      final diff = entered == null ? null : entered - app;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (datePicker)
            OutlinedButton.icon(
              onPressed: () async {
                final now = DateTime.now();
                final d = await showDatePicker(
                  context: context,
                  initialDate: asOf,
                  firstDate: DateTime(now.year - 2),
                  lastDate: now,
                  helpText: 'Balance as of',
                );
                if (d == null) return;
                final v = await appFigureOn(d);
                setState(() {
                  asOf = d;
                  app = v;
                });
              },
              icon: const Icon(Icons.event_rounded),
              label: Text('As of ${shortDate(asOf)}'),
            ),
          const SizedBox(height: AppSpacing.md - 4),
          Row(
            children: [
              Expanded(child: Text('In the app', style: text.bodyMedium)),
              Text(formatMoney(app, currency), style: text.moneyStyle(16)),
            ],
          ),
          const SizedBox(height: AppSpacing.md - 4),
          TextField(
            controller: actual,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(
              decimal: true,
              signed: true,
            ),
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              labelText: actualLabel,
              prefixText: '$currency ',
            ),
          ),
          if (diff != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                Icon(
                  diff == 0 ? Icons.check_circle_rounded : Icons.error_outline,
                  size: AppIconSize.sm,
                  color: diff == 0 ? p.income : p.warning,
                ),
                const SizedBox(width: AppSpacing.xs),
                Expanded(
                  child: Text(
                    diff == 0
                        ? 'Matches the bank.'
                        : 'The bank shows ${formatMoney(diff.abs(), currency)} '
                              '${diff > 0 ? 'more' : 'less'} than the app.',
                    style: text.bodyMedium?.copyWith(
                      color: diff == 0 ? p.income : p.warning,
                    ),
                  ),
                ),
              ],
            ),
            if (diff != 0) ...[
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: adjust,
                onChanged: (v) => setState(() => adjust = v),
                title: const Text('Record an adjustment'),
                subtitle: const Text(
                  'Brings the app in line. It’s labelled as an adjustment and '
                  'never counted as income or spending.',
                ),
              ),
              TextField(
                controller: note,
                decoration: const InputDecoration(
                  labelText: 'Note (optional)',
                  hintText: 'e.g. bank charges I couldn’t trace',
                ),
              ),
            ],
          ],
        ],
      );
    },
  );
  if (!ok) return null;
  return ReconcileInput(
    asOf,
    parseRupeesToPaise(actual.text)!,
    adjust,
    note.text.trim().isEmpty ? null : note.text.trim(),
  );
}
