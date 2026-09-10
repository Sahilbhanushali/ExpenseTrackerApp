import 'package:flutter_test/flutter_test.dart';

import 'package:expense_tracker_app/core/utils/sms_parser.dart';

/// An auto-logged row is one the user never typed, so the note has to say
/// where it came from. "Auto-detected" told them nothing.
void main() {
  ParsedSms parse(String sender, String body) => parseTransactionSms(
    body,
    sender: sender,
    receivedAt: DateTime(2026, 9, 9),
  )!;

  test('names the payee, the bank and the account', () {
    final r = parse(
      'VM-HDFCBK',
      'Rs.500.00 debited from A/c XX1234 on 09-09-26 to VPA swiggy@ybl. '
          'UPI Ref 123456789012',
    );

    expect(r.bank, 'HDFC Bank');
    expect(r.describe, 'swiggy@ybl · HDFC Bank ••1234');
  });

  test('falls back to bank and account when no payee is named', () {
    final r = parse(
      'JK-BOBSMS-S',
      'Dear BOB UPI User: Your account is credited with INR 5000.00 on '
          '2026-07-09 by UPI Ref No 619057260304; AvlBal: Rs5002.90 - BOB',
    );

    expect(r.bank, 'Bank of Baroda');
    expect(r.describe, contains('Bank of Baroda'));
  });

  test('an unknown sender leaves the bank unnamed rather than guessing', () {
    final r = parse(
      'ZZ-WHOKNW',
      'Rs.150 paid to zomato@ybl via UPI. UTR 334455667788',
    );

    expect(r.bank, isNull);
    expect(r.describe, 'zomato@ybl');
  });

  test('bankFromSender reads the middle token of a telco header', () {
    expect(bankFromSender('VM-HDFCBK-S'), 'HDFC Bank');
    expect(bankFromSender('AD-ICICIB'), 'ICICI Bank');
    expect(bankFromSender('JD-SLICEIT'), 'slice');
    expect(bankFromSender('9876543210'), isNull);
    expect(bankFromSender(null), isNull);
  });

  group('text shared in from a payment app', () {
    test('parses without account digits, which a share rarely carries', () {
      // Unattended inbox scanning demands an account identity; text the
      // user deliberately shared and is previewing does not.
      final r = parseTransactionSms(
        'You paid Rs.560 to Cp Shah And Sons. UPI transaction ID 4567890123',
        requireAccountIdentity: false,
      );

      expect(r, isNotNull);
      expect(r!.amountPaise, 56000);
      expect(r.direction, SmsDirection.debit);
      expect(r.merchant, 'Cp Shah And Sons');
    });

    test('the same text is still refused for unattended scanning', () {
      expect(
        parseTransactionSms(
          'You paid Rs.560 to Cp Shah And Sons. UPI transaction ID 4567890123',
          sender: 'VM-HDFCBK',
        ),
        isNotNull,
        reason: 'mentions UPI, so it clears the rail check',
      );
      expect(
        parseTransactionSms('You paid Rs.560 to Cp Shah And Sons'),
        isNull,
        reason: 'no account, no rail, no reference',
      );
    });
  });
}
