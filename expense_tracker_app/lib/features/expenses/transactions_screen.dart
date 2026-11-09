import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/constants/calendar.dart';
import '../../core/finance/accounting.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/money.dart';
import '../../core/utils/money_formatter.dart';
import '../../core/widgets/app_card.dart';
import '../../core/widgets/app_chip.dart';
import '../../core/widgets/category_icon.dart';
import '../../core/widgets/form_sheet.dart';
import '../../core/widgets/responsive.dart';
import '../../core/widgets/transaction_tile.dart';
import '../../data/models/account.dart';
import '../../data/models/movement.dart';
import '../../data/models/transaction.dart';
import '../accounts/accounts_controller.dart';
import '../cards/cards_controller.dart';
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

/// A row inside a day's card; [first]/[last] decide which corners round.
sealed class _RowEntry extends _ListEntry {
  final bool first;
  bool last = true;
  _RowEntry({required this.first});
}

class _TxnEntry extends _RowEntry {
  final Transaction txn;
  _TxnEntry(this.txn, {required super.first});
}

class _TransferEntry extends _RowEntry {
  final Transfer transfer;
  _TransferEntry(this.transfer, {required super.first});
}

/// Picker value for "entries with no account".
const _unassignedKey = '\u0000unassigned';

class TransactionsScreen extends StatefulWidget {
  /// Opens pre-filtered to one account's history (pushed from Accounts).
  final String? account;

  /// Opens pre-filtered to entries with no account (pushed from Accounts).
  final bool unassigned;

  const TransactionsScreen({super.key, this.account, this.unassigned = false});

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

  /// An account name, [_unassignedKey], or null for all.
  late String? _accountFilter = widget.unassigned
      ? _unassignedKey
      : widget.account;

  /// Transfers for the filtered account — few enough to load in one go.
  List<Transfer> _transfers = [];

  bool get _unassigned => _accountFilter == _unassignedKey;

