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
      SnackBar(content: Text('Removed: ${row.category} · ${row.note ?? 'no note'}')),
    );
  }

  Future<bool> _confirmDelete(Transaction txn) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete this entry?'),
        content: Text('${txn.category} · ${txn.note ?? 'no note'}'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton.tonal(onPressed: () => Navigator.pop(context, true), child: const Text('Delete')),
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
    final amountController = TextEditingController(text: txn.amount.toStringAsFixed(2));
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit transaction'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: amountController, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Amount')),
            const SizedBox(height: AppSpacing.md),
            TextField(controller: noteController, decoration: const InputDecoration(labelText: 'Note')),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Save')),
        ],
      ),
    );
    if (result != true || txn.id == null || !mounted) return;
    final amount = double.tryParse(amountController.text.replaceAll(',', ''));
    await context.read<ExpensesController>().edit(txn.id!, amount: amount, note: noteController.text.trim());
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

  @override
  Widget build(BuildContext context) {
    final currency = context.watch<SettingsController>().config.currency;
    final rows = _searchResults ?? _allRows;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Transactions'),
        actions: [
          IconButton(icon: const Icon(Icons.undo), tooltip: 'Undo last', onPressed: _undo),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.md, AppSpacing.lg, 0),
            child: TextField(
              controller: _searchController,
              onChanged: _onSearchChanged,
              decoration: const InputDecoration(hintText: 'Search notes or category', prefixIcon: Icon(Icons.search)),
            ),
          ),
          Expanded(
            child: rows == null
                ? const Center(child: CircularProgressIndicator())
                : rows.isEmpty
                    ? const EmptyState(icon: Icons.receipt_long_outlined, message: 'Nothing logged yet.')
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
        items.add(Padding(
          padding: EdgeInsets.fromLTRB(0, items.isEmpty ? 0 : AppSpacing.md, 0, AppSpacing.xs),
          child: Text(
            section,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
        ));
        lastSection = section;
      }

      items.add(StaggeredListItem(
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
          child: TransactionTile(txn: txn, currency: currency, onTap: () => _editTxn(txn)),
        ),
      ));
    }

    return ListView(padding: const EdgeInsets.all(AppSpacing.lg), children: items);
  }
}
