import 'package:flutter_test/flutter_test.dart';

import 'package:expense_tracker_app/core/utils/money.dart';
import 'package:expense_tracker_app/core/utils/money_formatter.dart';

void main() {
  group('parseRupeesToPaise', () {
    test('accepts the shapes people actually type', () {
      expect(parseRupeesToPaise('1250.50'), 125050);
      expect(parseRupeesToPaise('1,250.50'), 125050);
      expect(parseRupeesToPaise('₹1250.5'), 125050);
      expect(parseRupeesToPaise('  1250 '), 125000);
      expect(parseRupeesToPaise('9737.39'), 973739);
    });

    test('rejects junk instead of storing a wrong number', () {
      expect(parseRupeesToPaise(null), isNull);
      expect(parseRupeesToPaise(''), isNull);
      expect(parseRupeesToPaise('₹'), isNull);
      expect(parseRupeesToPaise('abc'), isNull);
    });
  });

  test('paiseToEditString round-trips through parseRupeesToPaise', () {
    for (final paise in [0, 5, 50, 100, 125050, 973739, 5579200]) {
      expect(parseRupeesToPaise(paiseToEditString(paise)), paise);
    }
    // Whole rupees prefill without a noisy ".00".
    expect(paiseToEditString(125000), '1250');
    expect(paiseToEditString(973739), '9737.39');
  });

  group('formatMoney', () {
    test('groups Indian-style and keeps non-zero paise', () {
      expect(formatMoney(973739, '₹'), '₹9,737.39');
      expect(formatMoney(123456789, '₹'), '₹12,34,567.89');
      expect(formatMoney(125000, '₹'), '₹1,250');
      expect(formatMoney(5, '₹'), '₹0.05');
      expect(formatMoney(0, '₹'), '₹0');
    });

    test('negatives keep the sign outside the symbol', () {
      expect(formatMoney(-973739, '₹'), '-₹9,737.39');
    });

    test('alwaysShowPaise pads whole rupees', () {
      expect(formatMoney(125000, '₹', alwaysShowPaise: true), '₹1,250.00');
    });
  });

  test('formatMoneyCompact abbreviates at Indian scales', () {
    expect(formatMoneyCompact(95000, '₹'), '₹950');
    expect(formatMoneyCompact(4530000, '₹'), '₹45.3K');
    expect(formatMoneyCompact(12000000, '₹'), '₹1.2L');
    expect(formatMoneyCompact(-12000000, '₹'), '-₹1.2L');
  });

  group('splitPaiseEvenly', () {
    test('parts always add back up to the original', () {
      for (final (paise, count) in [(100, 3), (973739, 6), (1, 4), (0, 3)]) {
        final parts = splitPaiseEvenly(paise, count);
        expect(parts, hasLength(count));
        expect(parts.reduce((a, b) => a + b), paise, reason: '$paise / $count');
      }
    });

    test('negative amounts split without inventing money', () {
      final parts = splitPaiseEvenly(-100, 3);
      expect(parts.reduce((a, b) => a + b), -100);
    });

    test(
      'a non-positive count yields nothing rather than dividing by zero',
      () {
        expect(splitPaiseEvenly(100, 0), isEmpty);
      },
    );
  });
}