  /// Transfers only belong in an account's history, and have no type,
  /// category or account-less form to match other filters against.
  bool get _showTransfers =>
      _accountFilter != null &&
      !_unassigned &&
      _typeFilter == null &&
      _categoryFilter == null;

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
      _transfers = [];
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
      if (_offset == 0 && _showTransfers) {
        final term = _searchController.text.trim().toLowerCase();
        final transfers = await _expenses.transfersFor(
          _accountFilter!,
          from: _dateFilter?.start,
          to: _dateFilter?.end,
        );
        _transfers = term.isEmpty
            ? transfers
            : transfers
                  .where((t) => (t.note ?? '').toLowerCase().contains(term))
                  .toList();
      }
      final page = await _expenses.queryPage(
        limit: _pageSize,
        offset: _offset,
        type: _typeFilter,
        category: _categoryFilter,
        from: _dateFilter?.start,
        to: _dateFilter?.end,
        searchTerm: _searchController.text,
        account: _unassigned ? null : _accountFilter,
        unassignedOnly: _unassigned,
      );
      if (!mounted) return;
      setState(() {
        _rows = [..._rows, ...page];
        _offset += page.length;
        _hasMore = page.length == _pageSize;
        _entries = _buildEntries(_rows);
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

  /// Merges loaded transactions with transfers (both newest-first) into
  /// day groups. While more pages remain, transfers older than the last
  /// loaded row wait for the page that reaches their date.
  List<_ListEntry> _buildEntries(List<Transaction> rows) {
    final oldest = rows.isEmpty ? null : rows.last.date;
    final transfers = _hasMore && oldest != null
        ? _transfers.where((t) => t.date.compareTo(oldest) >= 0).toList()
        : _transfers;
    final merged = <(String, Object)>[];
    var ti = 0;
    for (final txn in rows) {
      while (ti < transfers.length &&
          transfers[ti].date.compareTo(txn.date) > 0) {
        merged.add((transfers[ti].date, transfers[ti++]));
      }
      merged.add((txn.date, txn));
    }
    for (; ti < transfers.length; ti++) {
      merged.add((transfers[ti].date, transfers[ti]));
    }

    final entries = <_ListEntry>[];
    String? lastDate;
    var headerIndex = -1;
    var net = 0;
    _RowEntry? prev;

    void closeDay() {
      if (headerIndex < 0) return;
      final h = entries[headerIndex] as _DayHeader;
      entries[headerIndex] = _DayHeader(h.label, net);
    }

    for (final (date, item) in merged) {
      if (date != lastDate) {
        closeDay();
        headerIndex = entries.length;
        entries.add(_DayHeader(_sectionLabel(date), 0));
        net = 0;
        lastDate = date;
        prev = null;
      }
      prev?.last = false;
      final _RowEntry entry;
      if (item is Transaction) {
        // Transfers move money between your own accounts — they aren't
        // income or spending, so they stay out of the day's net.
        if (item.type == TxnType.income) net += item.amountPaise;
        net -= spendingEffect(item.type, item.amountPaise);
        entry = _TxnEntry(item, first: prev == null);
      } else {
        entry = _TransferEntry(item as Transfer, first: prev == null);
      }
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

  /// Planned → done, or cancel. A cancelled movement stays on record and
  /// in the audit log but no longer counts. Loan movements are undone from
  /// the loan, where the installment state lives.
  Future<void> _transferActions(Transfer t) async {
    final loan =
        t.kind == MovementKind.loanPrincipal || t.kind == MovementKind.loanOpen;
    final what = switch (t.kind) {
      MovementKind.cardPayment => 'card payment',
      MovementKind.adjustment => 'adjustment',
      _ => 'transfer',
    };
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (sheet) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (t.status == MovementStatus.planned && !loan)
              ListTile(
                leading: const Icon(Icons.check_circle_outline_rounded),
                title: const Text('Mark as done at the bank'),
                subtitle: const Text('Both balances change now'),
                onTap: () => Navigator.pop(sheet, 'done'),
              ),
            if (loan)
              const ListTile(
                leading: Icon(Icons.info_outline_rounded),
                title: Text('Part of a loan'),
                subtitle: Text('Undo it from Loans & EMI → Undo last payment'),
              )
            else
              ListTile(
                leading: const Icon(Icons.block_rounded),
                title: Text('Cancel this $what'),
                subtitle: const Text('Kept on record, but stops counting'),
                onTap: () => Navigator.pop(sheet, 'cancel'),
              ),
          ],
        ),
      ),
    );
    if (action == null || !mounted) return;
    final accounts = context.read<AccountsController>();
    final cards = context.read<CardsController?>();
    if (action == 'done') {
      await accounts.completeTransfer(t.id!);
    } else {
      final ok = await showDialog<bool>(
        context: context,
        builder: (d) => AlertDialog(
          title: Text('Cancel this $what?'),
          content: Text(
            '${formatMoney(t.amountPaise, context.read<SettingsController>().config.currency)} '
            'between ${t.fromAccount} and ${t.toAccount} will no longer count. '
            'It stays in the history as cancelled.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(d, false),
              child: const Text('Keep'),
            ),
            FilledButton.tonal(
              onPressed: () => Navigator.pop(d, true),
              child: const Text('Cancel it'),
            ),
          ],
        ),
      );
      if (ok != true || !mounted) return;
      await accounts.cancelMovement(t.id!);
    }
    await cards?.refresh();
    if (mounted) await _reload();
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
              foregroundColor: context.palette.onStatus,
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
        accounts: [
          for (final a in context.read<AccountsController>().active)
            a.account.name,
        ],
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
        options: [...accounts, _unassignedKey],
        selected: _accountFilter,
        labelOf: _accountLabel,
        leading: (a) => Icon(
          a == _unassignedKey
              ? Icons.link_off_rounded
              : Icons.account_balance_wallet_outlined,
        ),
      ),
    );
    if (picked == null) return;
    setState(() => _accountFilter = picked.isEmpty ? null : picked);
    _reload();
  }

  String _accountLabel(String key) =>
      key == _unassignedKey ? 'No account' : key;

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
    final pushed = widget.account != null || widget.unassigned;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.unassigned
              ? 'No account'
              : pushed
              ? widget.account!
              : 'Transactions',
        ),
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
                    label: _accountFilter == null
                        ? 'Any account'
                        : _accountLabel(_accountFilter!),
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
            _TransferEntry e => _cardSlice(
              e,
              InkWell(
                onTap: () => _transferActions(e.transfer),
                child: _TransferTile(
                  transfer: e.transfer,
                  account: _accountFilter!,
                  currency: currency,
                ),
              ),
            ),
          };
        },
      ),
    );
  }

  BorderRadius _sliceRadius(_RowEntry e) => BorderRadius.vertical(
    top: Radius.circular(e.first ? AppRadius.lg : 0),
    bottom: Radius.circular(e.last ? AppRadius.lg : 0),
  );

  /// Each row draws its slice of the day's card so the list stays lazy —
  /// rounded top on the first row, rounded bottom on the last.
  Widget _cardSlice(_RowEntry e, Widget child) {
    final p = context.palette;
    return Container(
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: _sliceRadius(e),
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
          child,
        ],
      ),
    );
  }

  Widget _buildRow(_TxnEntry e, String currency) {
    final p = context.palette;
    final txn = e.txn;
    return Dismissible(
      key: ValueKey(txn.id),
      direction: DismissDirection.endToStart,
      confirmDismiss: (_) => _confirmDelete(txn),
      onDismissed: (_) => _deleteTxn(txn),
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
        decoration: BoxDecoration(
          color: p.expense,
          borderRadius: _sliceRadius(e),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.delete_outline_rounded, color: p.onStatus),
            const SizedBox(width: AppSpacing.xs),
            Text('Delete', style: TextStyle(color: p.onStatus)),
          ],
        ),
      ),
      child: _cardSlice(
        e,
        TransactionTile(
          txn: txn,
          currency: currency,
          onTap: () => _editTxn(txn),
        ),
      ),
    );
  }
}

