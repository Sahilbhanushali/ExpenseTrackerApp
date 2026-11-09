import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/constants/calendar.dart';
import '../../core/finance/salary_cycle.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/utils/money.dart';
import '../../data/models/account.dart';
import '../../data/repositories/cycle_repository.dart';
import '../accounts/accounts_controller.dart';
import 'cycle_controller.dart';

Future<void> showRecordSalarySheet(BuildContext context) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => const _RecordSalarySheet(),
    );

Future<void> showSalaryProfileSheet(BuildContext context) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => const _ProfileSheet(),
    );

/// Shared frame: keyboard-aware, scrollable, page gutters.
class _Sheet extends StatelessWidget {
  final List<Widget> children;
  const _Sheet({required this.children});

  @override
  Widget build(BuildContext context) => Padding(
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
          children: children,
        ),
      ),
    ),
  );
}

class _RecordSalarySheet extends StatefulWidget {
  const _RecordSalarySheet();

  @override
  State<_RecordSalarySheet> createState() => _RecordSalarySheetState();
}

class _RecordSalarySheetState extends State<_RecordSalarySheet> {
  final _formKey = GlobalKey<FormState>();
  late final _amount = TextEditingController(
    text: switch (context.read<CycleController>().profile.expectedNetPaise) {
      final p? => paiseToEditString(p),
      null => '',
    },
  );
  final _note = TextEditingController();
  DateTime _date = dateOnly(DateTime.now());
  String? _account;
  bool _inBalance = false;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final accounts = context.read<AccountsController>().active;
    final names = accounts.map((a) => a.account.name).toSet();
    final preferred = context.read<CycleController>().profile.account;
    _account = names.contains(preferred)
        ? preferred
        : accounts
                  .where((a) => a.account.roles.contains(AccountRole.salary))
                  .firstOrNull
                  ?.account
                  .name ??
              accounts
                  .where((a) => a.account.isDefault)
                  .firstOrNull
                  ?.account
                  .name ??
              accounts.firstOrNull?.account.name;
  }

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(now.year - 2),
      lastDate: now,
      helpText: 'Date salary was credited',
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await context.read<CycleController>().recordSalary(
        amountPaise: parseRupeesToPaise(_amount.text)!,
        date: _date,
        account: _account,
        alreadyInBalance: _inBalance,
        note: _note.text.trim(),
      );
      if (!mounted) return;
      await context.read<AccountsController>().refresh();
      if (mounted) Navigator.pop(context);
    } on CycleException catch (e) {
      setState(() {
        _saving = false;
        _error = e.message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final accounts = context.watch<AccountsController>().active;
    return Form(
      key: _formKey,
      child: _Sheet(
        children: [
          Text('Record salary received', style: text.titleLarge),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'The date it reached your account starts a new salary cycle.',
            style: text.bodySmall,
          ),
          const SizedBox(height: AppSpacing.md),
          TextFormField(
            controller: _amount,
            autofocus: _amount.text.isEmpty,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'Amount credited',
              helperText: 'What actually arrived, after deductions',
            ),
            validator: (v) {
              final p = parseRupeesToPaise(v ?? '');
              return p == null || p <= 0 ? 'Enter the amount received' : null;
            },
          ),
          const SizedBox(height: AppSpacing.md - 4),
          InkWell(
            borderRadius: BorderRadius.circular(AppRadius.md),
            onTap: _pickDate,
            child: InputDecorator(
              decoration: const InputDecoration(
                labelText: 'Date credited',
                suffixIcon: Icon(Icons.calendar_today_rounded),
              ),
              child: Text(
                '${_date.day} ${kMonthNames[_date.month - 1]} ${_date.year}',
              ),
            ),
          ),
          if (accounts.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.md - 4),
            DropdownButtonFormField<String>(
              initialValue: _account,
              decoration: const InputDecoration(labelText: 'Credited to'),
              items: [
                for (final a in accounts)
                  DropdownMenuItem(
                    value: a.account.name,
                    child: Text(a.account.name),
                  ),
              ],
              onChanged: (v) => setState(() => _account = v),
            ),
          ],
          const SizedBox(height: AppSpacing.sm),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _inBalance,
            onChanged: (v) => setState(() => _inBalance = v),
            title: const Text('Already in my opening balance'),
            subtitle: const Text(
              'Turn on if you set this account’s opening balance after the '
              'salary arrived. It then counts for the cycle but isn’t added '
              'to the balance a second time.',
            ),
          ),
          TextField(
            controller: _note,
            decoration: const InputDecoration(labelText: 'Note (optional)'),
          ),
          if (_error != null) ...[
            const SizedBox(height: AppSpacing.md),
            Text(
              _error!,
              style: text.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.error,
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.lg),
          FilledButton(
            onPressed: _saving ? null : _save,
            child: const Text('Record salary'),
          ),
        ],
      ),
    );
  }
}

