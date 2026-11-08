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
import '../../core/utils/money.dart';
import '../../core/utils/money_formatter.dart';
import '../../core/utils/notification_service.dart';
import '../../core/utils/receipt_parser.dart';
import '../../core/utils/sms_parser.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_chip.dart';
import '../../core/widgets/category_icon.dart';
import '../../data/models/recurring_bill.dart';
import '../../data/models/transaction.dart';
import '../accounts/accounts_controller.dart';
import '../lending/lending_controller.dart';
import '../recurring/recurring_controller.dart';
import '../settings/settings_controller.dart';
import 'expenses_controller.dart';

Future<void> showAddTransactionSheet(
  BuildContext context, {
  String? initialText,
  String? initialImagePath,
}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => AddTransactionSheet(
      initialText: initialText,
      initialImagePath: initialImagePath,
    ),
  );
}

class AddTransactionSheet extends StatefulWidget {
  /// Prefills quick-mode text — used when text is shared into the app (e.g.
  /// a UPI payment confirmation via the system share sheet) so the parsed
  /// preview is ready immediately, still pending the user's confirmation.
  final String? initialText;

  /// A receipt image shared into the app. Scanned on open, exactly as if
  /// the user had tapped "Scan receipt" and picked it.
  final String? initialImagePath;

  const AddTransactionSheet({
    super.key,
    this.initialText,
    this.initialImagePath,
  });

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
  String? _amountError;

  @override
  void initState() {
    super.initState();
    final shared = widget.initialText?.trim();
    if (shared != null && shared.isNotEmpty) {
      _textController.text = shared;
      _onTextChanged(shared);
    }
    final image = widget.initialImagePath;
    if (image != null && image.isNotEmpty) {
      // After the first frame: OCR needs a mounted context for settings.
      WidgetsBinding.instance.addPostFrameCallback((_) => _scanFile(image));
    }
  }

