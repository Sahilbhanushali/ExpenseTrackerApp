import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/utils/money.dart';
import '../../core/utils/money_formatter.dart';
import '../../core/widgets/app_card.dart';
import '../../core/widgets/budget_progress_bar.dart';
import '../../core/widgets/staggered_list.dart';
import '../accounts/accounts_controller.dart';
import '../settings/settings_controller.dart';
import 'goals_controller.dart';

class GoalsScreen extends StatelessWidget {
  const GoalsScreen({super.key});

  Future<void> _showAddGoal(BuildContext context) async {
    final nameController = TextEditingController();
    final targetController = TextEditingController();
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('New savings goal'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: const InputDecoration(labelText: 'Goal name'),
            ),
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: targetController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Target amount'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Add'),
          ),
        ],
      ),
    );
    if (result == true && context.mounted) {
      final name = nameController.text.trim();
      final target = parseRupeesToPaise(targetController.text);
      if (name.isEmpty || target == null || target <= 0) return;
      await context.read<GoalsController>().add(name, target);
    }
  }

  Future<void> _showEditGoal(
    BuildContext context,
    int id,
    String name,
    int targetPaise,
  ) async {
    final nameController = TextEditingController(text: name);
    final targetController = TextEditingController(
      text: paiseToEditString(targetPaise),
    );
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit goal'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: const InputDecoration(labelText: 'Goal name'),
            ),
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: targetController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Target amount'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (result != true || !context.mounted) return;
    final newName = nameController.text.trim();
    final newTarget = parseRupeesToPaise(targetController.text);
    if (newName.isEmpty || newTarget == null || newTarget <= 0) return;
    await context.read<GoalsController>().update(
      id,
      name: newName,
      targetPaise: newTarget,
    );
  }

  Future<void> _showContribute(
    BuildContext context,
    int goalId,
    String name,
  ) async {
    final amountController = TextEditingController();
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Add to "$name"'),
        content: TextField(
          controller: amountController,
          keyboardType: TextInputType.number,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Amount'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Add'),
          ),
        ],
      ),
    );
    if (result == true && context.mounted) {
      final amount = parseRupeesToPaise(amountController.text);
      if (amount == null || amount <= 0) return;
      await context.read<GoalsController>().contribute(goalId, amount);
      if (context.mounted) await context.read<AccountsController>().refresh();
    }
  }

  Future<void> _confirmDelete(BuildContext context, int id, String name) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete this goal?'),
        content: Text(
          'Contributions already logged for "$name" stay in your transactions — only the goal tracker is removed.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true && context.mounted) {
      await context.read<GoalsController>().remove(id);
    }
  }

  @override
  Widget build(BuildContext context) {
    final goals = context.watch<GoalsController>();
    final currency = context.watch<SettingsController>().config.currency;

    return Scaffold(
      appBar: AppBar(title: const Text('Savings goals')),
      floatingActionButton: FloatingActionButton(
        heroTag: 'goals_add',
        onPressed: () => _showAddGoal(context),
        child: const Icon(Icons.add),
      ),
      body: goals.goals.isEmpty
          ? const EmptyState(
              icon: Icons.flag_outlined,
              message: 'No savings goals yet.',
            )
          : GridView.builder(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.page,
                AppSpacing.sm,
                AppSpacing.page,
                AppSpacing.navClearance,
              ),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                mainAxisSpacing: AppSpacing.sm,
                crossAxisSpacing: AppSpacing.sm,
                childAspectRatio: 0.92,
              ),
              itemCount: goals.goals.length,
              itemBuilder: (context, i) {
                final g = goals.goals[i];
                return StaggeredListItem(
                  index: i,
                  child: AppCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: () => _showEditGoal(
                            context,
                            g.goal.id!,
                            g.goal.name,
                            g.goal.targetPaise,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                g.goal.name,
                                style: Theme.of(context).textTheme.titleMedium,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              Text(
                                formatMoney(g.saved, currency),
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                              Text(
                                'of ${formatMoney(g.goal.targetPaise, currency)}',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ],
                          ),
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SizedBox(height: AppSpacing.sm),
                            BudgetProgressBar(
                              spent: g.saved,
                              budget: g.goal.targetPaise,
                            ),
                          ],
                        ),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.delete_outline, size: 18),
                              onPressed: () => _confirmDelete(
                                context,
                                g.goal.id!,
                                g.goal.name,
                              ),
                            ),
                            if (g.isComplete)
                              Icon(
                                Icons.check_circle,
                                color: context.palette.income,
                                size: 20,
                              )
                            else
                              FilledButton.tonal(
                                onPressed: () => _showContribute(
                                  context,
                                  g.goal.id!,
                                  g.goal.name,
                                ),
                                style: FilledButton.styleFrom(
                                  minimumSize: const Size(
                                    64,
                                    AppSizes.minTouch - 8,
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: AppSpacing.md,
                                  ),
                                ),
                                child: const Text('Add'),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }
}
