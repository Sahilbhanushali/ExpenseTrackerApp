import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme/app_spacing.dart';
import '../../core/utils/money.dart';
import '../../data/models/account.dart';

/// What the form collected. Amounts in paise.
class AccountFormResult {
  final String name;
  final String? bankName;
  final String? last4;
  final AccountType type;
  final int openingBalancePaise;
  final int? currentValuePaise;
  final Set<AccountRole> roles;
  final AccountStatus status;
  final BankType? bankType;
  final int holdPaise;

  const AccountFormResult({
    this.bankType,
    this.holdPaise = 0,
    required this.name,
    required this.bankName,
    required this.last4,
    required this.type,
    required this.openingBalancePaise,
    required this.currentValuePaise,
    required this.roles,
    required this.status,
  });
}

/// Add or edit an account. [nameTaken] rejects duplicate names inline.
Future<AccountFormResult?> showAccountForm(
  BuildContext context, {
  MoneyAccount? existing,
  required bool Function(String name) nameTaken,
}) {
  return showModalBottomSheet<AccountFormResult>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _AccountForm(existing: existing, nameTaken: nameTaken),
  );
}

class _AccountForm extends StatefulWidget {
  final MoneyAccount? existing;
  final bool Function(String name) nameTaken;
  const _AccountForm({required this.existing, required this.nameTaken});

  @override
  State<_AccountForm> createState() => _AccountFormState();
}

class _AccountFormState extends State<_AccountForm> {
  final _formKey = GlobalKey<FormState>();
  late final MoneyAccount? _a = widget.existing;
  late final _name = TextEditingController(text: _a?.name ?? '');
  late final _bank = TextEditingController(text: _a?.bankName ?? '');
  late final _last4 = TextEditingController(text: _a?.last4 ?? '');
  late final _opening = TextEditingController(
    text: _a == null ? '0' : paiseToEditString(_a.openingBalancePaise),
  );
  late final _current = TextEditingController(
    text: _a?.currentValuePaise == null
        ? ''
        : paiseToEditString(_a!.currentValuePaise!),
  );
  late AccountType _type = _a?.type ?? AccountType.cash;
  late Set<AccountRole> _roles = {
    ...(_a == null || _a.roles.isEmpty ? defaultRolesFor(_type) : _a.roles),
  };
  late bool _closed = _a?.status == AccountStatus.closed;
  late BankType? _bankType = _a?.bankType;
  late final _hold = TextEditingController(
    text: (_a?.holdPaise ?? 0) == 0 ? '' : paiseToEditString(_a!.holdPaise),
  );

  @override
  void dispose() {
    for (final c in [_name, _bank, _last4, _opening, _current, _hold]) {
      c.dispose();
    }
    super.dispose();
  }

  void _setType(AccountType t) {
    setState(() {
      // Keep the roles in step with the type unless the user changed them.
      if (_roles.length == 1 && _roles.first == defaultRolesFor(_type).first) {
        _roles = {...defaultRolesFor(t)};
      }
      _type = t;
    });
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.pop(
      context,
      AccountFormResult(
        name: _name.text.trim(),
        bankName: _bank.text.trim(),
        last4: _last4.text.trim(),
        type: _type,
        openingBalancePaise: parseRupeesToPaise(_opening.text) ?? 0,
        currentValuePaise: _type == AccountType.investment
            ? parseRupeesToPaise(_current.text)
            : null,
        roles: _roles,
        status: _closed ? AccountStatus.closed : AccountStatus.active,
        bankType: _bankType,
        holdPaise: parseRupeesToPaise(_hold.text) ?? 0,
      ),
    );
  }

