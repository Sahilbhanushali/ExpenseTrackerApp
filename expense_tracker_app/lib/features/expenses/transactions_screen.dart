import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/utils/money.dart';
import '../../core/widgets/app_card.dart';
import '../../core/widgets/staggered_list.dart';
import '../../core/widgets/transaction_tile.dart';
import '../../data/models/transaction.dart';
import '../accounts/accounts_controller.dart';
import '../settings/settings_controller.dart';
import 'expenses_controller.dart';

const _pageSize = 50;

class TransactionsScreen extends StatefulWidget {
  const TransactionsScreen({super.key});

  @override
  State<TransactionsScreen> createState() => _TransactionsScreenState();
}

class _TransactionsScreenState extends State<TransactionsScreen> {
  final _searchController = TextEditingController();
  final _scrollController = ScrollController();
  Timer? _searchDebounce;

  List<Transaction> _rows = [];
  List<String> _categories = [];
  bool _initialLoad = true;
  bool _loadingMore = false;
  bool _hasMore = true;
  int _offset = 0;

  TxnType? _typeFilter;
  String? _categoryFilter;
  DateTimeRange? _dateFilter;

  late final ExpensesController _expenses;

  @override
  void initState() {
    super.initState();
    _expenses = context.read<ExpensesController>();
    // IndexedStack keeps this screen mounted for the whole app lifetime, so
    // it never gets a fresh initState when the user switches back to this
    // tab — without this listener, a transaction added from the Dashboard
    // (or anywhere else) would never show up here until some unrelated
    // local action happened to trigger a reload.
    _expenses.addListener(_reload);
    _scrollController.addListener(_onScroll);
    _loadCategories();
    _reload();
  }

  @override
  void dispose() {
    _expenses.removeListener(_reload);
    _searchDebounce?.cancel();
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadCategories() async {
    final categories = await _expenses.distinctCategories();
    if (mounted) setState(() => _categories = categories);
  }

  void _onScroll() {
    if (_scrollController.position.pixels >
        _scrollController.position.maxScrollExtent - 400) {
      _loadMore();
    }
  }

  Future<void> _reload() async {
    setState(() {
      _rows = [];
      _offset = 0;
      _hasMore = true;
      _initialLoad = true;
    });
    await _loadMore();
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore) return;
    setState(() => _loadingMore = true);
    final page = await _expenses.queryPage(
      limit: _pageSize,
      offset: _offset,
      type: _typeFilter,
      category: _categoryFilter,
      from: _dateFilter?.start,
      to: _dateFilter?.end,
      searchTerm: _searchController.text,
    );
    if (!mounted) return;
    setState(() {
      _rows = [..._rows, ...page];
      _offset += page.length;
      _hasMore = page.length == _pageSize;
      _loadingMore = false;
      _initialLoad = false;
    });
  }

