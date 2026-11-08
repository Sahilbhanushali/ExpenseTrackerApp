import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/utils/money.dart';
import '../../core/utils/money_formatter.dart';
import '../../core/widgets/animated_money_text.dart';
import '../../core/widgets/app_card.dart';
import '../../core/widgets/budget_progress_bar.dart';
import '../../core/widgets/press_scale.dart';
import '../../core/widgets/staggered_list.dart';
import '../accounts/accounts_controller.dart';
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
            TextField(
              controller: nameController,
              decoration: const InputDecoration(labelText: 'Item'),
            ),
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: priceController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Price'),
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
      final price = parseRupeesToPaise(priceController.text);
      if (name.isEmpty || price == null || price <= 0) return;
      await context.read<WishlistController>().add(name, price);
    }
  }

  Future<void> _showEditItem(
    BuildContext context,
    int id,
    String name,
    int pricePaise,
  ) async {
    final nameController = TextEditingController(text: name);
    final priceController = TextEditingController(
      text: paiseToEditString(pricePaise),
    );
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit wishlist item'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: const InputDecoration(labelText: 'Item'),
            ),
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: priceController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Price'),
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
    final newPrice = parseRupeesToPaise(priceController.text);
    if (newName.isEmpty || newPrice == null || newPrice <= 0) return;
    await context.read<WishlistController>().update(
      id,
      name: newName,
      pricePaise: newPrice,
    );
  }

  Future<void> _confirmRemove(BuildContext context, int id, String name) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove from wishlist?'),
        content: Text('"$name" will be removed.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed == true && context.mounted) {
      await context.read<WishlistController>().remove(id);
    }
  }

  Future<void> _confirmBuy(BuildContext context, int id, String name) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Mark as bought?'),
        content: Text('This logs $name as an expense.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Bought it'),
          ),
        ],
      ),
    );
    if (confirmed == true && context.mounted) {
      await context.read<WishlistController>().buy(id);
      if (context.mounted) await context.read<AccountsController>().refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    final wishlist = context.watch<WishlistController>();
    final currency = context.watch<SettingsController>().config.currency;

    return Scaffold(
      appBar: AppBar(title: const Text('Wishlist')),
      floatingActionButton: FloatingActionButton(
        heroTag: 'wishlist_add',
        onPressed: () => _showAddItem(context),
        child: const Icon(Icons.add),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.page,
              AppSpacing.sm,
              AppSpacing.page,
              0,
            ),
            child: AppCard(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Available savings',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  AnimatedMoneyText(
                    amountPaise: wishlist.availableSavings,
                    currency: currency,
                    style: Theme.of(context).textTheme.titleMedium
                        ?.copyWith(color: context.palette.savings),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: wishlist.items.isEmpty
                ? const EmptyState(
                    icon: Icons.stars_outlined,
                    message: 'Nothing on your wishlist yet.',
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.page,
                      AppSpacing.sm,
                      AppSpacing.page,
                      AppSpacing.navClearance,
                    ),
                    itemCount: wishlist.items.length,
                    separatorBuilder: (_, _) =>
                        const SizedBox(height: AppSpacing.sm),
                    itemBuilder: (context, i) {
                      final item = wishlist.items[i];
                      final available = wishlist.availableSavings.clamp(
                        0,
                        item.pricePaise,
                      );
                      return StaggeredListItem(
                        index: i,
                        child: AppCard(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              InkWell(
                                borderRadius: BorderRadius.circular(12),
                                onTap: () => _showEditItem(
                                  context,
                                  item.id!,
                                  item.name,
                                  item.pricePaise,
                                ),
                                child: Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Expanded(
                                      child: Text(
                                        item.name,
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleMedium,
                                      ),
                                    ),
                                    Text(
                                      formatMoney(item.pricePaise, currency),
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleMedium,
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: AppSpacing.sm),
                              BudgetProgressBar(
                                spent: available,
                                budget: item.pricePaise,
                              ),
                              const SizedBox(height: AppSpacing.sm),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  PressScale(
                                    onTap: () => _confirmRemove(
                                      context,
                                      item.id!,
                                      item.name,
                                    ),
                                    child: const Padding(
                                      padding: EdgeInsets.symmetric(
                                        horizontal: AppSpacing.sm,
                                        vertical: 6,
                                      ),
                                      child: Text('Remove'),
                                    ),
                                  ),
                                  const SizedBox(width: AppSpacing.sm),
                                  FilledButton.tonal(
                                    onPressed: () => _confirmBuy(
                                      context,
                                      item.id!,
                                      item.name,
                                    ),
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
