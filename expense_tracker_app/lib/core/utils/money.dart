/// Money is stored and calculated as **integer paise**, never as a double.
///
/// A double can't represent 0.10 exactly, so repeated addition drifts: sum
/// enough ₹9,737.39 EMIs as doubles and the total stops matching what the
/// bank says. Integers are exact, and every amount in this app is a whole
/// number of paise, so there is nothing to lose by storing them that way.
///
/// The convention is that any field holding money is named `...Paise` — if
/// a number is called `amount` it is rupees and belongs only at the UI edge.
library;

/// ₹100.50 → 10050
int rupeesToPaise(num rupees) => (rupees * 100).round();

/// 10050 → 100.5. Only for display/'%' style maths — never store the result.
double paiseToRupees(int paise) => paise / 100;

/// Parses user input ("1,250.50", "₹1250.5", " 1250 ") into paise.
/// Returns null when the text isn't a usable number.
int? parseRupeesToPaise(String? text) {
  if (text == null) return null;
  final cleaned = text.replaceAll(RegExp(r'[₹,\s]'), '');
  if (cleaned.isEmpty) return null;
  final rupees = double.tryParse(cleaned);
  if (rupees == null) return null;
  return rupeesToPaise(rupees);
}

/// Value for prefilling an editable text field: "1250.5" for 125050.
/// Trims a trailing ".00" so whole rupees don't read as "500.00" in inputs.
String paiseToEditString(int paise) {
  final rupees = paiseToRupees(paise);
  final fixed = rupees.toStringAsFixed(2);
  return fixed.endsWith('.00') ? fixed.substring(0, fixed.length - 3) : fixed;
}

/// Splits [paise] into [count] parts that add back up to exactly [paise] —
/// the remainder is spread one paisa at a time rather than rounding each
/// part independently, which would lose or invent money.
List<int> splitPaiseEvenly(int paise, int count) {
  if (count <= 0) return const [];
  final base = paise ~/ count;
  var remainder = paise.remainder(count).abs();
  final step = paise.isNegative ? -1 : 1;
  return List.generate(count, (_) {
    var part = base;
    if (remainder > 0) {
      part += step;
      remainder--;
    }
    return part;
  });
}
