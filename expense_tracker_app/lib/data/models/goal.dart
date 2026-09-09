class Goal {
  final int? id;
  final String name;

  /// In paise.
  final int targetPaise;
  final String? note;
  final String createdAt;

  const Goal({
    this.id,
    required this.name,
    required this.targetPaise,
    this.note,
    required this.createdAt,
  });

  Map<String, Object?> toMap() {
    return {
      'id': id,
      'name': name,
      'target': targetPaise,
      'note': note,
      'created_at': createdAt,
    };
  }

  factory Goal.fromMap(Map<String, Object?> map) {
    return Goal(
      id: map['id'] as int?,
      name: map['name'] as String,
      targetPaise: (map['target'] as num).round(),
      note: map['note'] as String?,
      createdAt: map['created_at'] as String,
    );
  }
}