  void _onSearchChanged(String term) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 300), _reload);
  }

  Future<void> _undo() async {
    // No explicit _reload() here — deleting via ExpensesController already
    // calls its own refresh(), which the listener registered in initState
    // picks up automatically.
    final row = await _expenses.undoLast();
    if (!mounted) return;
    await context.read<AccountsController>().refresh();
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
    await _expenses.deleteById(txn.id!);
    if (mounted) await context.read<AccountsController>().refresh();
  }

  Future<void> _editTxn(Transaction txn) async {
    final currency = context.read<SettingsController>().config.currency;
    await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (context) => _TransactionDetailSheet(
        txn: txn,
        currency: currency,
        categories: _categories,
        onDelete: () async {
          Navigator.pop(context);
          if (await _confirmDelete(txn) && mounted) await _deleteTxn(txn);
        },
      ),
    );
    if (mounted) await context.read<AccountsController>().refresh();
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

  Future<void> _pickDateRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 5),
      lastDate: now,
      initialDateRange: _dateFilter,
    );
    if (picked != null) {
      setState(
        () => _dateFilter = DateTimeRange(
          start: DateTime(
            picked.start.year,
            picked.start.month,
            picked.start.day,
          ),
          end: DateTime(
            picked.end.year,
            picked.end.month,
            picked.end.day,
            23,
            59,
            59,
          ),
        ),
      );
      await _reload();
    }
  }

  String _dateFilterLabel() {
    if (_dateFilter == null) return 'Date';
    final s = _dateFilter!.start;
    final e = _dateFilter!.end;
    String fmt(DateTime d) => '${d.day}/${d.month}/${d.year}';
    return '${fmt(s)} – ${fmt(e)}';
  }

  @override
  Widget build(BuildContext context) {
    final currency = context.watch<SettingsController>().config.currency;

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
                    onTap: () {
                      setState(() => _typeFilter = null);
                      _reload();
                    },
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  _FilterChip(
                    label: 'Expense',
                    selected: _typeFilter == TxnType.expense,
                    onTap: () {
                      setState(() => _typeFilter = TxnType.expense);
                      _reload();
                    },
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  _FilterChip(
                    label: 'Income',
                    selected: _typeFilter == TxnType.income,
                    onTap: () {
                      setState(() => _typeFilter = TxnType.income);
                      _reload();
                    },
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  _FilterChip(
                    label: 'Lent',
                    selected: _typeFilter == TxnType.lent,
                    onTap: () {
                      setState(() => _typeFilter = TxnType.lent);
                      _reload();
                    },
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  _FilterChip(
                    label: 'Borrowed',
                    selected: _typeFilter == TxnType.borrowed,
                    onTap: () {
                      setState(() => _typeFilter = TxnType.borrowed);
                      _reload();
                    },
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Container(width: 1, color: Theme.of(context).dividerColor),
                  const SizedBox(width: AppSpacing.xs),
                  InputChip(
                    avatar: const Icon(Icons.date_range_outlined, size: 16),
                    label: Text(_dateFilterLabel()),
                    selected: _dateFilter != null,
                    onPressed: _pickDateRange,
                    onDeleted: _dateFilter == null
                        ? null
                        : () {
                            setState(() => _dateFilter = null);
                            _reload();
                          },
                  ),
                  if (_categories.isNotEmpty) ...[
                    const SizedBox(width: AppSpacing.md),
                    Container(width: 1, color: Theme.of(context).dividerColor),
                    const SizedBox(width: AppSpacing.md),
                    for (final c in _categories) ...[
                      _FilterChip(
                        label: c,
                        selected: _categoryFilter == c,
                        onTap: () {
                          setState(
                            () => _categoryFilter = _categoryFilter == c
                                ? null
                                : c,
                          );
                          _reload();
                        },
                      ),
                      const SizedBox(width: AppSpacing.xs),
                    ],
                  ],
                ],
              ),
            ),
          ),
          Expanded(
            child: _initialLoad
                ? const Center(child: CircularProgressIndicator())
                : _rows.isEmpty
                ? EmptyState(
                    icon: Icons.receipt_long_outlined,
                    message:
                        (_typeFilter == null &&
                            _categoryFilter == null &&
                            _dateFilter == null &&
                            _searchController.text.isEmpty)
                        ? 'Nothing logged yet.'
                        : 'No transactions match these filters.',
                  )
                : RefreshIndicator(
                    onRefresh: () async {
                      await _loadCategories();
                      await _reload();
                    },
                    child: _buildGroupedList(_rows, currency),
                  ),
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

    if (_hasMore) {
      items.add(
        const Padding(
          padding: EdgeInsets.symmetric(vertical: AppSpacing.lg),
          child: Center(
            child: SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
        ),
      );
    }

    return ListView(
      controller: _scrollController,
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

/// Full detail view for one transaction — how much, what category, what
/// note, and what date — all editable in place, instead of the amount+note
/// only dialog this replaced.
class _TransactionDetailSheet extends StatefulWidget {
  final Transaction txn;
  final String currency;
  final List<String> categories;
  final VoidCallback onDelete;

  const _TransactionDetailSheet({
    required this.txn,
    required this.currency,
    required this.categories,
    required this.onDelete,
  });

  @override
  State<_TransactionDetailSheet> createState() =>
      _TransactionDetailSheetState();
}

class _TransactionDetailSheetState extends State<_TransactionDetailSheet> {
  late final _amountController = TextEditingController(
    text: widget.txn.amountPaise.toStringAsFixed(2),
  );
  late final _noteController = TextEditingController(
    text: widget.txn.note ?? '',
  );
  late String _category = widget.txn.category;
  late DateTime _date = DateTime.parse(widget.txn.date);
  bool _saving = false;

  @override
  void dispose() {
    _amountController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  bool get _isLending =>
      widget.txn.type == TxnType.lent || widget.txn.type == TxnType.borrowed;

  String get _typeLabel => switch (widget.txn.type) {
    TxnType.expense => 'Expense',
    TxnType.income => 'Income',
    TxnType.lent => 'Lent to ${widget.txn.counterparty ?? 'someone'}',
    TxnType.borrowed => 'Borrowed from ${widget.txn.counterparty ?? 'someone'}',
  };

  Color get _typeColor => switch (widget.txn.type) {
    TxnType.expense => AppColors.expense,
    TxnType.income => AppColors.income,
    TxnType.lent => AppColors.income,
    TxnType.borrowed => AppColors.expense,
  };

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(DateTime.now().year - 5),
      lastDate: DateTime.now(),
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _save() async {
    final amount = parseRupeesToPaise(_amountController.text);
    if (amount == null || amount <= 0 || widget.txn.id == null) return;
    setState(() => _saving = true);
    final iso =
        '${_date.year.toString().padLeft(4, '0')}-${_date.month.toString().padLeft(2, '0')}-${_date.day.toString().padLeft(2, '0')}';
    await context.read<ExpensesController>().edit(
      widget.txn.id!,
      amountPaise: amount,
      category: _isLending ? null : _category,
      note: _noteController.text.trim(),
      date: iso,
    );
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final categories = {...widget.categories, _category}.toList()..sort();
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.sm,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: _typeColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(AppRadius.pill),
                    ),
                    child: Text(
                      _typeLabel,
                      style: Theme.of(context).textTheme.labelMedium
                          ?.copyWith(color: _typeColor),
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.delete_outline),
                    onPressed: widget.onDelete,
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              TextField(
                controller: _amountController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                style: Theme.of(context).textTheme.headlineSmall,
                decoration: InputDecoration(
                  prefixText: widget.currency,
                  labelText: 'Amount',
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              if (!_isLending) ...[
                DropdownButtonFormField<String>(
                  initialValue: categories.contains(_category)
                      ? _category
                      : null,
                  decoration: const InputDecoration(labelText: 'Category'),
                  items: categories
                      .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                      .toList(),
                  onChanged: (v) => setState(() => _category = v ?? _category),
                ),
                const SizedBox(height: AppSpacing.md),
              ],
              InkWell(
                borderRadius: BorderRadius.circular(AppRadius.md),
                onTap: _pickDate,
                child: InputDecorator(
                  decoration: const InputDecoration(labelText: 'Date'),
                  child: Text(
                    '${_date.year}-${_date.month.toString().padLeft(2, '0')}-${_date.day.toString().padLeft(2, '0')}',
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              TextField(
                controller: _noteController,
                decoration: const InputDecoration(labelText: 'Note'),
              ),
              const SizedBox(height: AppSpacing.lg),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _saving ? null : _save,
                  child: _saving
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Save'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