  @override
  void dispose() {
    _textController.dispose();
    _amountController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  String _isoDate(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  /// Payment confirmations shared in from GPay/PhonePe/a bank app are
  /// structured boilerplate, not the free-form "spent 500 on ola" the
  /// quick-add parser is built for, and read badly through it.
  ///
  /// Only takes over when the text carries a machine-generated marker — a
  /// reference number, account digits, or a named payee — so ordinary
  /// typing still goes to the free-form parser.
  ParsedTransaction? _parsePaymentConfirmation(
    String text,
    Map<String, List<String>>? extraCategories,
  ) {
    final sms = parseTransactionSms(
      text,
      extraCategories: extraCategories,
      // The user picked this text and is looking at the preview, so the
      // unattended-scanning gate doesn't apply.
      requireAccountIdentity: false,
    );
    if (sms == null) return null;
    if (sms.referenceNo == null &&
        sms.accountTail == null &&
        sms.merchant == null) {
      return null;
    }
    return ParsedTransaction(
      amountPaise: sms.amountPaise,
      category: sms.category,
      note: sms.describe,
      type: sms.direction == SmsDirection.credit
          ? ParsedTxnType.income
          : ParsedTxnType.expense,
      counterparty: null,
      date: _isoDate(sms.occurredAt),
    );
  }

  void _onTextChanged(String value) {
    final settings = context.read<SettingsController>();
    setState(() {
      if (value.trim().isEmpty) {
        _preview = null;
        return;
      }
      final extra = settings.config.customCategories;
      final parsed =
          _parsePaymentConfirmation(value, extra) ??
          parseMessage(value, extraCategories: extra);
      // A date the user explicitly picked wins over whatever the parser
      // found in the text — otherwise typing more after picking a date
      // would silently snap it back to "today".
      _preview = _quickDateOverride == null
          ? parsed
          : ParsedTransaction(
              amountPaise: parsed.amountPaise,
              category: parsed.category,
              note: parsed.note,
              type: parsed.type,
              counterparty: parsed.counterparty,
              date: _isoDate(_quickDateOverride!),
              emiMonths: parsed.emiMonths,
              pendingAmountPaise: parsed.pendingAmountPaise,
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
          amountPaise: p.amountPaise,
          category: p.category,
          note: p.note,
          type: p.type,
          counterparty: p.counterparty,
          date: _isoDate(picked),
          emiMonths: p.emiMonths,
          pendingAmountPaise: p.pendingAmountPaise,
        );
      }
    });
  }

  Future<void> _scanReceipt(ImageSource source) async {
    final picker = ImagePicker();
    final file = await picker.pickImage(source: source, imageQuality: 85);
    if (file == null || !mounted) return;
    await _scanFile(file.path);
  }

  /// Runs receipt OCR over one image file, whether the user picked it or
  /// shared it in from another app.
  Future<void> _scanFile(String path) async {
    if (!mounted) return;
    setState(() => _scanning = true);
    final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
    try {
      final result = await recognizer.processImage(
        InputImage.fromFilePath(path),
      );
      if (!mounted) return;
      final settings = context.read<SettingsController>();
      final receipt = parseReceiptText(
        result.text,
        extraCategories: settings.config.customCategories,
      );

      if (receipt.amountPaise == null) {
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
          amountPaise: receipt.amountPaise,
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
    if (_preview == null || _preview!.amountPaise == null) return;
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
    final effective = p.pendingAmountPaise == null
        ? p
        : ParsedTransaction(
            amountPaise: p.amountPaise,
            category: p.category,
            note: p.note.isEmpty
                ? '${formatMoney(p.pendingAmountPaise!, '₹')} pending'
                : '${p.note} — '
                      '${formatMoney(p.pendingAmountPaise!, '₹')} pending',
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
          amountPaise: p.amountPaise,
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
                  trailing: Text(formatMoney(b.amountPaise, '₹')),
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
      monthlyPaise: p.amountPaise!,
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
          'EMI created: ${formatMoney(p.amountPaise!, currency)}/month for ${p.emiMonths} months',
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
          amountPaise: p.amountPaise,
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

    final result = await lending.repay(target.id!, p.amountPaise!);
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
                : 'Applied to ${target.counterparty}: outstanding now '
                      '${formatMoney(result.row.amountPaise, '₹')}',
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
                  trailing: Text(formatMoney(t.amountPaise, '₹')),
                  onTap: () => Navigator.pop(context, t),
                ),
              )
              .toList(),
        ),
      ),
    );
  }

  Future<void> _submitDetailed() async {
    final amount = parseRupeesToPaise(_amountController.text);
    if (amount == null || amount <= 0) {
      HapticFeedback.heavyImpact();
      setState(
        () => _amountError = _amountController.text.trim().isEmpty
            ? 'Enter an amount'
            : 'Enter a valid amount greater than zero',
      );
      return;
    }
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
        amountPaise: amount,
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
      final budget = settings.config.monthlyBudgetPaise;
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
            backgroundColor: context.palette.expense,
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
          'Looks recurring: $category · ${formatMoney(candidate.avgAmountPaise, currency)}/mo',
        ),
        duration: const Duration(seconds: 6),
        action: SnackBarAction(
          label: 'Add reminder',
          onPressed: () => recurring.addBill(
            amountPaise: candidate.avgAmountPaise,
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
    final p = context.palette;
    return DraggableScrollableSheet(
      initialChildSize: 0.72,
      minChildSize: 0.4,
      maxChildSize: 0.94,
      expand: false,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: p.surface,
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(AppRadius.xl),
            ),
          ),
          padding: EdgeInsets.only(
            bottom: MediaQuery.viewInsetsOf(context).bottom,
          ),
          child: ListView(
            controller: scrollController,
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.page,
              AppSpacing.sm + 2,
              AppSpacing.page,
              AppSpacing.lg,
            ),
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: p.border,
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'New transaction',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  SegmentedButton<bool>(
                    showSelectedIcon: false,
                    segments: const [
                      ButtonSegment(
                        value: true,
                        icon: Icon(Icons.bolt_rounded, size: AppIconSize.sm),
                        label: Text('Quick'),
                      ),
                      ButtonSegment(
                        value: false,
                        icon: Icon(Icons.tune_rounded, size: AppIconSize.sm),
                        label: Text('Form'),
                      ),
                    ],
                    selected: {_quickMode},
                    onSelectionChanged: (s) =>
                        setState(() => _quickMode = s.first),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),
              AnimatedSwitcher(
                duration: AppDurations.of(context, AppDurations.base),
                child: _quickMode
                    ? _buildQuick(currency)
                    : _buildDetailed(currency),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildQuick(String currency) {
    final p = context.palette;
    final text = Theme.of(context).textTheme;
    final dateLabel = _quickDateOverride != null
        ? _isoDate(_quickDateOverride!)
        : (_preview?.date ?? 'Today');
    return Column(
      key: const ValueKey('quick'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Type it like a message — amount, what for, and when.',
          style: text.bodySmall,
        ),
        const SizedBox(height: AppSpacing.sm + 2),
        TextField(
          controller: _textController,
          autofocus: true,
          onChanged: _onTextChanged,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) {
            if (_preview?.amountPaise != null) _submitQuick();
          },
          decoration: InputDecoration(
            hintText: 'e.g. spent 500 on ola, or got salary 75000',
            prefixIcon: const Icon(Icons.edit_note_rounded),
            suffixIcon: _scanning
                ? const Padding(
                    padding: EdgeInsets.all(AppSpacing.md - 2),
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : IconButton(
                    tooltip: 'Scan receipt',
                    onPressed: _pickReceiptSource,
                    icon: Icon(
                      Icons.document_scanner_outlined,
                      color: p.savings,
                    ),
                  ),
          ),
        ),
        const SizedBox(height: AppSpacing.sm + 2),
        Align(
          alignment: Alignment.centerLeft,
          child: AppChoiceChip(
            icon: Icons.calendar_today_rounded,
            label: dateLabel,
            selected: _quickDateOverride != null,
            onTap: _pickQuickDate,
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        AnimatedSize(
          duration: AppDurations.of(context, AppDurations.base),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: AnimatedSwitcher(
            duration: AppDurations.of(context, AppDurations.base),
            child: _preview != null
                ? _buildPreview(currency, key: ValueKey(_preview.hashCode))
                : const SizedBox(
                    width: double.infinity,
                    key: ValueKey('empty'),
                  ),
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        FilledButton.icon(
          onPressed: _preview?.amountPaise != null ? _submitQuick : null,
          icon: const Icon(Icons.check_rounded),
          label: const Text('Log it'),
        ),
      ],
    );
  }

  Widget _buildPreview(String currency, {Key? key}) {
    final p = _preview!;
    final palette = context.palette;
    final text = Theme.of(context).textTheme;
    if (p.amountPaise == null) {
      return Container(
        key: key,
        padding: const EdgeInsets.all(AppSpacing.md - 4),
        decoration: BoxDecoration(
          color: palette.warning.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
        child: Row(
          children: [
            Icon(Icons.info_outline_rounded, color: palette.warning),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                "Couldn't find an amount — try e.g. \"500 ola\"",
                style: text.bodySmall?.copyWith(color: palette.textPrimary),
              ),
            ),
          ],
        ),
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
    final isIncome = p.type == ParsedTxnType.income;
    final amount = p.type == ParsedTxnType.emiCreate
        ? '${formatMoney(p.amountPaise!, currency)}/mo'
        : formatMoney(p.amountPaise!, currency);
    return Container(
      key: key,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: palette.surfaceAlt,
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CategoryIcon(
                category: isIncome ? 'income' : p.category,
                color: isIncome ? palette.income : null,
              ),
              const SizedBox(width: AppSpacing.md - 4),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      p.note.isNotEmpty ? p.note : p.category,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: text.bodyLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text('$typeLabel · ${p.category}', style: text.bodySmall),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Text(
                '${isIncome ? '+' : ''}$amount',
                style: text.moneyStyle(
                  18,
                  color: isIncome ? palette.income : null,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm + 2),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              _previewChip(Icons.calendar_today_rounded, p.date),
              if (p.pendingAmountPaise != null)
                _previewChip(
                  Icons.hourglass_bottom_rounded,
                  '${formatMoney(p.pendingAmountPaise!, currency)} pending',
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _previewChip(IconData icon, String label) {
    final p = context.palette;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm + 2,
        vertical: AppSpacing.xs + 2,
      ),
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: BorderRadius.circular(AppRadius.pill),
        border: Border.all(color: p.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: p.textSecondary),
          const SizedBox(width: AppSpacing.xs + 2),
          Text(label, style: Theme.of(context).textTheme.labelMedium),
        ],
      ),
    );
  }

  Widget _buildDetailed(String currency) {
    final p = context.palette;
    final text = Theme.of(context).textTheme;
    final categories = [...kCategoryKeywords.keys, kDefaultCategory];
    final isIncome = _type == TxnType.income;
    final accent = isIncome ? p.income : p.expense;
    return Column(
      key: const ValueKey('detailed'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SegmentedButton<TxnType>(
          showSelectedIcon: false,
          segments: const [
            ButtonSegment(
              value: TxnType.expense,
              icon: Icon(Icons.north_east_rounded, size: AppIconSize.sm),
              label: Text('Expense'),
            ),
            ButtonSegment(
              value: TxnType.income,
              icon: Icon(Icons.south_west_rounded, size: AppIconSize.sm),
              label: Text('Income'),
            ),
          ],
          selected: {_type},
          onSelectionChanged: (s) => setState(() => _type = s.first),
        ),
        const SizedBox(height: AppSpacing.lg),
        Text('Amount', textAlign: TextAlign.center, style: text.labelMedium),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(currency, style: text.moneyStyle(32, color: p.textTertiary)),
            const SizedBox(width: AppSpacing.xs),
            Flexible(
              child: IntrinsicWidth(
                child: TextField(
                  controller: _amountController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                  ],
                  textAlign: TextAlign.center,
                  onChanged: (_) {
                    if (_amountError != null) {
                      setState(() => _amountError = null);
                    }
                  },
                  style: text.moneyStyle(
                    44,
                    color: accent,
                    weight: FontWeight.w800,
                  ),
                  decoration: InputDecoration(
                    hintText: '0',
                    hintStyle: text.moneyStyle(44, color: p.border),
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    filled: false,
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              ),
            ),
          ],
        ),
        AnimatedSwitcher(
          duration: AppDurations.of(context, AppDurations.fast),
          child: _amountError == null
              ? const SizedBox(height: AppSpacing.md)
              : Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.xs),
                  child: Text(
                    _amountError!,
                    textAlign: TextAlign.center,
                    style: text.bodySmall?.copyWith(color: p.expense),
                  ),
                ),
        ),
        const SizedBox(height: AppSpacing.md),
        if (_type == TxnType.expense) ...[
          Text('Category', style: text.titleSmall),
          const SizedBox(height: AppSpacing.sm),
          LayoutBuilder(
            builder: (context, c) {
              final columns = (c.maxWidth / 84).floor().clamp(4, 8);
              final w = (c.maxWidth - AppSpacing.sm * (columns - 1)) / columns;
              return Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: [
                  for (final cat in categories)
                    SizedBox(
                      width: w,
                      child: _CategoryOption(
                        category: cat,
                        selected: _category == cat,
                        onTap: () => setState(() => _category = cat),
                      ),
                    ),
                ],
              );
            },
          ),
          const SizedBox(height: AppSpacing.lg),
        ],
        TextField(
          controller: _noteController,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(
            labelText: 'Note (optional)',
            prefixIcon: Icon(Icons.notes_rounded),
          ),
        ),
        const SizedBox(height: AppSpacing.sm + 2),
        Material(
          color: p.surfaceAlt,
          borderRadius: BorderRadius.circular(AppRadius.md),
          child: InkWell(
            borderRadius: BorderRadius.circular(AppRadius.md),
            onTap: () async {
              final picked = await showDatePicker(
                context: context,
                initialDate: _date,
                firstDate: DateTime(2020),
                lastDate: DateTime.now(),
              );
              if (picked != null) setState(() => _date = picked);
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md - 4,
                vertical: AppSpacing.md - 2,
              ),
              child: Row(
                children: [
                  Icon(Icons.calendar_today_rounded, color: p.textSecondary),
                  const SizedBox(width: AppSpacing.md - 4),
                  Expanded(child: Text(_isoDate(_date), style: text.bodyLarge)),
                  Text(
                    'Change',
                    style: text.labelMedium?.copyWith(color: p.savings),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        FilledButton.icon(
          onPressed: _submitDetailed,
          icon: const Icon(Icons.check_rounded),
          label: Text(isIncome ? 'Log income' : 'Log expense'),
        ),
      ],
    );
  }
}

class _CategoryOption extends StatelessWidget {
  final String category;
  final bool selected;
  final VoidCallback onTap;

  const _CategoryOption({
    required this.category,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final color = CategoryStyle.of(category).color;
    return Semantics(
      button: true,
      selected: selected,
      label: category,
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: AnimatedContainer(
          duration: AppDurations.of(context, AppDurations.fast),
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm + 2),
          decoration: BoxDecoration(
            color: selected
                ? color.withValues(alpha: 0.12)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(
              color: selected ? color : p.border,
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Column(
            children: [
              CategoryIcon(category: category, size: 36, solid: selected),
              const SizedBox(height: AppSpacing.xs + 2),
              Text(
                category,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: selected ? p.textPrimary : p.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
