import 'package:expense_tracker_app/core/utils/expense_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('parseMessage — amounts', () {
    test('plain number with category keyword', () {
      final r = parseMessage('spent 500 on ola');
      expect(r.amount, 500);
      expect(r.category, 'travel');
      expect(r.type, ParsedTxnType.expense);
    });

    test('k suffix', () {
      final r = parseMessage('1.5k myntra shirt');
      expect(r.amount, 1500);
      expect(r.category, 'clothes');
    });

    test('l suffix (lakh) does not eat "lunch"', () {
      final r = parseMessage('450 lunch');
      expect(r.amount, 450);
      expect(r.category, 'food');
    });

    test('lakh word', () {
      final r = parseMessage('2l invested in mutual fund');
      expect(r.amount, 200000);
      expect(r.category, 'investments');
    });

    test('rs prefix', () {
      final r = parseMessage('rs 200 chai');
      expect(r.amount, 200);
      expect(r.category, 'food');
    });

    test('currency symbol with comma grouping', () {
      final r = parseMessage('₹1,250 blinkit groceries');
      expect(r.amount, 1250);
      expect(r.category, 'groceries');
    });

    test('rs suffix', () {
      final r = parseMessage('500rs netflix');
      expect(r.amount, 500);
      expect(r.category, 'luxuries');
    });

    test('no amount found', () {
      final r = parseMessage('what is my budget');
      expect(r.amount, isNull);
    });
  });

  group('parseMessage — type detection', () {
    test('income keyword', () {
      final r = parseMessage('got salary 75000');
      expect(r.type, ParsedTxnType.income);
      expect(r.category, 'income');
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
      expect(results[0].amount, 450);
      expect(results[1].amount, 200);
    });

    test('falls back to a single entry when "and" is just part of a note', () {
      final results = parseMulti('coffee and snacks 300');
      expect(results, hasLength(1));
      expect(results[0].amount, 300);
    });
  });

  group('parseMessage — custom categories', () {
    test('extra category overrides default match', () {
      final r = parseMessage('vet visit 900', extraCategories: {
        'pets': ['vet', 'dog food'],
      });
      expect(r.category, 'pets');
    });
  });
}

String _iso(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
