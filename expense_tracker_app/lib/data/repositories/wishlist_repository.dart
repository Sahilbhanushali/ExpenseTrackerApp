import '../datasources/app_database.dart';
import '../models/wishlist_item.dart';

/// Port of expense_bot/db.py's wishlist functions.
class WishlistRepository {
  final AppDatabase _db;
  WishlistRepository([AppDatabase? db]) : _db = db ?? AppDatabase.instance;

  Future<int> add(String name, double price, {String? note}) async {
    final db = await _db.database;
    return db.insert('wishlist', {
      'name': name,
      'price': price,
      'note': note,
      'purchased': 0,
      'created_at': DateTime.now().toIso8601String(),
    });
  }

  Future<List<WishlistItem>> list({bool includePurchased = false}) async {
    final db = await _db.database;
    final rows = await db.query(
      'wishlist',
      where: includePurchased ? null : 'purchased = 0',
      orderBy: 'price ASC',
    );
    return rows.map(WishlistItem.fromMap).toList();
  }

  Future<WishlistItem?> markPurchased(int id) async {
    final db = await _db.database;
    final rows = await db.query('wishlist', where: 'id = ?', whereArgs: [id]);
    if (rows.isEmpty) return null;
    await db.update(
      'wishlist',
      {'purchased': 1, 'purchased_at': DateTime.now().toIso8601String()},
      where: 'id = ?',
      whereArgs: [id],
    );
    final updated = await db.query(
      'wishlist',
      where: 'id = ?',
      whereArgs: [id],
    );
    return WishlistItem.fromMap(updated.first);
  }

  Future<bool> update(
    int id, {
    String? name,
    double? price,
    String? note,
  }) async {
    final db = await _db.database;
    final fields = <String, Object?>{};
    if (name != null) fields['name'] = name;
    if (price != null) fields['price'] = price;
    if (note != null) fields['note'] = note;
    if (fields.isEmpty) return false;
    final count = await db.update(
      'wishlist',
      fields,
      where: 'id = ?',
      whereArgs: [id],
    );
    return count > 0;
  }

  Future<bool> remove(int id) async {
    final db = await _db.database;
    final count = await db.delete('wishlist', where: 'id = ?', whereArgs: [id]);
    return count > 0;
  }
}
