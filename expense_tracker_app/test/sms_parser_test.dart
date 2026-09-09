import 'package:flutter_test/flutter_test.dart';

import 'package:expense_tracker_app/core/utils/sms_parser.dart';

void main() {
  group('rejects non-transactional messages', () {
    test('OTP that also quotes an amount', () {
      expect(
        parseTransactionSms(
          'Your OTP for transaction of Rs 5000 at AMAZON is 123456. '
          'Do not share it with anyone. -HDFC Bank',
          sender: 'VM-HDFCBK',
        ),
        isNull,
      );
    });

    test('promotional offer phrased like a spend', () {
      expect(
        parseTransactionSms(
          'Spend Rs 5000 on your HDFC Credit Card and get 10% cashback! '
          'Offer valid till 30-09-26. T&C apply.',
          sender: 'VM-HDFCBK',
        ),
        isNull,
      );
    });

    test('failed transaction', () {
      expect(
        parseTransactionSms(
          'Transaction of Rs 2,000.00 on A/c XX1234 failed due to '
          'insufficient balance. -SBI',
          sender: 'AD-SBIBNK',
        ),
        isNull,
      );
    });

    test('balance enquiry with no money movement', () {
      expect(
        parseTransactionSms(
          'Available balance in A/c XX1234 is Rs 15,000.00 as on 09-09-26',
          sender: 'VM-HDFCBK',
        ),
        isNull,
      );
    });

    test('payment reminder (money has not moved yet)', () {
      expect(
        parseTransactionSms(
          'Your credit card bill of Rs 12,749.00 is due on 15-09-26. '
          'Minimum amount due Rs 1,200.00',
          sender: 'VM-HDFCBK',
        ),
        isNull,
      );
    });

    test('message with no amount at all', () {
      expect(
        parseTransactionSms(
          'Your account has been debited.',
          sender: 'VM-HDFC',
        ),
        isNull,
      );
    });
  });

  group('debit messages', () {
    test('UPI debit with VPA, reference and stated date', () {
      final r = parseTransactionSms(
        'Rs.500.00 debited from A/c XX1234 on 09-09-26 to VPA swiggy@ybl. '
        'UPI Ref 123456789012. -HDFC Bank',
        sender: 'VM-HDFCBK',
      );

      expect(r, isNotNull);
      expect(r!.amountPaise, 50000);
      expect(r.direction, SmsDirection.debit);
      expect(r.accountTail, '1234');
      expect(r.referenceNo, '123456789012');
      expect(r.merchant, 'swiggy@ybl');
      expect(r.occurredAt, DateTime(2026, 9, 9));
      // swiggy is a known food keyword
      expect(r.category, 'food');
      expect(r.isAutoLoggable, isTrue);
    });

    test('card spend with comma-grouped amount', () {
      final r = parseTransactionSms(
        'INR 1,250.50 spent on HDFC Bank Card x1234 at AMAZON on 09-09-26. '
        'Txn ID 998877665544',
        sender: 'VM-HDFCBK',
      );

      expect(r, isNotNull);
      expect(r!.amountPaise, 125050);
      expect(r.direction, SmsDirection.debit);
      expect(r.merchant, 'AMAZON');
    });

    test('trailing-currency format', () {
      final r = parseTransactionSms(
        '2,000.00 INR withdrawn from A/c XX9876 on 08-09-26 ref 5544332211',
        sender: 'AD-ICICIB',
      );

      expect(r, isNotNull);
      expect(r!.amountPaise, 200000);
      expect(r.direction, SmsDirection.debit);
    });
  });

  group('credit messages', () {
    test('salary credit is categorised as income', () {
      final r = parseTransactionSms(
        'Dear Customer, your A/c XX5678 is credited with INR 50,000.00 '
        'on 01-09-26 by SALARY. Ref 112233445566 -SBI',
        sender: 'AD-SBIBNK',
      );

      expect(r, isNotNull);
      expect(r!.amountPaise, 5000000);
      expect(r.direction, SmsDirection.credit);
      expect(r.category, 'income');
      expect(r.accountTail, '5678');
    });

    test('refund is a credit, not a spend', () {
      final r = parseTransactionSms(
        'Rs.799.00 has been credited to your A/c XX1234 as refund '
        'on 05-09-26. UPI Ref 776655443322',
        sender: 'VM-HDFCBK',
      );

      expect(r!.direction, SmsDirection.credit);
    });
  });

  group('confidence and routing', () {
    test('a fully corroborated bank message auto-logs', () {
      final r = parseTransactionSms(
        'Rs.500.00 debited from A/c XX1234 on 09-09-26 to VPA cafe@ybl. '
        'UPI Ref 123456789012. -HDFC Bank',
        sender: 'VM-HDFCBK',
      );

      expect(r!.confidence, greaterThanOrEqualTo(kAutoLogThreshold));
      expect(r.isAutoLoggable, isTrue);
    });

    test('a message from a personal number is never a transaction', () {
      // Friends text things like "paid Rs 500, send it back". Under the old
      // blocklist these were queued for review, which is how junk got into
      // the import queue in the first place.
      final r = parseTransactionSms(
        'Rs 500 debited',
        sender: '9876543210',
        receivedAt: DateTime(2026, 9, 9),
      );

      expect(r, isNull);
    });

    test('a bank message with no account identity waits for nothing', () {
      // "Rs 500 debited" with no a/c, card, VPA or rail named could be any
      // app's notification text — not enough to write into the ledger.
      final r = parseTransactionSms(
        'Rs 500 debited',
        sender: 'VM-HDFCBK',
        receivedAt: DateTime(2026, 9, 9),
      );

      expect(r, isNull);
    });

    test('personal phone numbers are not treated as bank senders', () {
      expect(looksLikeBankSender('9876543210'), isFalse);
      expect(looksLikeBankSender('+919876543210'), isFalse);
      expect(looksLikeBankSender('VM-HDFCBK'), isTrue);
      expect(looksLikeBankSender('AD-SBIUPI'), isTrue);
    });
  });

  group('dates', () {
    test('falls back to the received time when the body states no date', () {
      final received = DateTime(2026, 9, 9, 14, 30);
      final r = parseTransactionSms(
        'Rs.250.00 debited from A/c XX1234 to VPA shop@ybl ref 123456789',
        sender: 'VM-HDFCBK',
        receivedAt: received,
      );

      expect(r!.occurredAt, received);
    });

    test('parses a month-abbreviation date', () {
      final r = parseTransactionSms(
        'Rs.300.00 debited from A/c XX1234 on 09-Sep-26 to VPA shop@ybl '
        'ref 123456789',
        sender: 'VM-HDFCBK',
      );

      expect(r!.occurredAt, DateTime(2026, 9, 9));
    });
  });

  group('dedupe key', () {
    test('the same reference produces the same key across sources', () {
      final fromSms = parseTransactionSms(
        'Rs.500.00 debited from A/c XX1234 on 09-09-26 to VPA a@ybl. '
        'UPI Ref 123456789012.',
        sender: 'VM-HDFCBK',
      );
      final fromNotification = parseTransactionSms(
        'Paid Rs 500.00 to a@ybl. UPI Ref 123456789012',
        sender: 'GPay',
      );

      expect(fromSms!.dedupeKey(), fromNotification!.dedupeKey());
    });

    test('different transactions produce different keys', () {
      final a = parseTransactionSms(
        'Rs.500.00 debited from A/c XX1234 on 09-09-26 ref 111111111',
        sender: 'VM-HDFCBK',
      );
      final b = parseTransactionSms(
        'Rs.500.00 debited from A/c XX1234 on 09-09-26 ref 222222222',
        sender: 'VM-HDFCBK',
      );

      expect(a!.dedupeKey(), isNot(b!.dedupeKey()));
    });

    test('falls back to a composite key when there is no reference', () {
      final r = parseTransactionSms(
        'Rs 500 debited from A/c XX1234',
        sender: 'VM-HDFCBK',
        receivedAt: DateTime(2026, 9, 9),
      );

      expect(r!.dedupeKey(), 'cmp:2026-09-09:50000:debit:1234');
    });
  });
}
