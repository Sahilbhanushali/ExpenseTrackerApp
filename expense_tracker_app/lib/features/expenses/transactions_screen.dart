import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/widgets/app_card.dart';
import '../../core/widgets/staggered_list.dart';
import '../../core/widgets/transaction_tile.dart';
import '../../data/models/transaction.dart';
import '../settings/settings_controller.dart';
import 'expenses_controller.dart';

class TransactionsScreen extends StatefulWidget {
  const TransactionsScreen({super.key});

  @override
  State<TransactionsScreen> createState() => _TransactionsScreenState();
}

class _TransactionsScreenState extends State<TransactionsScreen> {
  final _searchController = TextEditingController();
  List<Transaction>? _allRows;
  List<Transaction>? _searchResults;
  TxnType? _typeFilter;
  String? _categoryFilter;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final rows = await context.read<ExpensesController>().allRows();
    if (mounted) setState(() => _allRows = rows.reversed.toList());
  }

  Future<void> _onSearchChanged(String term) async {
    if (term.trim().isEmpty) {
      setState(() => _searchResults = null);
      return;
    }
    final results = await context.read<ExpensesController>().search(term);
    if (mounted) setState(() => _searchResults = results.reversed.toList());
  }

  Future<void> _undo() async {
    final expenses = context.read<ExpensesController>();
    final row = await expenses.undoLast();
    await _load();
    if (!mounted || row == null) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Removed: ${row.category} · ${row.note ?? 'no note'}'),
      ),
    );
  }

  Future<bool> _confirmDelete(Transaction txn) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete this entry?'),
        content: Text('${txn.category} · ${txn.note ?? 'no note'}'),
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
    return confirmed == true;
  }

  Future<void> _deleteTxn(Transaction txn) async {
    HapticFeedback.mediumImpact();
    await context.read<ExpensesController>().deleteById(txn.id!);
    await _load();
  }

  Future<void> _editTxn(Transaction txn) async {
    final noteController = TextEditingController(text: txn.note ?? '');
    final amountController = TextEditingController(
      text: txn.amount.toStringAsFixed(2),
    );
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit transaction'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: amountController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Amount'),
            ),
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: noteController,
              decoration: const InputDecoration(labelText: 'Note'),
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
    if (result != true || txn.id == null || !mounted) return;
    final amount = double.tryParse(amountController.text.replaceAll(',', ''));
    await context.read<ExpensesController>().edit(
      txn.id!,
      amount: amount,
      note: noteController.text.trim(),
    );
    await _load();
  }

  String _sectionLabel(String isoDate) {
    final today = DateTime.now();
    final todayIso =
        '${today.year.toString().padLeft(4, '0')}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';
    final yesterday = today.subtract(const Duration(days: 1));
    final yesterdayIso =
        '${yesterday.year.toString().padLeft(4, '0')}-${yesterday.month.toString().padLeft(2, '0')}-${yesterday.day.toString().padLeft(2, '0')}';
    if (isoDate == todayIso) return 'Today';
    if (isoDate == yesterdayIso) return 'Yesterday';
    return isoDate;
  }

  List<Transaction> _applyFilters(List<Transaction> rows) {
    return rows.where((t) {
      if (_typeFilter != null && t.type != _typeFilter) return false;
      if (_categoryFilter != null && t.category != _categoryFilter) {
        return false;
      }
      return true;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final currency = context.watch<SettingsController>().config.currency;
    final baseRows = _searchResults ?? _allRows;
    final rows = baseRows == null ? null : _applyFilters(baseRows);
    final categories = (_allRows ?? []).map((t) => t.category).toSet().toList()
      ..sort();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Transactions'),
        actions: [
          IconButton(
            icon: const Icon(Icons.undo),
            tooltip: 'Undo last',
            onPressed: _undo,
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.md,
              AppSpacing.lg,
              0,
            ),
            child: TextField(
              controller: _searchController,
              onChanged: _onSearchChanged,
              decoration: const InputDecoration(
                hintText: 'Search notes or category',
                prefixIcon: Icon(Icons.search),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.sm,
              AppSpacing.lg,
              0,
            ),
            child: SizedBox(
              height: 36,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  _FilterChip(
                    label: 'All',
                    selected: _typeFilter == null,
                    onTap: () => setState(() => _typeFilter = null),
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  _FilterChip(
                    label: 'Expense',
                    selected: _typeFilter == TxnType.expense,
                    onTap: () => setState(() => _typeFilter = TxnType.expense),
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  _FilterChip(
                    label: 'Income',
                    selected: _typeFilter == TxnType.income,
                    onTap: () => setState(() => _typeFilter = TxnType.income),
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  _FilterChip(
                    label: 'Lent',
                    selected: _typeFilter == TxnType.lent,
                    onTap: () => setState(() => _typeFilter = TxnType.lent),
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  _FilterChip(
                    label: 'Borrowed',
                    selected: _typeFilter == TxnType.borrowed,
                    onTap: () => setState(() => _typeFilter = TxnType.borrowed),
                  ),
                  if (categories.isNotEmpty) ...[
                    const SizedBox(width: AppSpacing.md),
                    Container(width: 1, color: Theme.of(context).dividerColor),
                    const SizedBox(width: AppSpacing.md),
                    for (final c in categories) ...[
                      _FilterChip(
                        label: c,
                        selected: _categoryFilter == c,
                        onTap: () => setState(
                          () =>
                              _categoryFilter = _categoryFilter == c ? null : c,
                        ),
                      ),
                      const SizedBox(width: AppSpacing.xs),
                    ],
                  ],
                ],
              ),
            ),
          ),
          Expanded(
            child: rows == null
                ? const Center(child: CircularProgressIndicator())
                : rows.isEmpty
                ? EmptyState(
                    icon: Icons.receipt_long_outlined,
                    message: (baseRows?.isEmpty ?? true)
                        ? 'Nothing logged yet.'
                        : 'No transactions match these filters.',
                  )
                : _buildGroupedList(rows, currency),
          ),
        ],
      ),
    );
  }

  Widget _buildGroupedList(List<Transaction> rows, String currency) {
    final items = <Widget>[];
    String? lastSection;
    var index = 0;

    for (final txn in rows) {
      final section = _sectionLabel(txn.date);
      if (section != lastSection) {
        items.add(
          Padding(
            padding: EdgeInsets.fromLTRB(
              0,
              items.isEmpty ? 0 : AppSpacing.md,
              0,
              AppSpacing.xs,
            ),
            child: Text(
              section,
              style: Theme.of(context).textTheme.labelMedium
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
        );
        lastSection = section;
      }

      items.add(
        StaggeredListItem(
          index: index++,
          child: Dismissible(
            key: ValueKey(txn.id),
            direction: DismissDirection.endToStart,
            confirmDismiss: (_) => _confirmDelete(txn),
            onDismissed: (_) => _deleteTxn(txn),
            background: Container(
              alignment: Alignment.centerRight,
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
              decoration: BoxDecoration(
                color: AppColors.expense.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(AppRadius.md),
              ),
              child: const Icon(Icons.delete_outline, color: AppColors.expense),
            ),
            child: TransactionTile(
              txn: txn,
              currency: currency,
              onTap: () => _editTxn(txn),
            ),
          ),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      children: items,
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      borderRadius: BorderRadius.circular(AppRadius.pill),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: 6,
        ),
        decoration: BoxDecoration(
          color: selected ? AppColors.primary : theme.cardTheme.color,
          borderRadius: BorderRadius.circular(AppRadius.pill),
          border: Border.all(
            color: selected ? AppColors.primary : theme.dividerColor,
          ),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: theme.textTheme.bodySmall?.copyWith(
            color: selected ? Colors.white : null,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}