  String? _amountError(String? v, {bool optional = false}) {
    final text = (v ?? '').trim();
    if (text.isEmpty) return optional ? null : 'Enter an amount (0 is fine)';
    final paise = parseRupeesToPaise(text);
    if (paise == null) return 'Enter a valid amount';
    if (paise < 0) return "Can't be negative";
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final editing = _a != null;
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
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  editing ? 'Edit account' : 'Add account',
                  style: text.titleLarge,
                ),
                const SizedBox(height: AppSpacing.md),
                TextFormField(
                  controller: _name,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    labelText: 'Display name',
                    hintText: 'e.g. Salary account',
                  ),
                  validator: (v) {
                    final name = (v ?? '').trim();
                    if (name.isEmpty) return 'Give the account a name';
                    if (name != _a?.name && widget.nameTaken(name)) {
                      return 'You already have an account with this name';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: AppSpacing.md - 4),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 3,
                      child: TextFormField(
                        controller: _bank,
                        textCapitalization: TextCapitalization.words,
                        decoration: const InputDecoration(
                          labelText: 'Bank (optional)',
                        ),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      flex: 2,
                      child: TextFormField(
                        controller: _last4,
                        keyboardType: TextInputType.number,
                        maxLength: 4,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                        ],
                        decoration: const InputDecoration(
                          labelText: 'Last 4 digits',
                          counterText: '',
                        ),
                        validator: (v) {
                          final d = (v ?? '').trim();
                          return d.isEmpty || d.length == 4
                              ? null
                              : 'Exactly 4 digits';
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.md - 4),
                SegmentedButton<AccountType>(
                  segments: const [
                    ButtonSegment(value: AccountType.cash, label: Text('Bank')),
                    ButtonSegment(
                      value: AccountType.emergencyFund,
                      label: Text('Emergency'),
                    ),
                    ButtonSegment(
                      value: AccountType.investment,
                      label: Text('Investment'),
                    ),
                  ],
                  selected: {_type},
                  onSelectionChanged: (s) => _setType(s.first),
                ),
                const SizedBox(height: AppSpacing.md),
                TextFormField(
                  controller: _opening,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: InputDecoration(
                    labelText: _type == AccountType.investment
                        ? 'Amount invested'
                        : 'Opening balance',
                    helperText: 'A starting point, not income',
                  ),
                  validator: _amountError,
                ),
                if (_type == AccountType.investment) ...[
                  const SizedBox(height: AppSpacing.md - 4),
                  TextFormField(
                    controller: _current,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'Current value (optional)',
                      helperText:
                          'As shown by your broker; leave blank if same',
                    ),
                    validator: (v) => _amountError(v, optional: true),
                  ),
                ],
                if (_type == AccountType.cash) ...[
                  const SizedBox(height: AppSpacing.md - 4),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<BankType?>(
                          initialValue: _bankType,
                          decoration: const InputDecoration(
                            labelText: 'Account type',
                          ),
                          items: [
                            const DropdownMenuItem(
                              value: null,
                              child: Text('—'),
                            ),
                            for (final t in BankType.values)
                              DropdownMenuItem(
                                value: t,
                                child: Text(bankTypeLabel(t)),
                              ),
                          ],
                          onChanged: (v) => setState(() => _bankType = v),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: TextFormField(
                          controller: _hold,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: const InputDecoration(
                            labelText: 'On hold',
                            helperText: 'Not available',
                          ),
                          validator: (v) => _amountError(v, optional: true),
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: AppSpacing.md),
                Text('Used for', style: text.titleSmall),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  'Savings, emergency and investing accounts are kept out of '
                  'spendable money.',
                  style: text.bodySmall,
                ),
                const SizedBox(height: AppSpacing.sm),
                Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.xs,
                  children: [
                    for (final r in AccountRole.values)
                      FilterChip(
                        label: Text(accountRoleLabel(r)),
                        selected: _roles.contains(r),
                        onSelected: (on) => setState(
                          () => on ? _roles.add(r) : _roles.remove(r),
                        ),
                      ),
                  ],
                ),
                if (editing) ...[
                  const SizedBox(height: AppSpacing.sm),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Account closed'),
                    subtitle: const Text(
                      'Keeps its history but hides it from pickers',
                    ),
                    value: _closed,
                    onChanged: (v) => setState(() => _closed = v),
                  ),
                ],
                const SizedBox(height: AppSpacing.lg),
                FilledButton(
                  onPressed: _submit,
                  child: Text(editing ? 'Save changes' : 'Add account'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
