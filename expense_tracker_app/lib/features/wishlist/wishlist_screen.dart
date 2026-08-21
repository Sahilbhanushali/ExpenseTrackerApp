import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/utils/money_formatter.dart';
import '../../core/widgets/animated_money_text.dart';
import '../../core/widgets/app_card.dart';
import '../../core/widgets/budget_progress_bar.dart';
import '../../core/widgets/press_scale.dart';
import '../../core/widgets/staggered_list.dart';
import '../settings/settings_controller.dart';
import 'wishlist_controller.dart';

class WishlistScreen extends StatelessWidget {
  const WishlistScreen({super.key});

  Future<void> _showAddItem(BuildContext context) async {
    final nameController = TextEditingController();
    final priceController = TextEditingController();
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add to wishlist'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: nameController, decoration: const InputDecoration(labelText: 'Item')),
            const SizedBox(height: AppSpacing.md),
            TextField(controller: priceController, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Price')),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Add')),
        ],
      ),
    );
    if (result == true && context.mounted) {
      final name = nameController.text.trim();
      final price = double.tryParse(priceController.text.replaceAll(',', ''));
      if (name.isEmpty || price == null || price <= 0) return;
      await context.read<WishlistController>().add(name, price);
    }
  }

  Future<void> _confirmBuy(BuildContext context, int id, String name) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Mark as bought?'),
        content: Text('This logs $name as an expense.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Bought it')),
        ],
      ),
    );
    if (confirmed == true && context.mounted) {
      await context.read<WishlistController>().buy(id);
    }
  }

  @override
  Widget build(BuildContext context) {
    final wishlist = context.watch<WishlistController>();
    final currency = context.watch<SettingsController>().config.currency;

    return Scaffold(
      appBar: AppBar(title: const Text('Wishlist')),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showAddItem(context),
        child: const Icon(Icons.add),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.md, AppSpacing.lg, 0),
            child: AppCard(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Available savings', style: Theme.of(context).textTheme.bodyMedium),
                  AnimatedMoneyText(
                    amount: wishlist.availableSavings,
                    currency: currency,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(color: AppColors.primary),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: wishlist.items.isEmpty
                ? const EmptyState(icon: Icons.stars_outlined, message: 'Nothing on your wishlist yet.')
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.md, AppSpacing.lg, 96),
                    itemCount: wishlist.items.length,
                    separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.sm),
                    itemBuilder: (context, i) {
                      final item = wishlist.items[i];
                      final available = wishlist.availableSavings.clamp(0, double.infinity).toDouble();
                      return StaggeredListItem(
                        index: i,
                        child: AppCard(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Expanded(
                                    child: Text(item.name, style: Theme.of(context).textTheme.titleMedium),
                                  ),
                                  Text(formatMoney(item.price, currency), style: Theme.of(context).textTheme.titleMedium),
                                ],
                              ),
                              const SizedBox(height: AppSpacing.sm),
                              BudgetProgressBar(spent: available, budget: item.price),
                              const SizedBox(height: AppSpacing.sm),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  PressScale(
                                    onTap: () => context.read<WishlistController>().remove(item.id!),
                                    child: const Padding(
                                      padding: EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 6),
                                      child: Text('Remove'),
                                    ),
                                  ),
                                  const SizedBox(width: AppSpacing.sm),
                                  FilledButton.tonal(
                                    onPressed: () => _confirmBuy(context, item.id!, item.name),
                                    child: const Text('Bought it'),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
