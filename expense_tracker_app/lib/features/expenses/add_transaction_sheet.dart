import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../core/constants/categories.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/utils/budget_alerts.dart';
import '../../core/utils/expense_parser.dart';
import '../../core/utils/money_formatter.dart';
import '../../core/utils/notification_service.dart';
import '../../core/utils/receipt_parser.dart';
import '../../core/widgets/press_scale.dart';
import '../../data/models/recurring_bill.dart';
import '../../data/models/transaction.dart';
import '../accounts/accounts_controller.dart';
import '../lending/lending_controller.dart';
import '../recurring/recurring_controller.dart';
import '../settings/settings_controller.dart';
import 'expenses_controller.dart';

Future<void> showAddTransactionSheet(BuildContext context) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => const AddTransactionSheet(),
  );
}

class AddTransactionSheet extends StatefulWidget {
  const AddTransactionSheet({super.key});

  @override
  State<AddTransactionSheet> createState() => _AddTransactionSheetState();
}

class _AddTransactionSheetState extends State<AddTransactionSheet> {
  bool _quickMode = true;
  bool _scanning = false;

  // Quick mode
  final _textController = TextEditingController();
  ParsedTransaction? _preview;
  // Set only once the user explicitly taps the date chip — until then the
  // date comes from whatever parseMessage found in the text (e.g.
  // "yesterday"), or today if it found nothing.
  DateTime? _quickDateOverride;

  // Detailed mode
  final _amountController = TextEditingController();
  final _noteController = TextEditingController();
  TxnType _type = TxnType.expense;
  String _category = kDefaultCategory;
  DateTime _date = DateTime.now();

  @override
  void dispose() {
    _textController.dispose();
    _amountController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  String _isoDate(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  void _onTextChanged(String value) {
    final settings = context.read<SettingsController>();
    setState(() {
      if (value.trim().isEmpty) {
        _preview = null;
        return;
      }
      final parsed = parseMessage(
        value,
        extraCategories: settings.config.customCategories,
      );
      // A date the user explicitly picked wins over whatever the parser
      // found in the text — otherwise typing more after picking a date
      // would silently snap it back to "today".
      _preview = _quickDateOverride == null
          ? parsed
          : ParsedTransaction(
              amount: parsed.amount,
              category: parsed.category,
              note: parsed.note,
              type: parsed.type,
              counterparty: parsed.counterparty,
              date: _isoDate(_quickDateOverride!),
              emiMonths: parsed.emiMonths,
              pendingAmount: parsed.pendingAmount,
            );
    });
  }

  Future<void> _pickQuickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _quickDateOverride ?? now,
      firstDate: DateTime(now.year - 5),
      lastDate: now,
    );
    if (picked == null) return;
    setState(() {
      _quickDateOverride = picked;
      final p = _preview;
      if (p != null) {
        _preview = ParsedTransaction(
          amount: p.amount,
          category: p.category,
          note: p.note,
          type: p.type,
          counterparty: p.counterparty,
          date: _isoDate(picked),
          emiMonths: p.emiMonths,
          pendingAmount: p.pendingAmount,
        );
      }
    });
  }

