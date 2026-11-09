import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../utils/money.dart';
import '../theme/app_spacing.dart';

/// The app's one pattern for entering data: a bottom sheet with a title,
/// scrolling fields that stay above the keyboard, an inline error and a
/// full-width primary button. Dialogs are kept for confirmations only.
///
/// [validate] runs when the button is tapped; a non-null message is shown
/// in the sheet (which stays open) instead of silently doing nothing.
/// Resolves to true only when the user submitted valid input.
Future<bool> showFormSheet(
  BuildContext context, {
  required Widget title,
  String? subtitle,
  required Widget Function(BuildContext context, StateSetter setState) builder,
  required String submitLabel,
  String? Function()? validate,
  bool destructive = false,
}) async {
  final result = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (sheet) => _FormSheet(
      title: title,
      subtitle: subtitle,
      builder: builder,
      submitLabel: submitLabel,
      validate: validate,
      destructive: destructive,
    ),
  );
  return result == true;
}

class _FormSheet extends StatefulWidget {
  final Widget title;
  final String? subtitle;
  final Widget Function(BuildContext, StateSetter) builder;
  final String submitLabel;
  final String? Function()? validate;
  final bool destructive;

  const _FormSheet({
    required this.title,
    required this.subtitle,
    required this.builder,
    required this.submitLabel,
    required this.validate,
    required this.destructive,
  });

  @override
  State<_FormSheet> createState() => _FormSheetState();
}

class _FormSheetState extends State<_FormSheet> {
  String? _error;

  void _submit() {
    final error = widget.validate?.call();
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final text = Theme.of(context).textTheme;
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
              DefaultTextStyle.merge(
                style: text.titleLarge,
                child: widget.title,
              ),
              if (widget.subtitle != null) ...[
                const SizedBox(height: AppSpacing.xs),
                Text(widget.subtitle!, style: text.bodySmall),
              ],
              const SizedBox(height: AppSpacing.md),
              // Rebuilding this sheet's state also rebuilds the fields, so
              // the setState handed to them refreshes everything.
              widget.builder(context, setState),
              if (_error != null) ...[
                const SizedBox(height: AppSpacing.md),
                Row(
                  children: [
                    Icon(
                      Icons.error_outline_rounded,
                      size: AppIconSize.sm,
                      color: p.expense,
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    Expanded(
                      child: Text(
                        _error!,
                        style: text.bodyMedium?.copyWith(color: p.expense),
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: AppSpacing.lg),
              FilledButton(
                style: widget.destructive
                    ? FilledButton.styleFrom(
                        backgroundColor: p.expense,
                        foregroundColor: p.onStatus,
                      )
                    : null,
                onPressed: _submit,
                child: Text(widget.submitLabel),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Shared validation messages, so every form says the same thing.
String? requireText(String value, String what) =>
    value.trim().isEmpty ? 'Enter $what.' : null;

/// Null when [text] is an amount above zero.
String? positiveAmountError(String text) {
  final paise = parseRupeesToPaise(text);
  return paise == null || paise <= 0
      ? 'Enter an amount greater than zero.'
      : null;
}
