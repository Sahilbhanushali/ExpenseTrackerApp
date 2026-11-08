import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/constants/calendar.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/money.dart';
import '../../core/utils/money_formatter.dart';
import '../../core/widgets/app_card.dart';
import '../../core/widgets/app_chip.dart';
import '../../core/widgets/category_icon.dart';
import '../../core/widgets/responsive.dart';
import '../../core/widgets/transaction_tile.dart';
import '../../data/models/transaction.dart';
import '../accounts/accounts_controller.dart';
import '../settings/settings_controller.dart';
import 'expenses_controller.dart';

const _pageSize = 50;

/// One entry in the flattened, lazily built list: either a day header or a
/// transaction row (with its position inside that day's card).
sealed class _ListEntry {}

class _DayHeader extends _ListEntry {
  final String label;

  /// Net of the day's loaded rows, in paise (income − expense).
  final int net;
  _DayHeader(this.label, this.net);
}

class _TxnEntry extends _ListEntry {
  final Transaction txn;
  final bool first;
  bool last = true;
  _TxnEntry(this.txn, {required this.first});
}

class TransactionsScreen extends StatefulWidget {
  /// Opens pre-filtered to one account's history (pushed from Accounts).
  final String? account;

  const TransactionsScreen({super.key, this.account});

  @override
  State<TransactionsScreen> createState() => _TransactionsScreenState();
}

class _TransactionsScreenState extends State<TransactionsScreen> {
  final _searchController = TextEditingController();
  final _scrollController = ScrollController();
  Timer? _searchDebounce;

  List<Transaction> _rows = [];

  /// Derived from [_rows] once per load, not on every build.
  List<_ListEntry> _entries = [];
  List<String> _categories = [];
  bool _initialLoad = true;
  bool _loadingMore = false;
  bool _hasMore = true;
  int _offset = 0;
  Object? _loadError;

  TxnType? _typeFilter;
  String? _categoryFilter;
  DateTimeRange? _dateFilter;
  late String? _accountFilter = widget.account;

  late final ExpensesController _expenses;

