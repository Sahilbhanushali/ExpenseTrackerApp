/// Salary-cycle date logic. Pure — no database, no Flutter — so every rule
/// is unit-tested on its own.
///
/// A cycle starts on the day the salary actually arrived and ends the day
/// before the next salary arrived. Only start dates are stored; ends are
/// derived, so cycles can never overlap or leave gaps. The newest cycle is
/// open-ended until the next salary is recorded (decision D3).
library;

DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

String isoDate(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// What the user expects to be paid. None of these figures are money
/// received — only recorded salary counts toward available cash.
class SalaryProfile {
  /// Cost to company, per year. Informational only: CTC is never spendable.
  final int? ctcAnnualPaise;

  /// Gross monthly salary before deductions.
  final int? grossMonthlyPaise;

  /// Expected take-home per month.
  final int? expectedNetPaise;

  /// Salary usually arrives between these days of the month (inclusive).
  final int dayFrom;
  final int dayTo;

  /// Account the salary is usually credited to.
  final String? account;

  const SalaryProfile({
    this.ctcAnnualPaise,
    this.grossMonthlyPaise,
    this.expectedNetPaise,
    this.dayFrom = 7,
    this.dayTo = 15,
    this.account,
  });

  bool get isSet =>
      expectedNetPaise != null ||
      grossMonthlyPaise != null ||
      ctcAnnualPaise != null;
}

/// One stored cycle: its start and how its salary is known.
class CycleRecord {
  final int? id;
  final DateTime start;

  /// The income transaction for this cycle's salary, when it was recorded
  /// as one.
  final int? salaryTxnId;

  /// Salary that is already inside an account's opening balance, so it was
  /// deliberately not recorded as a transaction (that would count it twice).
  final int? untrackedSalaryPaise;

  /// Set when the cycle was closed (Phase 8). Closed cycles never move.
  final DateTime? closedAt;
  final String? note;

  /// Frozen at closing (a [CycleCloseSummary] encoding); null while open.
  final String? summaryJson;

  const CycleRecord({
    this.summaryJson,
    this.id,
    required this.start,
    this.salaryTxnId,
    this.untrackedSalaryPaise,
    this.closedAt,
    this.note,
  });

  bool get isClosed => closedAt != null;
}

/// A cycle with its derived end. [end] is null for the current, open cycle.
class CycleRange {
  final CycleRecord record;
  final DateTime start;
  final DateTime? end;
  const CycleRange(this.record, this.start, this.end);

  bool get isOpen => end == null;

  bool contains(DateTime day) {
    final d = dateOnly(day);
    return !d.isBefore(start) && (end == null || !d.isAfter(end!));
  }

  /// Inclusive query end: the derived end, or [today] for the open cycle.
  DateTime queryEnd(DateTime today) => end ?? dateOnly(today);
}

/// Sorts by start and derives each end as the day before the next start.
List<CycleRange> resolveCycles(Iterable<CycleRecord> records) {
  final sorted = [...records]..sort((a, b) => a.start.compareTo(b.start));
  return [
    for (var i = 0; i < sorted.length; i++)
      CycleRange(
        sorted[i],
        dateOnly(sorted[i].start),
        i + 1 < sorted.length
            ? dateOnly(sorted[i + 1].start).subtract(const Duration(days: 1))
            : null,
      ),
  ];
}

/// The cycle containing [day], if any.
CycleRange? cycleOn(List<CycleRange> cycles, DateTime day) {
  for (final c in cycles.reversed) {
    if (c.contains(day)) return c;
  }
  return null;
}

/// When the next salary is expected: [SalaryProfile.dayFrom]–[dayTo] of the
/// month after the cycle started (days clamped to the month's length).
class SalaryWindow {
  final DateTime earliest;
  final DateTime latest;
  const SalaryWindow(this.earliest, this.latest);
}

SalaryWindow nextSalaryWindow(DateTime cycleStart, SalaryProfile profile) {
  final y = cycleStart.year, m = cycleStart.month + 1;
  final lastDay = DateTime(y, m + 1, 0).day;
  int clamp(int d) => d.clamp(1, lastDay);
  final from = clamp(profile.dayFrom), to = clamp(profile.dayTo);
  return SalaryWindow(
    DateTime(y, m, from < to ? from : to),
    DateTime(y, m, from < to ? to : from),
  );
}

/// Where today sits in the open cycle.
class CycleStanding {
  final int dayNumber;

  /// Days this cycle's money must last, counting today, up to the *latest*
  /// expected salary day — the safe assumption, since planning to the
  /// earliest day would overspend whenever salary comes late in the window.
  /// Null once that day has passed with no salary recorded.
  final int? daysToLast;

  final bool salaryLate;
  final SalaryWindow window;

  const CycleStanding({
    required this.dayNumber,
    required this.daysToLast,
    required this.salaryLate,
    required this.window,
  });
}

CycleStanding standingOf(
  CycleRange cycle,
  SalaryProfile profile,
  DateTime today,
) {
  final t = dateOnly(today);
  final window = nextSalaryWindow(cycle.start, profile);
  final late = t.isAfter(window.latest);
  return CycleStanding(
    dayNumber: t.difference(cycle.start).inDays + 1,
    daysToLast: late ? null : window.latest.difference(t).inDays + 1,
    salaryLate: late,
    window: window,
  );
}

/// Why a new cycle start (or a moved one) isn't allowed, or null if fine.
///
/// [movingId] is the cycle being moved, ignored when checking clashes.
String? validateCycleStart(
  DateTime start,
  List<CycleRange> cycles,
  DateTime today, {
  int? movingId,
}) {
  final s = dateOnly(start);
  if (s.isAfter(dateOnly(today))) return "A cycle can't start in the future.";
  final others = cycles.where((c) => c.record.id != movingId).toList();
  if (others.any((c) => c.start == s)) {
    return 'Another cycle already starts on that day.';
  }
  // A closed cycle's dates are history (rule 15): a start inside one would
  // cut it short, so it's refused. Starting after its end is fine — that
  // only shortens the (unclosed) cycle the date falls in.
  for (final c in others.where((c) => c.record.isClosed)) {
    final end = c.end;
    if (!s.isBefore(c.start) && (end == null || !s.isAfter(end))) {
      return 'That date falls in a closed cycle, which can’t change.';
    }
  }
  if (movingId != null) {
    final moving = cycles.firstWhere((c) => c.record.id == movingId);
    if (moving.record.isClosed) return 'A closed cycle can’t be moved.';
    final idx = cycles.indexOf(moving);
    final prev = idx > 0 ? cycles[idx - 1] : null;
    final next = idx + 1 < cycles.length ? cycles[idx + 1] : null;
    if (prev != null && !s.isAfter(prev.start)) {
      return 'It must stay after the previous cycle’s start.';
    }
    if (next != null && !s.isBefore(next.start)) {
      return 'It must stay before the next cycle’s start.';
    }
    if (prev != null && prev.record.isClosed) {
      return 'The previous cycle is closed, so this start can’t move.';
    }
  }
  return null;
}

/// Income for one cycle, from the ledger. All paise.
class CycleIncome {
  /// The cycle's salary: its linked transaction, or the amount recorded as
  /// already being in an opening balance.
  final int salary;

  /// Every other income received inside the cycle's dates.
  final int additional;

  const CycleIncome({required this.salary, required this.additional});

  int get total => salary + additional;
}
