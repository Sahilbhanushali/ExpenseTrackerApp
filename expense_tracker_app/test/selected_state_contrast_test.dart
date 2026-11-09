import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:expense_tracker_app/core/theme/app_colors.dart';
import 'package:expense_tracker_app/core/theme/app_theme.dart';

/// Selected chips and segments sit on the action colour; their labels used
/// to keep the normal text colour and disappear into it (Add account roles).
void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  Color labelColor(WidgetTester tester, Finder within, String label) {
    final rich = tester.widget<RichText>(
      find.descendant(of: within, matching: find.byType(RichText)).first,
    );
    final style = rich.text.style;
    if (style?.color != null) return style!.color!;
    return (rich.text as TextSpan).children!.first.style!.color!;
  }

  for (final (name, theme, p) in [
    ('light', AppTheme.light, AppPalette.light),
    ('dark', AppTheme.dark, AppPalette.dark),
  ]) {
    testWidgets('$name: selected chips and segments stay readable', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: theme(),
          home: Scaffold(
            body: Column(
              children: [
                FilterChip(
                  key: const Key('on'),
                  label: const Text('Salary'),
                  selected: true,
                  onSelected: (_) {},
                ),
                FilterChip(
                  key: const Key('off'),
                  label: const Text('Savings'),
                  selected: false,
                  onSelected: (_) {},
                ),
                ChoiceChip(
                  key: const Key('choice'),
                  label: const Text('Mar'),
                  selected: true,
                  onSelected: (_) {},
                ),
                SegmentedButton<int>(
                  key: const Key('seg'),
                  segments: const [
                    ButtonSegment(value: 0, label: Text('Bank')),
                    ButtonSegment(value: 1, label: Text('Emergency')),
                  ],
                  selected: const {0},
                  onSelectionChanged: (_) {},
                ),
              ],
            ),
          ),
        ),
      );

      void check(String key, String label, Color bg) {
        final c = labelColor(tester, find.byKey(Key(key)), label);
        final ratio = contrastRatio(Color.alphaBlend(c, bg), bg);
        expect(
          ratio,
          greaterThanOrEqualTo(4.5),
          reason: '$key label is ${ratio.toStringAsFixed(2)}:1',
        );
      }

      check('on', 'Salary', p.action);
      check('off', 'Savings', p.surface);
      check('choice', 'Mar', p.action);
      check('seg', 'Bank', p.action);
    });
  }
}
