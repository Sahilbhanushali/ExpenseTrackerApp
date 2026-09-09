import 'package:flutter_test/flutter_test.dart';

import 'package:expense_tracker_app/core/utils/sms_parser.dart';

/// Precision guard for SMS import.
///
/// The parser began as a blocklist — reject known-bad phrases, accept
/// anything else carrying an amount and a verb — and let 8 of these 10 junk
/// messages through, auto-logging one of them straight into the ledger.
/// These cases exist so that never regresses: every message below is one a
/// real Indian phone receives constantly.
void main() {
  ParsedSms? parse(String sender, String body) => parseTransactionSms(
    body,
    sender: sender,
    receivedAt: DateTime(2026, 9, 9),
  );

  group('junk is never logged', () {
    const cases = <String, (String, String)>{
      'shop order confirmation': (
        'AX-AMAZON',
        'Your order of Rs.499 has been sent. Track it in the app.',
      ),
      'savings brag': (
        'VM-SWIGGY',
        'Yay! You saved Rs.120 on this order. Order again soon.',
      ),
      'friend asking for money': (
        '9876543210',
        'bro I paid Rs 500 to the guy, send it back',
      ),
      'friend confirming a transfer': (
        '9123456789',
        'Rs 2000 sent na? confirm karo',
      ),
      'wallet marketing': (
        'AD-PAYTM',
        'Rs.50 cashback received in your Paytm wallet. Shop more!',
      ),
      'recharge plan notice': (
        'BP-JIO',
        'Your Jio plan of Rs 239 is active till 12-10-2026.',
      ),
      'discount code': (
        'VK-ZOMATO',
        'Rs.150 off your next order, use code EAT150. Paid users only.',
      ),
      'courier update with a ref number': (
        'AX-MYNTRA',
        'Purchase worth Rs 1,299 shipped. Ref no MYN9087612',
      ),
      'loyalty points': (
        'DM-CRED',
        'You have received 500 coins worth Rs.5. Claim now',
      ),
      'otp quoting an amount': (
        'VM-HDFCBK',
        'OTP for txn of Rs 2500 on card XX1234 is 445566. Do not share.',
      ),
      'payment request, not a payment': (
        'VM-PHONPE',
        'RAHUL has requested Rs.300 via UPI. Ref 8877665544',
      ),
      'failed payment': (
        'AD-ICICIB',
        'Your payment of Rs.1200 to A/c XX4321 has failed. UPI Ref 7766554433',
      ),
      'scheduled future debit': (
        'JM-SBIINB',
        'Rs.5000 will be debited from A/c XX9876 on 15-09-26 towards SIP.',
      ),
      'balance enquiry': (
        'VM-HDFCBK',
        'Available balance in A/c XX1234 is Rs.14,250.00 as on 09-09-26.',
      ),
      'credit card bill due': (
        'AD-ICICIB',
        'Minimum amount due Rs.2,500 on your ICICI Card XX4321 by 20-09-26.',
      ),
      'pre-approved loan offer': (
        'VM-HDFCBK',
        'You are eligible for a pre-approved loan of Rs.5,00,000. Apply now.',
      ),
      'bare amount with no account named': ('VM-HDFCBK', 'Rs 500 debited'),

      // --- Found queued on a real device, all wrongly read as income. ---
      'wallet top-up is a transfer, not income': (
        'VM-CREDCL',
        'Update from CRED wallet: Rs.5,000.00 has been successfully '
            'credited to your CRED wallet.',
      ),
      'card bill payment confirmation is not income': (
        'JD-SLICEIT',
        'Repayment of Rs.765.85 received for the slice credit card. The '
            'amount has been credited to your card account - slice',
      ),
      'EPF passbook balance is a statement, not a transaction': (
        'VA-EPFOHO-G',
        'Dear XXXXXXXX5620, your passbook balance against '
            'SRVAP**************0019 is Rs. 7,478/-. Contribution of Rs. '
            '1,742/- for due month Jun-26 has been received.',
      ),
      'a refund that has not arrived yet': (
        'JK-blnkit-S',
        'We have initiated a refund of Rs.418.00 for ORD72093038024 into '
            'your UPI, which should reflect in 3-5 business days. -blinkit',
      ),
    };

    cases.forEach((name, msg) {
      test(name, () => expect(parse(msg.$1, msg.$2), isNull, reason: msg.$2));
    });
  });

  group('real bank alerts still parse', () {
    test('UPI debit to a merchant VPA', () {
      final r = parse(
        'VM-HDFCBK',
        'Rs.500.00 debited from A/c XX1234 on 09-09-26 to VPA swiggy@ybl. '
            'UPI Ref 123456789012. Not you? Call 18002586161',
      );

      expect(r, isNotNull);
      expect(r!.direction, SmsDirection.debit);
      expect(r.amountPaise, 50000);
      expect(r.accountTail, '1234');
      expect(r.referenceNo, '123456789012');
      expect(r.occurredAt, DateTime(2026, 9, 9));
      expect(r.isAutoLoggable, isTrue);
    });

    test('card spend resolves to debit despite the words "Credit Card"', () {
      // "ICICI Bank Credit Card" used to make this read as both directions
      // at once, and the message was discarded entirely.
      final r = parse(
        'AD-ICICIB',
        'INR 1,250.50 spent on ICICI Bank Credit Card XX4321 on 09-Sep-26 '
            'at AMAZON. Avl Lmt INR 48,749.50',
      );

      expect(r, isNotNull);
      expect(r!.direction, SmsDirection.debit);
      expect(r.amountPaise, 125050);
      expect(r.accountTail, '4321');
    });

    test('a debit that also quotes the balance is still a debit', () {
      // Nearly every Indian bank alert ends with "Avl Bal: Rs...". Treating
      // that phrase as proof of a balance-only message threw away real
      // spending — the worst possible failure for an expense tracker.
      final r = parse(
        'VM-HDFCBK',
        'Rs.500.00 debited from A/c XX1234 on 09-09-26 to VPA swiggy@ybl. '
            'UPI Ref 123456789012. Avl Bal: Rs.14,250.00',
      );

      expect(r, isNotNull);
      expect(r!.direction, SmsDirection.debit);
      expect(r.amountPaise, 50000, reason: 'the spend, not the balance');
    });

    test('a real BOB UPI credit with a trailing AvlBal', () {
      final r = parse(
        'JK-BOBSMS-S',
        'Dear BOB UPI User: Your account is credited with INR 5000.00 on '
            '2026-07-09 06:43:54 PM by UPI Ref No 619057260304; '
            'AvlBal: Rs5002.90 - BOB',
      );

      expect(r, isNotNull);
      expect(r!.direction, SmsDirection.credit);
      expect(r.amountPaise, 500000);
      expect(r.referenceNo, '619057260304');
    });

    test('a refund that actually landed is income', () {
      // The counterpart to the "initiated ... 3-5 business days" case: this
      // one names the account it reached, in the past tense.
      final r = parse(
        'VM-HDFCBK',
        'Rs.418.00 credited to A/c XX1234 on 09-09-26 towards refund. '
            'UPI Ref 665544332211',
      );

      expect(r, isNotNull);
      expect(r!.direction, SmsDirection.credit);
      expect(r.amountPaise, 41800);
    });

    test('salary credit', () {
      final r = parse(
        'JM-SBIINB',
        'Dear Customer, Rs.2000 credited to A/c XX9876 on 09/09/2026 by '
            'transfer from RAMESH. Ref 998877665544',
      );

      expect(r, isNotNull);
      expect(r!.direction, SmsDirection.credit);
      expect(r.amountPaise, 200000);
      expect(r.category, kSmsIncomeCategory);
    });

    test('ATM withdrawal', () {
      final r = parse(
        'VM-HDFCBK',
        'Rs.2,000 withdrawn from A/c XX1234 at ATM on 09-09-26. '
            'Txn ID 5566778899',
      );

      expect(r, isNotNull);
      expect(r!.direction, SmsDirection.debit);
      expect(r.amountPaise, 200000);
    });

    test('a payment naming only a UPI handle, no account digits', () {
      final r = parse(
        'VM-PHONPE',
        'Rs.150 paid to zomato@ybl via UPI. UTR 334455667788',
      );

      expect(r, isNotNull);
      expect(r!.direction, SmsDirection.debit);
      expect(r.amountPaise, 15000);
    });
  });

  group('rejection reasons are reported', () {
    ({String body, String sender, SmsRejection why}) c(
      String sender,
      String body,
      SmsRejection why,
    ) => (sender: sender, body: body, why: why);

    final cases = [
      c(
        '9876543210',
        'Rs 500 debited from A/c XX1',
        SmsRejection.personalSender,
      ),
      c('VM-HDFCBK', 'OTP is 4455 for Rs 500', SmsRejection.otp),
      c(
        'VM-HDFCBK',
        'Rs.500 to A/c XX1234 has failed',
        SmsRejection.notCompleted,
      ),
      c('AX-AMAZON', 'Your order of Rs.499 shipped', SmsRejection.orderStatus),
      c(
        'VM-HDFCBK',
        'Flat discount of Rs.500, apply now',
        SmsRejection.promotional,
      ),
      c(
        'VM-HDFCBK',
        'Available balance in A/c XX1234 is Rs.500 as on date',
        SmsRejection.balanceOnly,
      ),
      c(
        'VM-CREDCL',
        'Rs.5,000 has been credited to your CRED wallet',
        SmsRejection.selfTransfer,
      ),
      c('VM-HDFCBK', 'Your A/c XX1234 was accessed', SmsRejection.noAmount),
      c('VM-HDFCBK', 'Rs.500 on A/c XX1234 via UPI', SmsRejection.noDirection),
      c('VM-HDFCBK', 'Rs 500 debited', SmsRejection.noAccountIdentity),
    ];

    for (final t in cases) {
      test(t.why.name, () {
        final (parsed, why) = parseTransactionSmsVerbose(
          t.body,
          sender: t.sender,
        );
        expect(parsed, isNull, reason: t.body);
        expect(why, t.why, reason: t.body);
      });
    }
  });

  group('auto-log threshold', () {
    test('a fully corroborated bank alert logs itself', () {
      final r = parse(
        'VM-HDFCBK',
        'Rs.500.00 debited from A/c XX1234 on 09-09-26 to VPA swiggy@ybl. '
            'UPI Ref 123456789012',
      );

      expect(r!.isAutoLoggable, isTrue);
    });

    test('a thinner message waits for review instead of self-logging', () {
      // No reference number and no stated date: plausible, but not certain
      // enough to write into the ledger unasked.
      final r = parse('VM-HDFCBK', 'Rs.500 paid to someone@ybl via UPI');

      expect(r, isNotNull);
      expect(r!.isAutoLoggable, isFalse);
    });
  });
}
