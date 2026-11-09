import '../../core/finance/wealth.dart';

/// A savings goal: an earmark on part of a savings account's money, not a
/// separate pot — so it's never counted twice in net worth.
class Goal {
  final int? id;
  final String name;

  /// In paise.
  final int targetPaise;
  final String? note;
  final String createdAt;
  final DateTime? targetDate;

  /// 1 high, 2 medium, 3 low.
  final int priority;

  /// Planned per month, in paise.
  final int? monthlyContributionPaise;

  /// The savings (or investment) account the goal's money sits in.
  final String? account;
  final GoalHorizon horizon;
  final bool achieved;

  /// Already saved toward it when the goal was added, in paise.
  final int startingPaise;

  const Goal({
    this.id,
    required this.name,
    required this.targetPaise,
    this.note,
    required this.createdAt,
    this.targetDate,
    this.priority = 2,
    this.monthlyContributionPaise,
    this.account,
    this.horizon = GoalHorizon.short,
    this.achieved = false,
    this.startingPaise = 0,
  });

  Map<String, Object?> toMap() => {
    'id': id,
    'name': name,
    'target': targetPaise,
    'note': note,
    'created_at': createdAt,
    'target_date': targetDate?.toIso8601String(),
    'priority': priority,
    'monthly_contribution': monthlyContributionPaise,
    'account': account,
    'kind': horizon.name,
    'status': achieved ? 'achieved' : 'active',
    'starting_amount': startingPaise,
  };

  factory Goal.fromMap(Map<String, Object?> map) => Goal(
    id: map['id'] as int?,
    name: map['name'] as String,
    targetPaise: (map['target'] as num).round(),
    note: map['note'] as String?,
    createdAt: map['created_at'] as String,
    targetDate: map['target_date'] == null
        ? null
        : DateTime.parse(map['target_date'] as String),
    priority: map['priority'] as int? ?? 2,
    monthlyContributionPaise: map['monthly_contribution'] as int?,
    account: map['account'] as String?,
    horizon: map['kind'] == 'long' ? GoalHorizon.long : GoalHorizon.short,
    achieved: map['status'] == 'achieved',
    startingPaise: map['starting_amount'] as int? ?? 0,
  );
}
