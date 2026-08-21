class WishlistItem {
  final int? id;
  final String name;
  final double price;
  final String? note;
  final bool purchased;
  final String createdAt;
  final String? purchasedAt;

  const WishlistItem({
    this.id,
    required this.name,
    required this.price,
    this.note,
    this.purchased = false,
    required this.createdAt,
    this.purchasedAt,
  });

  Map<String, Object?> toMap() {
    return {
      'id': id,
      'name': name,
      'price': price,
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
      price: (map['price'] as num).toDouble(),
      note: map['note'] as String?,
      purchased: (map['purchased'] as int) == 1,
      createdAt: map['created_at'] as String,
      purchasedAt: map['purchased_at'] as String?,
    );
  }
}
