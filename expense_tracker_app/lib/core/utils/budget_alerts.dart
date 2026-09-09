/// Port of bot.py's _crossed()/_threshold_warnings() — fires a warning only
/// the moment a transaction pushes a total across the 80%/100% line, not on
/// every message after.
bool _crossed(int before, int after, int cap, double frac) {
  return cap > 0 && before < cap * frac && after >= cap * frac;
}

List<String> buildThresholdWarnings({
  /// All money arguments are in paise.
  required int beforeSpent,
  required int afterSpent,
  required int budget,
  required int beforeCat,
  required int afterCat,
  required int catCap,
  required String category,
  required String Function(int) fmt,
}) {
  final warnings = <String>[];
  final remaining = budget - afterSpent;

  if (_crossed(beforeSpent, afterSpent, budget, 1.0)) {
    warnings.add('Over monthly budget! Overspent by ${fmt(remaining.abs())}.');
  } else if (_crossed(beforeSpent, afterSpent, budget, 0.8)) {
    warnings.add(
      '80% of monthly budget used — ${fmt(remaining)} left for the month.',
    );
  }

  final catRemaining = catCap - afterCat;
  if (_crossed(beforeCat, afterCat, catCap, 1.0)) {
    warnings.add(
      'Over budget for $category! Overspent by ${fmt(catRemaining.abs())}.',
    );
  } else if (_crossed(beforeCat, afterCat, catCap, 0.8)) {
    warnings.add(
      '80% of $category budget used — ${fmt(catRemaining)} left in this category.',
    );
  }

  return warnings;
}
