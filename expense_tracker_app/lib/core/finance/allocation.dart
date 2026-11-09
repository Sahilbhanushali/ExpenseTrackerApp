/// Smart Money Allocation: a priority-based plan for unallocated cash.
/// Pure — no database, no Flutter.
///
/// - Funds only what is actually unallocated: cash in spendable accounts,
///   minus holds, minus money already reserved. Received income is already
///   inside those balances, so it is never added a second time, and money
///   in savings / emergency / investment accounts is never re-spent.
/// - Walks the priority order; each need gets what it requires (less what
///   is already reserved for it) until the money runs out.
/// - Never balances a plan that can't be balanced: unmet needs are shown as
///   shortfalls.
/// - Investing is skipped while anything essential or due is uncovered, or
///   card debt has gone past its due date.
library;

enum AllocBucket {
  essentials,
  obligations,
  emergency,
  savings,
  investing,
  discretionary,
  buffer,
}

String bucketLabel(AllocBucket b) => switch (b) {
  AllocBucket.essentials => 'Essentials',
  AllocBucket.obligations => 'Bills, EMIs & card dues',
  AllocBucket.emergency => 'Emergency fund',
  AllocBucket.savings => 'Short-term savings',
  AllocBucket.investing => 'Investing',
  AllocBucket.discretionary => 'Discretionary spending',
  AllocBucket.buffer => 'Unallocated buffer',
};

/// The configurable default order (spec §9B). The buffer is always last.
const kDefaultAllocationOrder = [
  AllocBucket.essentials,
  AllocBucket.obligations,
  AllocBucket.emergency,
  AllocBucket.savings,
  AllocBucket.investing,
  AllocBucket.discretionary,
];

/// One thing the money could go to. All paise.
class AllocationNeed {
  /// Stable id for decisions, e.g. `card:3:stmt:7`, `loan:2:inst:14`.
  final String key;
  final AllocBucket bucket;
  final String label;
  final int required;

  /// Where the money should sit (an account name), if known.
  final String? destination;
  final DateTime? dueDate;

  /// Why, in words built from the actual figures.
  final String reason;

  /// Overdue card balance: interest is accruing.
  final bool revolving;

  const AllocationNeed({
    required this.key,
    required this.bucket,
    required this.label,
    required this.required,
    required this.reason,
    this.destination,
    this.dueDate,
    this.revolving = false,
  });
}

class AllocationLine {
  final AllocationNeed need;

  /// Already set aside for this need by an earlier approval.
  final int reserved;

  /// Newly proposed now.
  final int proposed;

  /// Still uncovered after [reserved] + [proposed].
  final int shortfall;

  /// Set when the line was deliberately not funded (e.g. investing while
  /// obligations are at risk).
  final String? skippedBecause;

  const AllocationLine({
    required this.need,
    required this.reserved,
    required this.proposed,
    required this.shortfall,
    this.skippedBecause,
  });

  int get priority => need.bucket.index;
}

class AllocationPlan {
  /// Money available to allocate now.
  final int available;
  final List<AllocationLine> lines;

  /// What's left after every need — kept as a buffer, never forced anywhere.
  final int buffer;

  const AllocationPlan({
    required this.available,
    required this.lines,
    required this.buffer,
  });

  int get proposedTotal => lines.fold(0, (s, l) => s + l.proposed);

  /// Uncovered essentials and obligations — the money that's short before
  /// the next salary.
  int get criticalShortfall => lines
      .where(
        (l) =>
            l.need.bucket == AllocBucket.essentials ||
            l.need.bucket == AllocBucket.obligations,
      )
      .fold(0, (s, l) => s + l.shortfall);

  /// Highest-priority unmet needs first, soonest due first within a bucket.
  List<AllocationLine> get unmet =>
      lines.where((l) => l.shortfall > 0).toList()..sort(_byPriority);
}

int _byPriority(AllocationLine a, AllocationLine b) {
  final p = a.priority.compareTo(b.priority);
  if (p != 0) return p;
  final ad = a.need.dueDate, bd = b.need.dueDate;
  if (ad == null || bd == null) return ad == null ? 1 : -1;
  return ad.compareTo(bd);
}

/// Builds the plan. [reservedByKey] is what earlier approvals already set
/// aside per need (not part of [available]). [order] is the user's priority
/// order; buckets missing from it keep their default place.
AllocationPlan allocate({
  required int available,
  required List<AllocationNeed> needs,
  Map<String, int> reservedByKey = const {},
  List<AllocBucket> order = kDefaultAllocationOrder,
}) {
  final rank = {
    for (final (i, b) in order.indexed) b: i,
    for (final b in AllocBucket.values)
      if (!order.contains(b)) b: order.length + b.index,
  };
  // Overdue card debt always comes before discretionary and investing,
  // whatever the order says.
  int rankOf(AllocationNeed n) {
    final r = rank[n.bucket]!;
    if (n.revolving) {
      final cap = [
        rank[AllocBucket.investing]!,
        rank[AllocBucket.discretionary]!,
        rank[AllocBucket.savings]!,
      ].reduce((a, b) => a < b ? a : b);
      return r < cap ? r : cap - 1;
    }
    return r;
  }

  final sorted = [...needs]
    ..sort((a, b) {
      final c = rankOf(a).compareTo(rankOf(b));
      if (c != 0) return c;
      final ad = a.dueDate, bd = b.dueDate;
      if (ad == null || bd == null) return ad == null ? 1 : -1;
      return ad.compareTo(bd);
    });

  var left = available < 0 ? 0 : available;
  var urgentUncovered = false;
  final revolving = needs.any((n) => n.revolving);
  final lines = <AllocationLine>[];
  for (final n in sorted) {
    final reserved = (reservedByKey[n.key] ?? 0).clamp(0, n.required);
    final want = n.required - reserved;
    if (n.bucket == AllocBucket.investing && (urgentUncovered || revolving)) {
      lines.add(
        AllocationLine(
          need: n,
          reserved: reserved,
          proposed: 0,
          shortfall: 0,
          skippedBecause: revolving
              ? 'Card debt is past its due date — clear it before investing.'
              : 'Essentials or dues aren’t fully covered yet.',
        ),
      );
      continue;
    }
    final give = want < left ? want : left;
    left -= give;
    final short = want - give;
    if (short > 0 &&
        (n.bucket == AllocBucket.essentials ||
            n.bucket == AllocBucket.obligations ||
            n.revolving)) {
      urgentUncovered = true;
    }
    lines.add(
      AllocationLine(
        need: n,
        reserved: reserved,
        proposed: give,
        shortfall: short,
      ),
    );
  }
  return AllocationPlan(available: available, lines: lines, buffer: left);
}
