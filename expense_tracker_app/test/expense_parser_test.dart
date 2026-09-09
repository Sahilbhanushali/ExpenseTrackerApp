import 'package:expense_tracker_app/core/utils/expense_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('parseMessage — amounts', () {
    test('plain number with category keyword', () {
      final r = parseMessage('spent 500 on ola');
      expect(r.amountPaise, 50000);
      expect(r.category, 'travel');
      expect(r.type, ParsedTxnType.expense);
    });

    test('k suffix', () {
      final r = parseMessage('1.5k myntra shirt');
      expect(r.amountPaise, 150000);
      expect(r.category, 'clothes');
    });

    test('l suffix (lakh) does not eat "lunch"', () {
      final r = parseMessage('450 lunch');
      expect(r.amountPaise, 45000);
      expect(r.category, 'food');
    });

    test('lakh word', () {
      final r = parseMessage('2l invested in mutual fund');
      expect(r.amountPaise, 20000000);
      expect(r.category, 'investments');
    });

    test('rs prefix', () {
      final r = parseMessage('rs 200 chai');
      expect(r.amountPaise, 20000);
      expect(r.category, 'food');
    });

    test('currency symbol with comma grouping', () {
      final r = parseMessage('₹1,250 blinkit groceries');
      expect(r.amountPaise, 125000);
      expect(r.category, 'groceries');
    });

    test('rs suffix', () {
      final r = parseMessage('500rs netflix');
      expect(r.amountPaise, 50000);
      expect(r.category, 'luxuries');
    });

    test('no amount found', () {
      final r = parseMessage('what is my budget');
      expect(r.amountPaise, isNull);
    });
  });

  group('parseMessage — type detection', () {
    test('income keyword', () {
      final r = parseMessage('got salary 75000');
      expect(r.type, ParsedTxnType.income);
      expect(r.category, 'income');
    });

    test('freelance income keyword', () {
      final r = parseMessage('got 5000 from freelance work');
      expect(r.type, ParsedTxnType.income);
      expect(r.amountPaise, 500000);
    });

    test('lent keyword with counterparty', () {
      final r = parseMessage('lent 500 to Rahul for lunch');
      expect(r.type, ParsedTxnType.lent);
      expect(r.counterparty, 'Rahul');
      expect(r.category, 'lending');
    });

    test('borrowed keyword with counterparty', () {
      final r = parseMessage('borrowed 1000 from Priya');
      expect(r.type, ParsedTxnType.borrowed);
      expect(r.counterparty, 'Priya');
    });

    test('repayment keyword with counterparty', () {
      final r = parseMessage('paid back 500 to sachin');
      expect(r.type, ParsedTxnType.repayment);
      expect(r.counterparty, 'Sachin');
      expect(r.category, 'lending');
    });

    test(
      'repayment "returned" keyword does not get read as a plain expense',
      () {
        final r = parseMessage('returned 200 to rahul');
        expect(r.type, ParsedTxnType.repayment);
        expect(r.counterparty, 'Rahul');
      },
    );

    test('emi payment keyword extracts item name', () {
      final r = parseMessage('given emi for fridge of rs 10000');
      expect(r.type, ParsedTxnType.emiPayment);
      expect(r.amountPaise, 1000000);
      expect(r.note, 'fridge');
    });

    test('emi create keyword builds monthly amount + months + item', () {
      final r = parseMessage(
        'bought fridge of 65000 on emi for 6 months every month i have to pay 10000',
      );
      expect(r.type, ParsedTxnType.emiCreate);
      expect(r.amountPaise, 1000000);
      expect(r.emiMonths, 6);
      expect(r.note, 'fridge');
    });

    test(
      'emi keyword without a months count falls back to a plain expense',
      () {
        final r = parseMessage('fridge on emi 65000');
        expect(r.type, ParsedTxnType.expense);
      },
    );

    test(
      'lend with given/pending split creates loan for the given amount only',
      () {
        final r = parseMessage(
          'i want to give money to henil for the project share 50000 5000 given pending 45000 which i will give month by month',
        );
        expect(r.type, ParsedTxnType.lent);
        expect(r.amountPaise, 500000);
        expect(r.pendingAmountPaise, 4500000);
        expect(r.counterparty, 'Henil');
      },
    );
  });

  group('parseMessage — dates', () {
    test('yesterday', () {
      final expected = DateTime.now().subtract(const Duration(days: 1));
      final r = parseMessage('yesterday 500 taxi');
      expect(r.date, _iso(expected));
      expect(r.category, 'travel');
    });

    test('N days ago', () {
      final expected = DateTime.now().subtract(const Duration(days: 3));
      final r = parseMessage('3 days ago 200 chai');
      expect(r.date, _iso(expected));
    });

    test('explicit month/day', () {
      final r = parseMessage('780 groceries on 3rd aug 2026');
      expect(r.date, '2026-08-03');
    });

    test('defaults to today when no date phrase', () {
      final r = parseMessage('300 electricity bill');
      expect(r.date, _iso(DateTime.now()));
    });
  });

  group('parseMulti', () {
    test('splits "and" when both sides have an amount', () {
      final results = parseMulti('450 lunch and 200 auto');
      expect(results, hasLength(2));
      expect(results[0].amountPaise, 45000);
      expect(results[1].amountPaise, 20000);
    });

    test('falls back to a single entry when "and" is just part of a note', () {
      final results = parseMulti('coffee and snacks 300');
      expect(results, hasLength(1));
      expect(results[0].amountPaise, 30000);
    });
  });

  group('parseMessage — custom categories', () {
    test('extra category overrides default match', () {
      final r = parseMessage(
        'vet visit 900',
        extraCategories: {
          'pets': ['vet', 'dog food'],
        },
      );
      expect(r.category, 'pets');
    });
  });
}

String _iso(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
