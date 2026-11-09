import 'package:flutter/foundation.dart';

import '../../data/models/credit_card.dart';
import '../../data/models/transaction.dart';
import '../../data/repositories/card_repository.dart';
import '../../data/repositories/reconciliation_repository.dart';
import '../expenses/expenses_controller.dart';

/// A card with what's owed and its latest statement.
class CardSummary {
  final CreditCard card;

  /// What's owed on the card now (statements and unbilled), in paise.
  final int outstanding;
  final CardStatement? latest;

  const CardSummary({
    required this.card,
    required this.outstanding,
    this.latest,
  });

  int get available => card.limitPaise - outstanding;
}

class CardsController extends ChangeNotifier {
  final CardRepository _repo;
  final ReconciliationRepository _recon;
  CardsController([CardRepository? repo, ReconciliationRepository? recon])
    : _repo = repo ?? CardRepository(),
      _recon = recon ?? ReconciliationRepository();

  /// Checks what's owed against the card's own figure; with [adjust], a
  /// correction (never spending) brings the app in line.
  Future<Reconciliation> reconcile(
    int cardId, {
    required int actualOwedPaise,
    bool adjust = false,
    String? note,
  }) async {
    final r = await _recon.reconcileCard(
      cardId,
      actualOwedPaise: actualOwedPaise,
      adjust: adjust,
      note: note,
    );
    await refresh();
    return r;
  }

  Future<List<Reconciliation>> checks(int cardId) =>
      _recon.history('card', cardId);

  ExpensesController? _expenses;
  void attach(ExpensesController expenses) {
    _expenses?.removeListener(refresh);
    _expenses = expenses..addListener(refresh);
  }

  List<CardSummary> _cards = [];
  List<CardSummary> get cards => _cards;
  List<CardSummary> get active => _cards.where((c) => c.card.active).toList();

  /// Owed across all cards — a liability in net worth. In paise.
  int get outstanding => _cards.fold(0, (s, c) => s + c.outstanding);

  Future<void> init() => refresh();

  Future<void> refresh() async {
    final cards = await _repo.list();
    final owed = await _repo.outstanding();
    _cards = [
      for (final c in cards)
        CardSummary(
          card: c,
          outstanding: owed[c.id] ?? 0,
          latest: (await _repo.statements(c.id!)).firstOrNull,
        ),
    ];
    notifyListeners();
  }

  Future<void> _changed() async {
    await refresh();
    await _expenses?.refresh();
  }

  /// All throw [CardException] with a message for the user.
  Future<void> save(CreditCard c) async {
    await _repo.save(c);
    await refresh();
  }

  Future<List<CardStatement>> statements(int cardId) =>
      _repo.statements(cardId);
  Future<List<CardEmi>> emis(int cardId) => _repo.emis(cardId);
  Future<List<Transaction>> spending(int cardId) => _repo.spending(cardId);

  Future<void> addStatement(
    CardStatement s, {
    Map<int, ({int? principal, int? interest})> billedEmis = const {},
    int newCharges = 0,
  }) async {
    await _repo.addStatement(s, billedEmis: billedEmis, newCharges: newCharges);
    await _changed();
  }

  Future<void> removeStatement(int id) async {
    await _repo.removeStatement(id);
    await _changed();
  }

  Future<void> pay({
    required int cardId,
    required String fromAccount,
    required int amountPaise,
    int? statementId,
    String? reference,
  }) async {
    await _repo.pay(
      cardId: cardId,
      fromAccount: fromAccount,
      amountPaise: amountPaise,
      date: DateTime.now(),
      statementId: statementId,
      reference: reference,
    );
    await _changed();
  }

  Future<void> addEmi(CardEmi e) async {
    await _repo.addEmi(e);
    await refresh();
  }

  @override
  void dispose() {
    _expenses?.removeListener(refresh);
    super.dispose();
  }
}
