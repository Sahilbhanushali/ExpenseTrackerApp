import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:expense_tracker_app/core/theme/app_colors.dart';

/// Every foreground/background pairing the UI relies on, in both themes.
/// Text needs 4.5:1 (WCAG AA); icons and large figures 3:1.
void main() {
  for (final (name, p) in [
    ('light', AppPalette.light),
    ('dark', AppPalette.dark),
  ]) {
    group('$name palette', () {
      void pair(String label, Color fg, Color bg, [double min = 4.5]) {
        final r = contrastRatio(fg, bg);
        expect(
          r,
          greaterThanOrEqualTo(min),
          reason: '$label is ${r.toStringAsFixed(2)}:1',
        );
      }

      test('text on surfaces', () {
        for (final bg in [p.surface, p.background, p.surfaceAlt]) {
          pair('textPrimary', p.textPrimary, bg);
          pair('textSecondary', p.textSecondary, bg);
          pair('textTertiary (hints)', p.textTertiary, bg, 4.3);
        }
      });

      test('status colours on cards', () {
        for (final (label, c) in [
          ('income', p.income),
          ('expense', p.expense),
          ('warning', p.warning),
          ('debt', p.debt),
        ]) {
          pair(label, c, p.surface);
        }
        pair('savings', p.savings, p.surface, 4.4);
      });

      test('everything drawn on the ink surface', () {
        for (final (label, c) in [
          ('onInk', p.onInk),
          ('onInkMuted', p.onInkMuted),
          ('inkIncome', p.inkIncome),
          ('inkWarning', p.inkWarning),
          ('inkExpense', p.inkExpense),
          ('inkAccent', p.inkAccent),
        ]) {
          pair(label, c, p.inkSurface);
        }
      });

      test('actions and solid status fills', () {
        pair('onAction', p.onAction, p.action);
        for (final (label, c) in [
          ('expense', p.expense),
          ('income', p.income),
          ('warning', p.warning),
        ]) {
          pair('onStatus on $label', p.onStatus, c);
        }
      });

      test('every category icon is legible on its tint', () {
        final dark = identical(p, AppPalette.dark);
        for (final c in AppColors.categoryPalette) {
          final bg = Color.alphaBlend(
            c.withValues(alpha: dark ? 0.22 : 0.12),
            p.surface,
          );
          pair('category glyph', ensureContrast(c, bg, min: 3), bg, 3);
          pair('solid glyph', bestOn(c), c, 3);
        }
      });
    });
  }
}
