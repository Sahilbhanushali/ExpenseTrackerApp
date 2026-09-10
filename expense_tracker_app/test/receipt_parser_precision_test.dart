import 'package:flutter_test/flutter_test.dart';

import 'package:expense_tracker_app/core/utils/receipt_parser.dart';

/// Receipts are the least structured input the app takes, and the old
/// parser — "first line containing 'total', else the largest number
/// anywhere" — got every one of these wrong.
void main() {
  test('takes the grand total, not the subtotal above it', () {
    final r = parseReceiptText('''
THE WAFFLE WINGS
Shop 12, Station Road, Vapi
GSTIN 24ABCDE1234F1Z5
1 x Belgian Waffle    120.00
2 x Cold Coffee       180.00
Sub Total             300.00
CGST 2.5%               7.50
SGST 2.5%               7.50
Grand Total           315.00
''');

    expect(r.amountPaise, 31500);
    expect(r.category, 'food');
    expect(r.note, 'THE WAFFLE WINGS');
  });

  test('takes the final total, not a running "Item Total"', () {
    // Stopping at the first line containing "total" logged the
    // pre-delivery figure and quietly under-counted every order.
    final r = parseReceiptText('''
Blinkit
Order ID ORD72093038024
Milk 1L            62.00
Item Total        175.00
Delivery           15.00
TOTAL             190.00
''');

    expect(r.amountPaise, 19000);
    expect(r.category, 'groceries');
  });

  test('never mistakes a transaction id for an amount', () {
    // This used to log a ₹6,19,05,72,60,304 lunch.
    final r = parseReceiptText('''
₹560
Paid
To Cp Shah And Sons Vapi
9 Sep 2026, 6:43 pm
UPI transaction ID 619057260304
From HDFC Bank ••1234
''');

    expect(r.amountPaise, 56000);
    expect(r.note, 'Cp Shah And Sons Vapi');
  });

  test('"9.57 L" on a fuel bill is litres, not 9.57 lakh', () {
    final r = parseReceiptText('''
HP PETROL PUMP
Rate/Ltr : 104.50
Volume   : 9.57 L
Amount   : 1000.00
''');

    expect(r.amountPaise, 100000);
  });

  test('a receipt with no numbers at all yields no amount', () {
    final r = parseReceiptText('THANK YOU\nVISIT AGAIN');
    expect(r.amountPaise, isNull);
  });

  test('the note skips status words in favour of the payee', () {
    final r = parseReceiptText('Paid\n₹250\nSwiggy Instamart\n');
    expect(r.note, 'Swiggy Instamart');
  });
}
