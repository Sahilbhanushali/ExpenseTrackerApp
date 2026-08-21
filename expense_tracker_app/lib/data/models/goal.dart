class Goal {
  final int? id;
  final String name;
  final double target;
  final String? note;
  final String createdAt;

  const Goal({
    this.id,
    required this.name,
    required this.target,
    this.note,
    required this.createdAt,
  });

  Map<String, Object?> toMap() {
    return {
      'id': id,
      'name': name,
      'target': target,
      'note': note,
      'created_at': createdAt,
    };
  }

  factory Goal.fromMap(Map<String, Object?> map) {
    return Goal(
      id: map['id'] as int?,
      name: map['name'] as String,
      target: (map['target'] as num).toDouble(),
      note: map['note'] as String?,
      createdAt: map['created_at'] as String,
    );
  }
}
