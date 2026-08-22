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
import '../../core/utils/receipt_parser.dart';
import '../../core/widgets/press_scale.dart';
import '../../data/models/transaction.dart';
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

  void _onTextChanged(String value) {
    final settings = context.read<SettingsController>();
    setState(() {
      _preview = value.trim().isEmpty
          ? null
          : parseMessage(
              value,
              extraCategories: settings.config.customCategories,
            );
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
    await _logWithWarnings(
      category: p.category,
      isExpense: p.type == ParsedTxnType.expense,
      date: p.date,
      logTxn: () => context.read<ExpensesController>().addFromParsed(p),
    );
  }

  Future<void> _submitDetailed() async {
    final amount = double.tryParse(_amountController.text.replaceAll(',', ''));
    if (amount == null || amount <= 0) return;
    final iso =
        '${_date.year.toString().padLeft(4, '0')}-${_date.month.toString().padLeft(2, '0')}-${_date.day.toString().padLeft(2, '0')}';
    await _logWithWarnings(
      category: _type == TxnType.income ? 'income' : _category,
      isExpense: _type == TxnType.expense,
      date: iso,
      logTxn: () => context.read<ExpensesController>().addManual(
        amount: amount,
        category: _type == TxnType.income ? 'income' : _category,
        note: _noteController.text.trim().isEmpty
            ? null
            : _noteController.text.trim(),
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
      }
    }

    HapticFeedback.mediumImpact();
    Navigator.of(context).pop();
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
    };
    return Wrap(
      key: key,
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      children: [
        _previewChip(formatMoney(p.amount!, currency), highlight: true),
        _previewChip(p.category),
        _previewChip(typeLabel),
        _previewChip(p.date),
        if (p.note.isNotEmpty) _previewChip(p.note),
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