  Future<void> _scanReceipt(ImageSource source) async {
    final picker = ImagePicker();
    final file = await picker.pickImage(source: source, imageQuality: 85);
    if (file == null || !mounted) return;

    setState(() => _scanning = true);
    final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
    try {
      final result = await recognizer.processImage(
        InputImage.fromFilePath(file.path),
      );
      if (!mounted) return;
      final settings = context.read<SettingsController>();
      final receipt = parseReceiptText(
        result.text,
        extraCategories: settings.config.customCategories,
      );

      if (receipt.amount == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                "Couldn't find an amount on that receipt — try typing it instead.",
              ),
            ),
          );
        }
        return;
      }

      final now = DateTime.now();
      final iso =
          '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
      setState(() {
        _quickMode = true;
        _textController.text = receipt.note;
        _preview = ParsedTransaction(
          amount: receipt.amount,
          category: receipt.category,
          note: receipt.note,
          type: ParsedTxnType.expense,
          counterparty: null,
          date: iso,
        );
      });
    } finally {
      await recognizer.close();
      if (mounted) setState(() => _scanning = false);
    }
  }

  Future<void> _pickReceiptSource() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Take a photo'),
              onTap: () => Navigator.pop(context, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Choose from gallery'),
              onTap: () => Navigator.pop(context, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
    if (source != null) await _scanReceipt(source);
  }

  Future<void> _submitQuick() async {
    if (_preview == null || _preview!.amount == null) return;
    final p = _preview!;
    if (p.type == ParsedTxnType.repayment) {
      await _submitRepayment(p);
      return;
    }
    if (p.type == ParsedTxnType.emiPayment) {
      await _submitEmiPayment(p);
      return;
    }
    if (p.type == ParsedTxnType.emiCreate) {
      await _submitEmiCreate(p);
      return;
    }
    // "50000 5000 given pending 45000" already resolved amount down to the
    // 5000 actually handed over — fold the pending balance into the note so
    // it isn't silently lost, since the loan record itself only holds one
    // number.
    final effective = p.pendingAmount == null
        ? p
        : ParsedTransaction(
            amount: p.amount,
            category: p.category,
            note: p.note.isEmpty
                ? '₹${p.pendingAmount!.toStringAsFixed(0)} pending'
                : '${p.note} — ₹${p.pendingAmount!.toStringAsFixed(0)} pending',
            type: p.type,
            counterparty: p.counterparty,
            date: p.date,
          );
    await _logWithWarnings(
      category: effective.category,
      note: effective.note.isEmpty ? null : effective.note,
      isExpense: effective.type == ParsedTxnType.expense,
      date: effective.date,
      logTxn: () => context.read<ExpensesController>().addFromParsed(effective),
    );
  }

  /// "Given emi for fridge of 10000" shouldn't log a disconnected expense —
  /// it should find the matching active EMI (by category/note) and apply
  /// this month's installment the same way "Log now" on Recurring & EMI
  /// does, decrementing what's left.
  Future<void> _submitEmiPayment(ParsedTransaction p) async {
    final recurring = context.read<RecurringController>();
    final tokens = p.note
        .toLowerCase()
        .split(RegExp(r'\s+'))
        .where((t) => t.length >= 3)
        .toList();
    final candidates = recurring.bills
        .where(
          (b) =>
              b.type == RecurringType.expense &&
              b.installmentsRemaining != null,
        )
        .where((b) {
          if (tokens.isEmpty) return false;
          final haystack = '${b.category} ${b.note ?? ''}'.toLowerCase();
          return tokens.any((t) => haystack.contains(t));
        })
        .toList();

    if (candidates.isEmpty) {
      final messenger = ScaffoldMessenger.of(context);
      await context.read<ExpensesController>().addFromParsed(
        ParsedTransaction(
          amount: p.amount,
          category: p.category,
          note: p.note,
          type: ParsedTxnType.expense,
          counterparty: null,
          date: p.date,
        ),
      );
      if (!mounted) return;
      await context.read<AccountsController>().refresh();
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            p.note.isEmpty
                ? 'No matching EMI found — logged as an expense instead.'
                : 'No EMI found for "${p.note}" — logged as an expense instead.',
          ),
        ),
      );
      HapticFeedback.mediumImpact();
      if (mounted) Navigator.of(context).pop();
      return;
    }

    final target = candidates.length == 1
        ? candidates.first
        : await _pickEmiToPay(candidates);
    if (target == null || !mounted) return;

    final result = await recurring.logDue(target);
    if (!mounted) return;
    await context.read<AccountsController>().refresh();
    if (!mounted) return;
    HapticFeedback.mediumImpact();
    final messenger = ScaffoldMessenger.of(context);
    Navigator.of(context).pop();
    messenger.showSnackBar(SnackBar(content: Text(result.message)));
  }

  Future<RecurringBill?> _pickEmiToPay(List<RecurringBill> candidates) {
    return showDialog<RecurringBill>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Which EMI?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: candidates
              .map(
                (b) => ListTile(
                  title: Text(
                    b.note?.isNotEmpty == true ? b.note! : b.category,
                  ),
                  subtitle: Text('${b.installmentsRemaining} left'),
                  trailing: Text(b.amount.toStringAsFixed(0)),
                  onTap: () => Navigator.pop(context, b),
                ),
              )
              .toList(),
        ),
      ),
    );
  }

  /// "Bought fridge for 65000 on emi for 6 months, pay 10000 every month" —
  /// creates the EMI outright instead of logging one plain expense, the
  /// same as filling out the Recurring & EMI screen's EMI form by hand.
  Future<void> _submitEmiCreate(ParsedTransaction p) async {
    final currency = context.read<SettingsController>().config.currency;
    final recurring = context.read<RecurringController>();
    await recurring.logEmi(
      monthlyAmount: p.amount!,
      category: p.category,
      note: p.note.isEmpty ? null : p.note,
      months: p.emiMonths!,
      dueDay: DateTime.now().day,
    );
    if (!mounted) return;
    await context.read<ExpensesController>().refresh();
    if (!mounted) return;
    await context.read<AccountsController>().refresh();
    if (!mounted) return;
    HapticFeedback.mediumImpact();
    final messenger = ScaffoldMessenger.of(context);
    Navigator.of(context).pop();
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          'EMI created: ${formatMoney(p.amount!, currency)}/month for ${p.emiMonths} months',
        ),
      ),
    );
  }

  /// "Paid back 500 to sachin" shouldn't log a disconnected expense — it
  /// should reduce the matching outstanding loan with sachin, the same way
  /// tapping "Apply repayment" on the Owed screen does.
  Future<void> _submitRepayment(ParsedTransaction p) async {
    final lending = context.read<LendingController>();
    final name = p.counterparty?.toLowerCase();
    final matches = name == null
        ? <Transaction>[]
        : lending.outstanding
              .where((t) => (t.counterparty ?? '').toLowerCase() == name)
              .toList();

    if (matches.isEmpty) {
      final messenger = ScaffoldMessenger.of(context);
      await context.read<ExpensesController>().addFromParsed(
        ParsedTransaction(
          amount: p.amount,
          category: 'other',
          note: p.note,
          type: ParsedTxnType.expense,
          counterparty: null,
          date: p.date,
        ),
      );
      if (!mounted) return;
      await context.read<AccountsController>().refresh();
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            p.counterparty == null
                ? 'No outstanding loan found — logged as an expense instead.'
                : "No outstanding loan with ${p.counterparty} — logged as an expense instead.",
          ),
        ),
      );
      HapticFeedback.mediumImpact();
      if (mounted) Navigator.of(context).pop();
      return;
    }

    final target = matches.length == 1
        ? matches.first
        : await _pickLoanToRepay(matches);
    if (target == null || !mounted) return;

    final result = await lending.repay(target.id!, p.amount!);
    if (!mounted) return;
    await context.read<AccountsController>().refresh();
    if (!mounted) return;
    HapticFeedback.mediumImpact();
    Navigator.of(context).pop();
    if (result != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result.row.isSettled
                ? '${target.counterparty} — fully settled!'
                : 'Applied to ${target.counterparty}: outstanding now ${result.row.amount.toStringAsFixed(0)}',
          ),
        ),
      );
    }
  }

  Future<Transaction?> _pickLoanToRepay(List<Transaction> matches) {
    return showDialog<Transaction>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Which one?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: matches
              .map(
                (t) => ListTile(
                  title: Text(t.counterparty ?? 'Someone'),
                  subtitle: Text(
                    t.type == TxnType.lent ? 'Owes you' : 'You owe',
                  ),
                  trailing: Text(t.amount.toStringAsFixed(0)),
                  onTap: () => Navigator.pop(context, t),
                ),
              )
              .toList(),
        ),
      ),
    );
  }

  Future<void> _submitDetailed() async {
    final amount = double.tryParse(_amountController.text.replaceAll(',', ''));
    if (amount == null || amount <= 0) return;
    final iso =
        '${_date.year.toString().padLeft(4, '0')}-${_date.month.toString().padLeft(2, '0')}-${_date.day.toString().padLeft(2, '0')}';
    final note = _noteController.text.trim().isEmpty
        ? null
        : _noteController.text.trim();
    await _logWithWarnings(
      category: _type == TxnType.income ? 'income' : _category,
      note: note,
      isExpense: _type == TxnType.expense,
      date: iso,
      logTxn: () => context.read<ExpensesController>().addManual(
        amount: amount,
        category: _type == TxnType.income ? 'income' : _category,
        note: note,
        type: _type,
        date: iso,
      ),
    );
  }

  /// Logs the transaction, then — for an expense dated in the current month —
  /// checks whether it just pushed the overall or category budget across the
  /// 80%/100% line, and surfaces a warning the moment that happens (parity
  /// with bot.py's in-chat threshold warnings, which the app was missing).
  Future<void> _logWithWarnings({
    required String category,
    String? note,
    required bool isExpense,
    required String date,
    required Future<void> Function() logTxn,
  }) async {
    final expenses = context.read<ExpensesController>();
    final settings = context.read<SettingsController>();
    final today = DateTime.now();
    final isCurrentMonth = date.startsWith(
      '${today.year.toString().padLeft(4, '0')}-${today.month.toString().padLeft(2, '0')}',
    );

    final beforeSpent = expenses.monthTotal.expense;
    final beforeCat = expenses.categoryTotals[category] ?? 0;

    await logTxn();
    if (!mounted) return;
    // Every transaction can move an account's derived balance (expense,
    // income, or a fresh lend/borrow) — keep the Dashboard's net worth in
    // sync instead of leaving it stale until the next full refresh.
    await context.read<AccountsController>().refresh();
    if (!mounted) return;

    if (isExpense && isCurrentMonth) {
      final config = settings.config;
      final budget = settings.effectiveBudget(expenses.monthTotal.income);
      final catCap = config.budgets[category] ?? 0;
      final warnings = buildThresholdWarnings(
        beforeSpent: beforeSpent,
        afterSpent: expenses.monthTotal.expense,
        budget: budget,
        beforeCat: beforeCat,
        afterCat: expenses.categoryTotals[category] ?? 0,
        catCap: catCap,
        category: category,
        fmt: (v) => formatMoney(v, config.currency),
      );
      if (warnings.isNotEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(warnings.join('\n')),
            backgroundColor: AppColors.expense,
            duration: const Duration(seconds: 4),
          ),
        );
        NotificationService.instance.showNow(
          id: 'budget_${category.hashCode}'.hashCode,
          title: 'Budget alert',
          body: warnings.join(' '),
        );
      }
    }

    if (isExpense) await _maybeSuggestRecurring(category, note);
    if (!mounted) return;

    HapticFeedback.mediumImpact();
    Navigator.of(context).pop();
  }

  /// After logging an expense, checks whether the same category+note has
  /// shown up in 3+ of the last 4 months at a similar amount — if so, and
  /// there's no recurring reminder for it yet, offers to add one.
  Future<void> _maybeSuggestRecurring(String category, String? note) async {
    final recurring = context.read<RecurringController>();
    final alreadyTracked = recurring.bills.any(
      (b) => b.category == category && b.note == note,
    );
    if (alreadyTracked) return;

    final candidate = await context.read<ExpensesController>().detectRecurring(
      category,
      note,
    );
    if (candidate == null || !mounted) return;

    final currency = context.read<SettingsController>().config.currency;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Looks recurring: $category · ${formatMoney(candidate.avgAmount, currency)}/mo',
        ),
        duration: const Duration(seconds: 6),
        action: SnackBarAction(
          label: 'Add reminder',
          onPressed: () => recurring.addBill(
            amount: candidate.avgAmount,
            category: candidate.category,
            note: candidate.note,
            dayOfMonth: candidate.dayOfMonth,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final currency = context.watch<SettingsController>().config.currency;
    return DraggableScrollableSheet(
      initialChildSize: 0.64,
      minChildSize: 0.4,
      maxChildSize: 0.92,
      expand: false,
      builder: (context, scrollController) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        return Container(
          decoration: BoxDecoration(
            color: isDark ? AppColors.surfaceDark : AppColors.surface,
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(AppRadius.lg),
            ),
          ),
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
          ),
          child: ListView(
            controller: scrollController,
            padding: const EdgeInsets.all(AppSpacing.lg),
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.border,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Add transaction',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  SegmentedButton<bool>(
                    segments: const [
                      ButtonSegment(value: true, label: Text('Quick')),
                      ButtonSegment(value: false, label: Text('Form')),
                    ],
                    selected: {_quickMode},
                    onSelectionChanged: (s) =>
                        setState(() => _quickMode = s.first),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                child: _quickMode ? _buildQuick(currency) : _buildDetailed(),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildQuick(String currency) {
    return Column(
      key: const ValueKey('quick'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _textController,
          autofocus: true,
          onChanged: _onTextChanged,
          decoration: InputDecoration(
            hintText: 'e.g. spent 500 on ola, or got salary 75000',
            suffixIcon: PressScale(
              onTap: _scanning ? null : _pickReceiptSource,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: _scanning
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(
                        Icons.document_scanner_outlined,
                        color: AppColors.primary,
                      ),
              ),
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        PressScale(
          onTap: _pickQuickDate,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.calendar_today_outlined,
                size: 14,
                color: AppColors.primary,
              ),
              const SizedBox(width: 6),
              Text(
                _quickDateOverride == null
                    ? (_preview?.date != null
                          ? 'Date: ${_preview!.date}'
                          : 'Date: Today — tap to change')
                    : 'Date: ${_isoDate(_quickDateOverride!)}',
                style: Theme.of(context).textTheme.bodySmall
                    ?.copyWith(color: AppColors.primary),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 220),
          child: _preview != null
              ? _buildPreview(currency, key: ValueKey(_preview.hashCode))
              : const SizedBox.shrink(key: ValueKey('empty')),
        ),
        const SizedBox(height: AppSpacing.lg),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: _preview?.amount != null ? _submitQuick : null,
            child: const Text('Log it'),
          ),
        ),
      ],
    );
  }

  Widget _buildPreview(String currency, {Key? key}) {
    final p = _preview!;
    if (p.amount == null) {
      return Text(
        key: key,
        "Couldn't find an amount — try e.g. \"500 ola\"",
        style: Theme.of(context).textTheme.bodySmall,
      );
    }
    final typeLabel = switch (p.type) {
      ParsedTxnType.expense => 'Expense',
      ParsedTxnType.income => 'Income',
      ParsedTxnType.lent => 'Lent to ${p.counterparty ?? 'someone'}',
      ParsedTxnType.borrowed => 'Borrowed from ${p.counterparty ?? 'someone'}',
      ParsedTxnType.repayment =>
        p.counterparty == null
            ? 'Repayment'
            : 'Repayment to/from ${p.counterparty}',
      ParsedTxnType.emiPayment => 'EMI payment',
      ParsedTxnType.emiCreate => 'Create EMI · ${p.emiMonths} months',
    };
    return Wrap(
      key: key,
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      children: [
        _previewChip(
          p.type == ParsedTxnType.emiCreate
              ? '${formatMoney(p.amount!, currency)}/mo'
              : formatMoney(p.amount!, currency),
          highlight: true,
        ),
        _previewChip(p.category),
        _previewChip(typeLabel),
        _previewChip(p.date),
        if (p.note.isNotEmpty) _previewChip(p.note),
        if (p.pendingAmount != null)
          _previewChip('${formatMoney(p.pendingAmount!, currency)} pending'),
      ],
    );
  }

  Widget _previewChip(String label, {bool highlight = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: highlight
            ? AppColors.primary.withValues(alpha: 0.14)
            : AppColors.categoryPalette.last.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontWeight: highlight ? FontWeight.w700 : FontWeight.w500,
          color: highlight ? AppColors.primary : null,
          fontSize: 13,
        ),
      ),
    );
  }

  Widget _buildDetailed() {
    final categories = [...kCategoryKeywords.keys, kDefaultCategory];
    return Column(
      key: const ValueKey('detailed'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SegmentedButton<TxnType>(
          segments: const [
            ButtonSegment(value: TxnType.expense, label: Text('Expense')),
            ButtonSegment(value: TxnType.income, label: Text('Income')),
          ],
          selected: {_type},
          onSelectionChanged: (s) => setState(() => _type = s.first),
        ),
        const SizedBox(height: AppSpacing.md),
        TextField(
          controller: _amountController,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(labelText: 'Amount'),
        ),
        const SizedBox(height: AppSpacing.md),
        if (_type == TxnType.expense)
          DropdownButtonFormField<String>(
            initialValue: _category,
            decoration: const InputDecoration(labelText: 'Category'),
            items: categories
                .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                .toList(),
            onChanged: (v) => setState(() => _category = v ?? kDefaultCategory),
          ),
        const SizedBox(height: AppSpacing.md),
        TextField(
          controller: _noteController,
          decoration: const InputDecoration(labelText: 'Note (optional)'),
        ),
        const SizedBox(height: AppSpacing.md),
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Date'),
          subtitle: Text(
            '${_date.year}-${_date.month.toString().padLeft(2, '0')}-${_date.day.toString().padLeft(2, '0')}',
          ),
          trailing: const Icon(Icons.calendar_today_outlined),
          onTap: () async {
            final picked = await showDatePicker(
              context: context,
              initialDate: _date,
              firstDate: DateTime(2020),
              lastDate: DateTime.now(),
            );
            if (picked != null) setState(() => _date = picked);
          },
        ),
        const SizedBox(height: AppSpacing.lg),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: _submitDetailed,
            child: const Text('Log it'),
          ),
        ),
      ],
    );
  }
}