  @override
  void initState() {
    super.initState();
    _expenses = context.read<ExpensesController>();
    // IndexedStack keeps this screen mounted for the whole app lifetime, so
    // it never gets a fresh initState when the user switches back to this
    // tab — without this listener, a transaction added from the Dashboard
    // (or anywhere else) would never show up here.
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
      _entries = [];
      _offset = 0;
      _hasMore = true;
      _initialLoad = true;
      _loadError = null;
    });
    await _loadMore();
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore) return;
    setState(() => _loadingMore = true);
    try {
      final page = await _expenses.queryPage(
        limit: _pageSize,
        offset: _offset,
        type: _typeFilter,
        category: _categoryFilter,
        from: _dateFilter?.start,
        to: _dateFilter?.end,
        searchTerm: _searchController.text,
        account: _accountFilter,
      );
      if (!mounted) return;
      setState(() {
        _rows = [..._rows, ...page];
        _entries = _buildEntries(_rows);
        _offset += page.length;
        _hasMore = page.length == _pageSize;
        _loadingMore = false;
        _initialLoad = false;
      });
    } catch (e) {
      debugPrint('Transactions load failed: ${e.runtimeType}');
      if (!mounted) return;
      setState(() {
        _loadError = e;
        _loadingMore = false;
        _initialLoad = false;
        _hasMore = false;
      });
    }
  }

  List<_ListEntry> _buildEntries(List<Transaction> rows) {
    final entries = <_ListEntry>[];
    String? lastDate;
    var headerIndex = -1;
    var net = 0;
    _TxnEntry? prev;

    void closeDay() {
      if (headerIndex < 0) return;
      final h = entries[headerIndex] as _DayHeader;
      entries[headerIndex] = _DayHeader(h.label, net);
    }

    for (final txn in rows) {
      if (txn.date != lastDate) {
        closeDay();
        headerIndex = entries.length;
        entries.add(_DayHeader(_sectionLabel(txn.date), 0));
        net = 0;
        lastDate = txn.date;
        prev = null;
      }
      if (txn.type == TxnType.income) net += txn.amountPaise;
      if (txn.type == TxnType.expense) net -= txn.amountPaise;
      prev?.last = false;
      final entry = _TxnEntry(txn, first: prev == null);
      entries.add(entry);
      prev = entry;
    }
    closeDay();
    return entries;
  }

  void _onSearchChanged(String term) {
    setState(() {}); // toggles the clear button
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 300), _reload);
  }

  Future<void> _undo() async {
    // Deleting via ExpensesController already calls its own refresh(),
    // which the listener registered in initState picks up.
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
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: context.palette.expense,
              foregroundColor: Colors.white,
            ),
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
      showDragHandle: true,
      builder: (context) => TransactionDetailSheet(
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
    String iso(DateTime d) =>
        '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    if (isoDate == iso(today)) return 'Today';
    if (isoDate == iso(today.subtract(const Duration(days: 1)))) {
      return 'Yesterday';
    }
    final d = DateTime.tryParse(isoDate);
    if (d == null) return isoDate;
    final weekday = kWeekdayNames[d.weekday - 1].substring(0, 3);
    final year = d.year == today.year ? '' : ' ${d.year}';
    return '$weekday, ${d.day} ${kMonthNamesShort[d.month - 1]}$year';
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

  Future<void> _pickCategory() async {
    final picked = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => _FilterPickerSheet(
        title: 'Filter by category',
        allLabel: 'All categories',
        options: _categories,
        selected: _categoryFilter,
        leading: (cat) => CategoryIcon(category: cat, size: 36),
      ),
    );
    if (picked == null) return;
    setState(() => _categoryFilter = picked.isEmpty ? null : picked);
    _reload();
  }

  Future<void> _pickAccount(List<String> accounts) async {
    final picked = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => _FilterPickerSheet(
        title: 'Filter by account',
        allLabel: 'All accounts',
        options: accounts,
        selected: _accountFilter,
        leading: (_) => const Icon(Icons.account_balance_wallet_outlined),
      ),
    );
    if (picked == null) return;
    setState(() => _accountFilter = picked.isEmpty ? null : picked);
    _reload();
  }

  String _dateFilterLabel() {
    if (_dateFilter == null) return 'Any date';
    String fmt(DateTime d) => '${d.day} ${kMonthNamesShort[d.month - 1]}';
    return '${fmt(_dateFilter!.start)} – ${fmt(_dateFilter!.end)}';
  }

  void _setType(TxnType? type) {
    setState(() => _typeFilter = type);
    _reload();
  }

  bool get _anyFilter =>
      _typeFilter != null ||
      _categoryFilter != null ||
      _dateFilter != null ||
      _accountFilter != null ||
      _searchController.text.isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final currency = context.watch<SettingsController>().config.currency;
    final accounts = context.select<AccountsController, List<String>>(
      (c) => [for (final a in c.accounts) a.account.name],
    );
    final pushed = widget.account != null;

    return Scaffold(
      appBar: AppBar(
        title: Text(pushed ? widget.account! : 'Transactions'),
        actions: [
          IconButton(
            icon: const Icon(Icons.undo_rounded),
            tooltip: 'Undo last entry',
            onPressed: _undo,
          ),
          const SizedBox(width: AppSpacing.sm),
        ],
      ),
      body: ResponsivePage(
        builder: (context, gutter) => Column(
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(gutter, AppSpacing.xs, gutter, 0),
              child: TextField(
                controller: _searchController,
                onChanged: _onSearchChanged,
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  hintText: 'Search notes or category',
                  prefixIcon: const Icon(Icons.search_rounded),
                  suffixIcon: _searchController.text.isEmpty
                      ? null
                      : IconButton(
                          tooltip: 'Clear search',
                          icon: const Icon(Icons.close_rounded),
                          onPressed: () {
                            _searchController.clear();
                            _onSearchChanged('');
                          },
                        ),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.md - 4),
            ChipRow(
              children: [
                AppChoiceChip(
                  label: 'All',
                  selected: _typeFilter == null,
                  onTap: () => _setType(null),
                ),
                AppChoiceChip(
                  label: 'Expenses',
                  selected: _typeFilter == TxnType.expense,
                  onTap: () => _setType(TxnType.expense),
                ),
                AppChoiceChip(
                  label: 'Income',
                  selected: _typeFilter == TxnType.income,
                  onTap: () => _setType(TxnType.income),
                ),
                AppChoiceChip(
                  label: 'Lent',
                  selected: _typeFilter == TxnType.lent,
                  onTap: () => _setType(TxnType.lent),
                ),
                AppChoiceChip(
                  label: 'Borrowed',
                  selected: _typeFilter == TxnType.borrowed,
                  onTap: () => _setType(TxnType.borrowed),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            ChipRow(
              children: [
                AppChoiceChip(
                  icon: Icons.date_range_rounded,
                  label: _dateFilterLabel(),
                  selected: _dateFilter != null,
                  onTap: _pickDateRange,
                  onClear: () {
                    setState(() => _dateFilter = null);
                    _reload();
                  },
                ),
                if (_categories.isNotEmpty)
                  AppChoiceChip(
                    icon: Icons.category_outlined,
                    label: _categoryFilter ?? 'Any category',
                    selected: _categoryFilter != null,
                    onTap: _pickCategory,
                    onClear: () {
                      setState(() => _categoryFilter = null);
                      _reload();
                    },
                  ),
                if (accounts.isNotEmpty && !pushed)
                  AppChoiceChip(
                    icon: Icons.account_balance_wallet_outlined,
                    label: _accountFilter ?? 'Any account',
                    selected: _accountFilter != null,
                    onTap: () => _pickAccount(accounts),
                    onClear: () {
                      setState(() => _accountFilter = null);
                      _reload();
                    },
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Expanded(
              child: AnimatedSwitcher(
                duration: AppDurations.of(context, AppDurations.base),
                child: _buildBody(currency, gutter),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(String currency, double gutter) {
    if (_initialLoad) {
      return Padding(
        key: const ValueKey('loading'),
        padding: EdgeInsets.symmetric(horizontal: gutter),
        child: const SkeletonList(),
      );
    }
    if (_loadError != null) {
      return ErrorState(
        key: const ValueKey('error'),
        message: "Couldn't load your transactions.",
        onRetry: _reload,
      );
    }
    if (_rows.isEmpty) {
      return EmptyState(
        key: const ValueKey('empty'),
        icon: _anyFilter
            ? Icons.filter_alt_off_outlined
            : Icons.receipt_long_outlined,
        title: _anyFilter ? 'No matches' : 'Nothing logged yet',
        message: _anyFilter
            ? 'No transactions match these filters.'
            : 'Tap + to add your first transaction.',
      );
    }
    return RefreshIndicator(
      key: const ValueKey('list'),
      onRefresh: () async {
        await _loadCategories();
        await _reload();
      },
      child: ListView.builder(
        controller: _scrollController,
        padding: EdgeInsets.fromLTRB(
          gutter,
          AppSpacing.sm,
          gutter,
          AppSpacing.navClearance,
        ),
        itemCount: _entries.length + (_hasMore ? 1 : 0),
        itemBuilder: (context, i) {
          if (i == _entries.length) {
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: AppSpacing.lg),
              child: Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            );
          }
          return switch (_entries[i]) {
            _DayHeader h => _DayHeaderRow(
              header: h,
              currency: currency,
              first: i == 0,
            ),
            _TxnEntry e => _buildRow(e, currency),
          };
        },
      ),
    );
  }

  Widget _buildRow(_TxnEntry e, String currency) {
    final p = context.palette;
    final txn = e.txn;
    final radius = BorderRadius.vertical(
      top: Radius.circular(e.first ? AppRadius.lg : 0),
      bottom: Radius.circular(e.last ? AppRadius.lg : 0),
    );
    // Each row draws its slice of the day's card so the list stays lazy —
    // rounded top on the first row, rounded bottom on the last.
    return Dismissible(
      key: ValueKey(txn.id),
      direction: DismissDirection.endToStart,
      confirmDismiss: (_) => _confirmDelete(txn),
      onDismissed: (_) => _deleteTxn(txn),
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
        decoration: BoxDecoration(color: p.expense, borderRadius: radius),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.delete_outline_rounded, color: Colors.white),
            SizedBox(width: AppSpacing.xs),
            Text('Delete', style: TextStyle(color: Colors.white)),
          ],
        ),
      ),
      child: Container(
        decoration: BoxDecoration(
          color: p.surface,
          borderRadius: radius,
          border: Border(
            left: BorderSide(color: p.border),
            right: BorderSide(color: p.border),
            top: e.first ? BorderSide(color: p.border) : BorderSide.none,
            bottom: e.last ? BorderSide(color: p.border) : BorderSide.none,
          ),
        ),
        padding: EdgeInsets.only(
          top: e.first ? AppSpacing.xs : 0,
          bottom: e.last ? AppSpacing.xs : 0,
        ),
        child: Column(
          children: [
            if (!e.first)
              Divider(
                indent: AppSpacing.md + AppSizes.iconBadge + 12,
                endIndent: AppSpacing.md,
                color: p.border,
              ),
            TransactionTile(
              txn: txn,
              currency: currency,
              onTap: () => _editTxn(txn),
            ),
          ],
        ),
      ),
    );
  }
}

class _DayHeaderRow extends StatelessWidget {
  final _DayHeader header;
  final String currency;
  final bool first;

  const _DayHeaderRow({
    required this.header,
    required this.currency,
    required this.first,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.xs,
        first ? AppSpacing.xs : AppSpacing.lg - 4,
        AppSpacing.xs,
        AppSpacing.sm,
      ),
      child: Row(
        children: [
          Expanded(
            child: Semantics(
              header: true,
              child: Text(header.label, style: text.labelMedium),
            ),
          ),
          if (header.net != 0)
            Text(
              '${header.net > 0 ? '+' : '−'}${formatMoney(header.net.abs(), currency)}',
              style: text.labelMedium?.copyWith(
                color: header.net > 0 ? p.income : p.textSecondary,
              ),
            ),
        ],
      ),
    );
  }
}

class _FilterPickerSheet extends StatelessWidget {
  final String title;
  final String allLabel;
  final List<String> options;
  final String? selected;
  final Widget Function(String option) leading;

  /// Pops the chosen option, or '' for "all".
  const _FilterPickerSheet({
    required this.title,
    required this.allLabel,
    required this.options,
    required this.leading,
    this.selected,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.7,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.page,
              0,
              AppSpacing.page,
              AppSpacing.sm,
            ),
            child: Text(title, style: Theme.of(context).textTheme.titleLarge),
          ),
          Flexible(
            child: ListView.builder(
              shrinkWrap: true,
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.sm,
                0,
                AppSpacing.sm,
                AppSpacing.lg,
              ),
              itemCount: options.length + 1,
              itemBuilder: (context, i) {
                final option = i == 0 ? null : options[i - 1];
                return ListTile(
                  leading: option == null
                      ? Icon(
                          Icons.all_inclusive_rounded,
                          color: p.textSecondary,
                        )
                      : leading(option),
                  title: Text(option ?? allLabel),
                  trailing: option == selected
                      ? Icon(Icons.check_rounded, color: p.savings)
                      : null,
                  onTap: () => Navigator.pop(context, option ?? ''),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// Full detail view for one transaction — amount, category, note and date,
/// all editable in place.
/// Public so the amount round-trip (paise in, rupees shown, paise back out)
/// can be widget-tested — prefilling this field with raw paise multiplied
/// every edited amount by 100.
class TransactionDetailSheet extends StatefulWidget {
  final Transaction txn;
  final String currency;
  final List<String> categories;
  final VoidCallback onDelete;

  const TransactionDetailSheet({
    super.key,
    required this.txn,
    required this.currency,
    required this.categories,
    required this.onDelete,
  });

  @override
  State<TransactionDetailSheet> createState() => TransactionDetailSheetState();
}

class TransactionDetailSheetState extends State<TransactionDetailSheet> {
  // Rupees, because that is what the user types and what _save parses back.
  // Prefilling raw paise here made every edit multiply the amount by 100.
  late final _amountController = TextEditingController(
    text: paiseToEditString(widget.txn.amountPaise),
  );
  late final _noteController = TextEditingController(
    text: widget.txn.note ?? '',
  );
  late String _category = widget.txn.category;
  late DateTime _date = DateTime.parse(widget.txn.date);
  bool _saving = false;
  String? _amountError;

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

  Color _typeColor(AppPalette p) => switch (widget.txn.type) {
    TxnType.expense => p.expense,
    TxnType.income => p.income,
    TxnType.lent => p.income,
    TxnType.borrowed => p.expense,
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
    if (amount == null || amount <= 0) {
      setState(() => _amountError = 'Enter a valid amount greater than zero');
      return;
    }
    if (widget.txn.id == null) return;
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
    final p = context.palette;
    final text = Theme.of(context).textTheme;
    final typeColor = _typeColor(p);
    final categories = {...widget.categories, _category}.toList()..sort();
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.page,
            0,
            AppSpacing.page,
            AppSpacing.lg,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  CategoryIcon(
                    category: _isLending ? 'lending' : _category,
                    size: 44,
                  ),
                  const SizedBox(width: AppSpacing.md - 4),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Edit transaction', style: text.titleLarge),
                        const SizedBox(height: AppSpacing.xxs),
                        Row(
                          children: [
                            Container(
                              width: 6,
                              height: 6,
                              decoration: BoxDecoration(
                                color: typeColor,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: AppSpacing.xs + 2),
                            Flexible(
                              child: Text(
                                _typeLabel,
                                overflow: TextOverflow.ellipsis,
                                style: text.labelMedium?.copyWith(
                                  color: typeColor,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Delete transaction',
                    icon: Icon(Icons.delete_outline_rounded, color: p.expense),
                    onPressed: widget.onDelete,
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),
              TextField(
                controller: _amountController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                style: text.moneyStyle(28, weight: FontWeight.w800),
                onChanged: (_) {
                  if (_amountError != null) setState(() => _amountError = null);
                },
                decoration: InputDecoration(
                  prefixText: '${widget.currency} ',
                  prefixStyle: text.moneyStyle(28, color: p.textTertiary),
                  labelText: 'Amount',
                  errorText: _amountError,
                ),
              ),
              const SizedBox(height: AppSpacing.md - 4),
              if (!_isLending) ...[
                DropdownButtonFormField<String>(
                  initialValue: categories.contains(_category)
                      ? _category
                      : null,
                  decoration: const InputDecoration(labelText: 'Category'),
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  items: categories
                      .map(
                        (c) => DropdownMenuItem(
                          value: c,
                          child: Row(
                            children: [
                              CategoryIcon(category: c, size: 28),
                              const SizedBox(width: AppSpacing.sm + 2),
                              Text(c),
                            ],
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: (v) => setState(() => _category = v ?? _category),
                ),
                const SizedBox(height: AppSpacing.md - 4),
              ],
              InkWell(
                borderRadius: BorderRadius.circular(AppRadius.md),
                onTap: _pickDate,
                child: InputDecorator(
                  decoration: const InputDecoration(
                    labelText: 'Date',
                    suffixIcon: Icon(Icons.calendar_today_rounded),
                  ),
                  child: Text(
                    '${_date.day} ${kMonthNames[_date.month - 1]} ${_date.year}',
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.md - 4),
              TextField(
                controller: _noteController,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(labelText: 'Note'),
              ),
              const SizedBox(height: AppSpacing.lg),
              FilledButton(
                onPressed: _saving ? null : _save,
                child: _saving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Save changes'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
