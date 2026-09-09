class WishlistItem {
  final int? id;
  final String name;

  /// In paise.
  final int pricePaise;
  final String? note;
  final bool purchased;
  final String createdAt;
  final String? purchasedAt;

  const WishlistItem({
    this.id,
    required this.name,
    required this.pricePaise,
    this.note,
    this.purchased = false,
    required this.createdAt,
    this.purchasedAt,
  });

  Map<String, Object?> toMap() {
    return {
      'id': id,
      'name': name,
      'price': pricePaise,
      'note': note,
      'purchased': purchased ? 1 : 0,
      'created_at': createdAt,
      'purchased_at': purchasedAt,
    };
  }

  factory WishlistItem.fromMap(Map<String, Object?> map) {
    return WishlistItem(
      id: map['id'] as int?,
      name: map['name'] as String,
      pricePaise: (map['price'] as num).round(),
      note: map['note'] as String?,
      purchased: (map['purchased'] as int) == 1,
      createdAt: map['created_at'] as String,
      purchasedAt: map['purchased_at'] as String?,
    );
  }
}