class _ProfileSheet extends StatefulWidget {
  const _ProfileSheet();

  @override
  State<_ProfileSheet> createState() => _ProfileSheetState();
}

class _ProfileSheetState extends State<_ProfileSheet> {
  final _formKey = GlobalKey<FormState>();
  late final SalaryProfile _p = context.read<CycleController>().profile;
  late final _ctc = _money(_p.ctcAnnualPaise);
  late final _gross = _money(_p.grossMonthlyPaise);
  late final _net = _money(_p.expectedNetPaise);
  late int _from = _p.dayFrom;
  late int _to = _p.dayTo;
  late String? _account = _p.account;
  String? _error;

  static TextEditingController _money(int? paise) => TextEditingController(
    text: paise == null ? '' : paiseToEditString(paise),
  );

  @override
  void dispose() {
    _ctc.dispose();
    _gross.dispose();
    _net.dispose();
    super.dispose();
  }

  String? _optionalAmount(String? v) {
    final t = (v ?? '').trim();
    if (t.isEmpty) return null;
    final p = parseRupeesToPaise(t);
    return p == null || p < 0 ? 'Enter a valid amount' : null;
  }

  int? _paise(TextEditingController c) =>
      c.text.trim().isEmpty ? null : parseRupeesToPaise(c.text);

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    try {
      await context.read<CycleController>().saveProfile(
        SalaryProfile(
          ctcAnnualPaise: _paise(_ctc),
          grossMonthlyPaise: _paise(_gross),
          expectedNetPaise: _paise(_net),
          dayFrom: _from,
          dayTo: _to,
          account: _account,
        ),
      );
      if (mounted) Navigator.pop(context);
    } on CycleException catch (e) {
      setState(() => _error = e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final accounts = context.watch<AccountsController>().active;
    final names = accounts.map((a) => a.account.name).toList();
    DropdownButtonFormField<int> day(
      String label,
      int value,
      ValueChanged<int> onChanged,
    ) => DropdownButtonFormField<int>(
      initialValue: value,
      decoration: InputDecoration(labelText: label),
      items: [
        for (var d = 1; d <= 31; d++)
          DropdownMenuItem(value: d, child: Text('$d')),
      ],
      onChanged: (v) => onChanged(v ?? value),
    );

    return Form(
      key: _formKey,
      child: _Sheet(
        children: [
          Text('Salary details', style: text.titleLarge),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'For reference and planning. Only salary you record as received '
            'counts as money you have.',
            style: text.bodySmall,
          ),
          const SizedBox(height: AppSpacing.md),
          TextFormField(
            controller: _ctc,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'CTC per year (optional)',
              helperText: 'Cost to company, not what you take home',
            ),
            validator: _optionalAmount,
          ),
          const SizedBox(height: AppSpacing.md - 4),
          TextFormField(
            controller: _gross,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Gross per month (optional)',
            ),
            validator: _optionalAmount,
          ),
          const SizedBox(height: AppSpacing.md - 4),
          TextFormField(
            controller: _net,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Expected take-home per month',
              helperText: 'Shown as expected, never as received',
            ),
            validator: _optionalAmount,
          ),
          const SizedBox(height: AppSpacing.md),
          Text('Salary usually arrives between', style: text.titleSmall),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              Expanded(
                child: day('From day', _from, (v) => setState(() => _from = v)),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: day('To day', _to, (v) => setState(() => _to = v)),
              ),
            ],
          ),
          if (names.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.md - 4),
            DropdownButtonFormField<String>(
              initialValue: names.contains(_account) ? _account : null,
              decoration: const InputDecoration(
                labelText: 'Usually credited to',
              ),
              items: [
                for (final n in names)
                  DropdownMenuItem(value: n, child: Text(n)),
              ],
              onChanged: (v) => setState(() => _account = v),
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: AppSpacing.md),
            Text(
              _error!,
              style: text.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.error,
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.lg),
          FilledButton(onPressed: _save, child: const Text('Save')),
        ],
      ),
    );
  }
}
