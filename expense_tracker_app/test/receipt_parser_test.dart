import 'package:expense_tracker_app/core/utils/receipt_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('parseReceiptText', () {
    test('prefers a line saying total over subtotal', () {
      final r = parseReceiptText('''
Big Bazaar
Milk 40
Bread 35
Subtotal 75
Tax 5
Total 80
''');
      expect(r.amount, 80);
    });

    test('falls back to the largest number when no total line exists', () {
      final r = parseReceiptText('''
Cafe Coffee Day
Latte 180
Sandwich 220
''');
      expect(r.amount, 220);
    });

    test('detects category from full receipt text', () {
      final r = parseReceiptText('''
Blinkit
Milk 40
Vegetables 60
Total 100
''');
      expect(r.category, 'groceries');
    });

    test('note is the first line, truncated to 40 chars', () {
      final r = parseReceiptText('This Is A Very Long First Line That Goes On And On\nTotal 50');
      expect(r.note.length, lessThanOrEqualTo(40));
    });

    test('no amount found on empty text', () {
      final r = parseReceiptText('');
      expect(r.amount, isNull);
    });
  });
}
