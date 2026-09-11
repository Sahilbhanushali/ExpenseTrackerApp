import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/constants/categories.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/utils/money.dart';
import '../../core/utils/money_formatter.dart';
import '../../core/widgets/app_card.dart';
import 'settings_controller.dart';

/// Splits the monthly budget across categories, and keeps it always fully
/// allocated: dragging one category's slider takes the difference from (or
/// gives it back to) the others, proportionally to their current share —
/// envelope-style budgeting instead of independent per-category caps that
/// can silently add up to more than the total.
class BudgetPlannerScreen extends StatefulWidget {
  const BudgetPlannerScreen({super.key});

  @override
  State<BudgetPlannerScreen> createState() => _BudgetPlannerScreenState();
}

class _BudgetPlannerScreenState extends State<BudgetPlannerScreen> {
  /// Both in paise.
  late int _total;
  late Map<String, int> _allocations;
  /// The budget the current allocations were seeded from. Re-seeding only
  /// when it changes keeps the user's slider edits while still following a
  /// budget changed in Settings.
  int? _seededFor;

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsController>();
    final config = settings.config;

    if (_seededFor != config.monthlyBudgetPaise) {
      _total = config.monthlyBudgetPaise;
      _allocations = _seedAllocations(config.budgets, _total);
      _seededFor = _total;
    }

    final allocatedSum = _allocations.values.fold<int>(0, (s, v) => s + v);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Budget planner'),
        actions: [
          TextButton(
            onPressed: _total > 0 ? _applyRecommended : null,
            child: const Text('Recommend'),
          ),
        ],
      ),
      body: _total <= 0
          ? const _NoBudgetState()
          : ListView(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.md,
                AppSpacing.lg,
                96,
              ),
              children: [
                AppCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Monthly budget',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      Text(
                        formatMoney(_total, config.currency),
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        'Fully allocated — ${formatMoney(allocatedSum, config.currency)} across categories',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                ..._allocations.keys.map(
                  (cat) => _CategoryAllocator(
                    category: cat,
                    value: _allocations[cat]!,
                    total: _total,
                    currency: config.currency,
                    color: AppColors.categoryColor(cat),
                    onChanged: (v) => setState(() => _rebalance(cat, v)),
                  ),
                ),
              ],
            ),
      bottomNavigationBar: _total <= 0
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: ElevatedButton(
                  onPressed: () {
                    settings.setBudgets(_allocations);
                    HapticFeedback.mediumImpact();
                    Navigator.of(context).pop();
                  },
                  child: const Text('Save split'),
                ),
              ),
            ),
    );
  }

  /// Seeds every known category with its existing budget, or 0 if unset,
  /// then scales the whole set so it sums exactly to `total`. If nothing was
  /// ever set, seeds from the recommended split instead of all-zero.
  Map<String, int> _seedAllocations(Map<String, int> existing, int total) {
    final categories = [...kCategoryKeywords.keys];
    final hasAny = categories.any((c) => (existing[c] ?? 0) > 0);
    if (!hasAny) return _recommendedSplit(total);

    final raw = {for (final c in categories) c: existing[c] ?? 0};
    return _scaleToTotal(raw, total);
  }

  Map<String, int> _recommendedSplit(int total) {
    return {
      for (final entry in kRecommendedAllocation.entries)
        entry.key: (total * entry.value.$2).round(),
    };
  }

  Map<String, int> _scaleToTotal(Map<String, int> raw, int total) {
    final sum = raw.values.fold<int>(0, (s, v) => s + v);
    if (sum <= 0) return _recommendedSplit(total);
    final factor = total / sum;
    return raw.map((k, v) => MapEntry(k, (v * factor).round()));
  }

  void _applyRecommended() {
    setState(() => _allocations = _recommendedSplit(_total));
    HapticFeedback.selectionClick();
  }

  void _rebalance(String category, int newValue) {
    newValue = newValue.clamp(0, _total);
    final oldValue = _allocations[category]!;
    final delta = newValue - oldValue;
    if (delta == 0) return;

    final others = _allocations.keys.where((k) => k != category).toList();
    final othersSum = others.fold<int>(0, (s, k) => s + _allocations[k]!);

    if (delta > 0) {
      final take = delta.clamp(0, othersSum);
      if (othersSum > 0) {
        for (final k in others) {
          final share = _allocations[k]! / othersSum;
          _allocations[k] = (_allocations[k]! - take * share).round().clamp(
            0,
            _total,
          );
        }
      }
      _allocations[category] = oldValue + take;
    } else {
      final give = -delta;
      if (othersSum > 0) {
        for (final k in others) {
          final share = _allocations[k]! / othersSum;
          _allocations[k] = _allocations[k]! + (give * share).round();
        }
      } else if (others.isNotEmpty) {
        for (final k in others) {
          _allocations[k] = give ~/ others.length;
        }
      }
      _allocations[category] = newValue;
    }
    // Rounding can drift the sum off `_total`; park the remainder on the
    // category the user is actually dragging.
    final drift = _total - _allocations.values.fold<int>(0, (s, v) => s + v);
    _allocations[category] = (_allocations[category]! + drift).clamp(0, _total);
  }
}

class _CategoryAllocator extends StatelessWidget {
  final String category;

  /// Both in paise.
  final int value;
  final int total;
  final String currency;
  final Color color;
  final ValueChanged<int> onChanged;

  const _CategoryAllocator({
    required this.category,
    required this.value,
    required this.total,
    required this.currency,
    required this.color,
    required this.onChanged,
  });

  Future<void> _editExact(BuildContext context) async {
    final controller = TextEditingController(text: paiseToEditString(value));
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(category),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Set'),
          ),
        ],
      ),
    );
    if (result == true) {
      final v = parseRupeesToPaise(controller.text);
      if (v != null && v >= 0) onChanged(v);
    }
  }

  @override
  Widget build(BuildContext context) {
    final pct = total > 0 ? (value / total * 100).round() : 0;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: color,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Text(
                      category,
                      style: Theme.of(context).textTheme.bodyLarge
                          ?.copyWith(fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => _editExact(context),
                  child: Row(
                    children: [
                      Text(
                        formatMoney(value, currency),
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '· $pct%',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            SliderTheme(
              data: SliderTheme.of(context).copyWith(
                activeTrackColor: color,
                thumbColor: color,
                overlayColor: color.withValues(alpha: 0.15),
              ),
              child: Slider(
                value: value.clamp(0, total).toDouble(),
                min: 0,
                max: total.toDouble(),
                onChanged: (v) => onChanged(v.round()),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NoBudgetState extends StatelessWidget {
  const _NoBudgetState();

  @override
  Widget build(BuildContext context) {
    return const EmptyState(
      icon: Icons.pie_chart_outline,
      message: 'Set a monthly budget in Settings first, then come back here to split it across categories.',
    );
  }
}
