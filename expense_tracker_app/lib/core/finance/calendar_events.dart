/// The financial calendar: every dated money event in one list. Pure — no
/// database, no Flutter.
library;

import 'salary_cycle.dart';

enum EventKind {
  salary,
  income,
  emi,
  cardDue,
  statement,
  bill,
  billIncome,
  transfer,
}

String eventKindLabel(EventKind k) => switch (k) {
  EventKind.salary => 'Salary',
  EventKind.income => 'Expected income',
  EventKind.emi => 'EMI',
  EventKind.cardDue => 'Card due',
  EventKind.statement => 'Statement day',
  EventKind.bill => 'Bill',
  EventKind.billIncome => 'Recurring income',
  EventKind.transfer => 'Planned transfer',
};

/// Money going out on this date (vs coming in, or just information).
enum MoneyFlow { outgoing, incoming, info }

class FinEvent {
  /// Stable per obligation — reminders are keyed by it, so rescheduling
  /// replaces a reminder instead of adding a second one.
  final String key;
  final DateTime date;
  final EventKind kind;
  final String title;

  /// Paise; null when the amount isn't known yet (e.g. a statement day).
  final int? amount;
  final MoneyFlow flow;
  final String? detail;

  const FinEvent({
    required this.key,
    required this.date,
    required this.kind,
    required this.title,
    this.amount,
    required this.flow,
    this.detail,
  });

  bool overdue(DateTime today) =>
      flow == MoneyFlow.outgoing && dateOnly(date).isBefore(dateOnly(today));
}

/// Next date with [day] of the month on or after [from], day clamped to the
/// month's length.
DateTime nextDayOfMonth(int day, DateTime from) {
  final f = dateOnly(from);
  DateTime on(int y, int m) {
    final last = DateTime(y, m + 1, 0).day;
    return DateTime(y, m, day > last ? last : day);
  }

  final thisMonth = on(f.year, f.month);
  return thisMonth.isBefore(f) ? on(f.year, f.month + 1) : thisMonth;
}

/// Events between [from] and [to] (inclusive), plus anything outgoing that
/// is already overdue. Sorted by date, overdue first.
List<FinEvent> eventsBetween(
  Iterable<FinEvent> all,
  DateTime from,
  DateTime to,
  DateTime today,
) {
  final f = dateOnly(from), t = dateOnly(to);
  final out =
      all.where((e) {
        final d = dateOnly(e.date);
        if (e.overdue(today)) return true;
        return !d.isBefore(f) && !d.isAfter(t);
      }).toList()..sort((a, b) {
        final c = a.date.compareTo(b.date);
        return c != 0 ? c : a.kind.index.compareTo(b.kind.index);
      });
  return out;
}

/// Totals for a window: what's due out and what's expected in. Paise.
({int outgoing, int incoming}) windowTotals(Iterable<FinEvent> events) {
  var o = 0, i = 0;
  for (final e in events) {
    final a = e.amount ?? 0;
    if (e.flow == MoneyFlow.outgoing) o += a;
    if (e.flow == MoneyFlow.incoming) i += a;
  }
  return (outgoing: o, incoming: i);
}

/// A notification id in a range of its own (500000–599999), stable for a
/// key, so the same obligation always maps to the same reminder.
int reminderId(String key) {
  var h = 0;
  for (final c in key.codeUnits) {
    h = (h * 31 + c) & 0x7fffffff;
  }
  return 500000 + h % 100000;
}

/// When to remind about [e]: [daysBefore] days ahead at [hour]:00, or null
/// when that moment has passed (or it's information only).
DateTime? reminderTime(
  FinEvent e,
  int daysBefore,
  DateTime now, {
  int hour = 9,
}) {
  if (e.flow == MoneyFlow.info && e.kind != EventKind.statement) return null;
  final day = dateOnly(e.date).subtract(Duration(days: daysBefore));
  final at = DateTime(day.year, day.month, day.day, hour);
  return at.isAfter(now) ? at : null;
}