/// A transfer seen from one account: money in from, or out to, another
/// of your accounts. Not editable here — it isn't income or spending.
class _TransferTile extends StatelessWidget {
  final Transfer transfer;
  final String account;
  final String currency;

  const _TransferTile({
    required this.transfer,
    required this.account,
    required this.currency,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final text = Theme.of(context).textTheme;
    final outgoing = transfer.fromAccount == account;
    final title = switch (transfer.kind) {
      MovementKind.cardPayment => 'Card bill · ${transfer.toAccount}',
      MovementKind.loanPrincipal => 'Loan repayment · ${transfer.toAccount}',
      MovementKind.loanOpen => 'Loan received · ${transfer.fromAccount}',
      MovementKind.adjustment => 'Balance adjustment',
      _ =>
        outgoing
            ? 'Transfer to ${transfer.toAccount}'
            : 'Transfer from ${transfer.fromAccount}',
    };
    final note = transfer.note;
    final base = note != null && note.isNotEmpty ? note : 'Transfer';
    // Planned transfers haven't happened at the bank and don't count yet.
    final subtitle = transfer.status == MovementStatus.planned
        ? 'Planned, not done yet · $base'
        : base;
    final amount =
        '${outgoing ? '−' : '+'}${formatMoney(transfer.amountPaise, currency)}';

    return Semantics(
      label: '$title, $subtitle, $amount',
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm + 2,
        ),
        child: Row(
          children: [
            CategoryIcon(
              category: 'transfer',
              icon: switch (transfer.kind) {
                MovementKind.cardPayment => Icons.credit_card_rounded,
                MovementKind.loanPrincipal ||
                MovementKind.loanOpen => Icons.account_balance_rounded,
                _ => Icons.swap_horiz_rounded,
              },
              color: p.debt,
            ),
            const SizedBox(width: AppSpacing.md - 4),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: text.bodyLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xxs),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: text.bodySmall,
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Flexible(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerRight,
                child: Text(
                  amount,
                  style: text.moneyStyle(
                    15,
                    color: outgoing ? p.textPrimary : p.income,
                  ),
                ),
              ),
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
  final String Function(String option)? labelOf;

  /// Pops the chosen option, or '' for "all".
  const _FilterPickerSheet({
    required this.title,
    required this.allLabel,
    required this.options,
    required this.leading,
    this.selected,
    this.labelOf,
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
                  title: Text(
                    option == null
                        ? allLabel
                        : (labelOf?.call(option) ?? option),
                  ),
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

  /// Account names the entry can be moved to. Empty hides the picker.
  final List<String> accounts;

  const TransactionDetailSheet({
    super.key,
    required this.txn,
    required this.currency,
    required this.categories,
    required this.onDelete,
    this.accounts = const [],
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
  late String? _account = widget.txn.account;
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
    TxnType.refund => 'Refund',
  };

  Color _typeColor(AppPalette p) => switch (widget.txn.type) {
    TxnType.expense => p.expense,
    TxnType.income => p.income,
    TxnType.lent => p.income,
    TxnType.borrowed => p.expense,
    TxnType.refund => p.income,
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
    try {
      await context.read<ExpensesController>().edit(
        widget.txn.id!,
        amountPaise: amount,
        category: _isLending ? null : _category,
        note: _noteController.text.trim(),
        date: iso,
        account: _account != widget.txn.account ? _account : null,
      );
    } on StateError {
      setState(() {
        _saving = false;
        _amountError =
            "Can't be less than the ${formatMoney(_refunded, widget.currency)} "
            'already refunded';
      });
      return;
    }
    if (mounted) Navigator.pop(context, true);
  }

  /// Already refunded against this expense, in paise.
  int _refunded = 0;

  @override
  void initState() {
    super.initState();
    if (widget.txn.type == TxnType.expense && widget.txn.id != null) {
      context.read<ExpensesController?>()?.refundedFor(widget.txn.id!).then((
        v,
      ) {
        if (mounted) setState(() => _refunded = v);
      });
    }
  }

  Future<void> _recordRefund() async {
    final left = widget.txn.amountPaise - _refunded;
    final amount = TextEditingController(text: paiseToEditString(left));
    final ok = await showFormSheet(
      context,
      title: const Text('Record a refund'),
      subtitle:
          'Money back for this expense. It lowers your spending; it isn’t '
          'income. Up to ${formatMoney(left, widget.currency)} can be refunded.',
      submitLabel: 'Record refund',
      validate: () {
        final error = positiveAmountError(amount.text);
        if (error != null) return error;
        return parseRupeesToPaise(amount.text)! > left
            ? 'That’s more than is left to refund.'
            : null;
      },
      builder: (context, setState) => TextField(
        controller: amount,
        autofocus: true,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: InputDecoration(
          labelText: 'Refund amount',
          prefixText: '${widget.currency} ',
        ),
      ),
    );
    if (!ok || !mounted) return;
    await context.read<ExpensesController>().addRefund(
      expenseId: widget.txn.id!,
      amountPaise: parseRupeesToPaise(amount.text)!,
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
              if (widget.accounts.isNotEmpty) ...[
                DropdownButtonFormField<String>(
                  initialValue: widget.accounts.contains(_account)
                      ? _account
                      : null,
                  hint: const Text('Not linked to an account'),
                  decoration: InputDecoration(
                    labelText: 'Account',
                    helperText: _account == null
                        ? "Pick one so this counts toward that account's balance"
                        : null,
                  ),
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  items: [
                    for (final a in widget.accounts)
                      DropdownMenuItem(value: a, child: Text(a)),
                  ],
                  onChanged: (v) => setState(() => _account = v ?? _account),
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
              if (widget.txn.type == TxnType.expense) ...[
                const SizedBox(height: AppSpacing.sm),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        _refunded > 0
                            ? '${formatMoney(_refunded, widget.currency)} refunded so far'
                            : 'Got money back for this?',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                    if (_refunded < widget.txn.amountPaise)
                      TextButton.icon(
                        onPressed: _recordRefund,
                        icon: const Icon(Icons.undo_rounded),
                        label: const Text('Record a refund'),
                      ),
                  ],
                ),
              ],
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
