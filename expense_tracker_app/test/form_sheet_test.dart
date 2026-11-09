import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:expense_tracker_app/core/theme/app_theme.dart';
import 'package:expense_tracker_app/core/widgets/form_sheet.dart';

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  testWidgets('invalid input keeps the sheet open with a message', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 1.5;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    final amount = TextEditingController();
    bool? submitted;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async => submitted = await showFormSheet(
                context,
                title: const Text('Add to wishlist'),
                submitLabel: 'Add',
                validate: () => positiveAmountError(amount.text),
                builder: (context, setState) => TextField(controller: amount),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();
    expect(find.text('Enter an amount greater than zero.'), findsOneWidget);
    expect(submitted, isNull);

    await tester.enterText(find.byType(TextField), '250');
    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();
    expect(submitted, isTrue);
    expect(find.text('Add to wishlist'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  test('shared validators', () {
    expect(positiveAmountError('0'), isNotNull);
    expect(positiveAmountError('abc'), isNotNull);
    expect(positiveAmountError('19,000'), isNull);
    expect(requireText('  ', 'a name'), 'Enter a name.');
  });
}
