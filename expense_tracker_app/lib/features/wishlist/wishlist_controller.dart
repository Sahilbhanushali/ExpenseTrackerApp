import 'package:flutter/foundation.dart';

import '../../data/models/transaction.dart';
import '../../data/models/wishlist_item.dart';
import '../../data/repositories/account_repository.dart';
import '../../data/repositories/transaction_repository.dart';
import '../../data/repositories/wishlist_repository.dart';

/// Purchase goals vs. available savings — port of bot.py's wishlist_cmd.
class WishlistController extends ChangeNotifier {
  final WishlistRepository _wishlistRepo;
  final TransactionRepository _txnRepo;
  final AccountRepository _accountRepo;

  WishlistController({
    WishlistRepository? wishlistRepo,
    TransactionRepository? txnRepo,
    AccountRepository? accountRepo,
  })  : _wishlistRepo = wishlistRepo ?? WishlistRepository(),
        _txnRepo = txnRepo ?? TransactionRepository(),
        _accountRepo = accountRepo ?? AccountRepository();

  List<WishlistItem> _items = [];
  List<WishlistItem> get items => _items;

  double _availableSavings = 0;
  double get availableSavings => _availableSavings;

  Future<void> init() => refresh();

  Future<void> refresh() async {
    _items = await _wishlistRepo.list();
    _availableSavings = await _txnRepo.availableSavings();
    notifyListeners();
  }

  Future<void> add(String name, double price, {String? note}) async {
    await _wishlistRepo.add(name, price, note: note);
    await refresh();
  }

  Future<void> buy(int id) async {
    final row = await _wishlistRepo.markPurchased(id);
    if (row == null) return;
    final account = await _accountRepo.defaultAccount();
    final now = DateTime.now();
    final date =
        '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    await _txnRepo.add(Transaction(
      date: date,
      category: 'other',
      amount: row.price,
      note: row.name,
      type: TxnType.expense,
      createdAt: now.toIso8601String(),
      account: account,
    ));
    await refresh();
  }

  Future<void> remove(int id) async {
    await _wishlistRepo.remove(id);
    await refresh();
  }
}
