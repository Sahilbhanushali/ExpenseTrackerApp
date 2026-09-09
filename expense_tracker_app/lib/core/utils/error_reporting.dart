import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';

/// Anything that goes wrong below the UI — a failed write, a corrupt row, a
/// denied permission — used to surface as nothing at all: the button just
/// didn't work. These hooks turn every unhandled failure into one short,
/// non-technical message instead, without every call site needing its own
/// try/catch.
///
/// Set once, at startup, before `runApp`.
void installErrorHandlers(GlobalKey<NavigatorState> navigatorKey) {
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    _report(navigatorKey, details.exception);
  };

  // Async errors that escape a Future — the common shape for a repository
  // call awaited from an onPressed with no catch.
  PlatformDispatcher.instance.onError = (error, stack) {
    _report(navigatorKey, error);
    if (kDebugMode) debugPrintStack(stackTrace: stack, label: '$error');
    return true;
  };

  // A widget that throws while building shows Flutter's grey box in release
  // and a red one in debug; neither says anything useful to the person
  // holding the phone.
  ErrorWidget.builder = (details) => _BrokenSection(details: details);
}

/// Shows a failure to the user without leaking the exception text.
///
/// ponytail: one generic message rather than per-error copy — refine only if
/// a specific failure turns out to be common enough to deserve its own line.
void showErrorSnack(BuildContext context, String message) {
  ScaffoldMessenger.maybeOf(context)?.showSnackBar(
    SnackBar(
      content: Text(message),
      backgroundColor: AppColors.expense,
      behavior: SnackBarBehavior.floating,
    ),
  );
}

void _report(GlobalKey<NavigatorState> navigatorKey, Object error) {
  if (kDebugMode) debugPrint('Unhandled: $error');
  final context = navigatorKey.currentContext;
  if (context == null) return;
  // The error may arrive mid-frame; showing a SnackBar then throws.
  WidgetsBinding.instance.addPostFrameCallback((_) {
    if (!context.mounted) return;
    showErrorSnack(context, "That didn't go through. Please try again.");
  });
}

/// Replaces one broken widget subtree, so a single bad row can't take the
/// whole screen down with it.
class _BrokenSection extends StatelessWidget {
  final FlutterErrorDetails details;

  const _BrokenSection({required this.details});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline, size: 18, color: AppColors.expense),
          const SizedBox(width: AppSpacing.xs),
          Flexible(
            child: Text(
              kDebugMode ? '${details.exception}' : "This didn't load.",
              style: const TextStyle(fontSize: 12, color: AppColors.expense),
            ),
          ),
        ],
      ),
    );
  }
}
