import 'package:sqflite/sqflite.dart' show DatabaseExecutor;

import '../../core/finance/cards.dart';
import '../../core/finance/salary_cycle.dart';
import '../datasources/app_database.dart';
import '../models/credit_card.dart';
import '../models/movement.dart';
import '../models/transaction.dart';
import 'account_repository.dart';
import 'audit_log.dart';

class CardException implements Exception {
  final String message;
  const CardException(this.message);
  @override
  String toString() => message;
}

/// Credit cards, their statements, bill payments and card EMIs.
///
/// Accounting (docs/finance-upgrade-plan.md §3.1):
/// - a card purchase is an expense on the card (`txns.card_id`), counted
///   once on its date; it never touches a bank balance;
/// - a bill payment is a movement bank → card (rule 2: not an expense);
/// - an EMI installment on a statement is principal already counted at
///   purchase — only its interest, fees and taxes become expenses
///   (rule 10).
class CardRepository {
  final AppDatabase _db;
  CardRepository([AppDatabase? db]) : _db = db ?? AppDatabase.instance;

  Future<List<CreditCard>> list() async {
    final db = await _db.database;
    return (await db.query(
      'credit_cards',
      orderBy: 'id',
    )).map(CreditCard.fromMap).toList();
  }

  Future<int> save(CreditCard c) async {
    if (c.name.trim().isEmpty) {
      throw const CardException('Give the card a name.');
    }
    if (c.last4 != null && !RegExp(r'^\d{4}$').hasMatch(c.last4!)) {
      throw const CardException('Last four digits must be exactly 4 numbers.');
    }
    if (c.limitPaise < 0 || c.openingOutstandingPaise < 0) {
      throw const CardException("Amounts can't be negative.");
    }
    final db = await _db.database;
    return db.transaction((txn) async {
      final row = c.toMap();
      if (c.id == null) {
        final id = await txn.insert('credit_cards', {
          ...row,
          'created_at': DateTime.now().toIso8601String(),
        });
        await writeAudit(
          txn,
          entity: 'card',
          entityId: id,
          action: 'create',
          after: row,
        );
        return id;
      }
      final before = await txn.query(
        'credit_cards',
        where: 'id = ?',
        whereArgs: [c.id],
      );
      await txn.update('credit_cards', row, where: 'id = ?', whereArgs: [c.id]);
      await writeAudit(
        txn,
        entity: 'card',
        entityId: c.id,
        action: 'update',
        before: before.firstOrNull,
        after: row,
      );
      return c.id!;
    });
  }

  /// Card id → what's owed on it now, in paise: opening balance + spending
  /// on the card (net of refunds) − completed bill payments.
  Future<Map<int, int>> outstanding() async {
    final db = await _db.database;
    final out = <int, int>{
      for (final r in await db.query('credit_cards'))
        r['id'] as int: r['opening_outstanding'] as int,
    };
    final spend = await db.rawQuery(
      "SELECT card_id, SUM(CASE WHEN type = 'refund' THEN -amount ELSE amount END) AS t "
      "FROM txns WHERE card_id IS NOT NULL AND type IN ('expense', 'refund') "
      'GROUP BY card_id',
    );
    for (final r in spend) {
      final id = r['card_id'] as int;
      if (out.containsKey(id)) {
        out[id] = out[id]! + ((r['t'] as num?)?.round() ?? 0);
      }
    }
    final paid = await db.rawQuery(
      "SELECT p.owner_id AS id, SUM(p.amount) AS t FROM postings p "
      "JOIN movements m ON m.id = p.movement_id "
      "WHERE p.owner_type = 'card' AND m.status = 'completed' GROUP BY p.owner_id",
    );
    for (final r in paid) {
      final id = r['id'] as int;
      if (out.containsKey(id)) {
        out[id] = out[id]! - ((r['t'] as num?)?.round() ?? 0);
      }
    }
    return out;
  }

  Future<List<CardStatement>> statements(int cardId) async {
    final db = await _db.database;
    final rows = await db.rawQuery(
      'SELECT s.*, (SELECT SUM(m.amount) FROM movements m '
      "WHERE m.link_type = 'statement' AND m.link_id = s.id "
      "AND m.status = 'completed') AS paid "
      'FROM card_statements s WHERE s.card_id = ? ORDER BY s.period_end DESC',
      [cardId],
    );
    return rows.map(_statementFrom).toList();
  }

  static CardStatement _statementFrom(Map<String, Object?> r) => CardStatement(
    id: r['id'] as int,
    cardId: r['card_id'] as int,
    periodStart: DateTime.parse(r['period_start'] as String),
    periodEnd: DateTime.parse(r['period_end'] as String),
    generatedOn: DateTime.parse(r['generated_on'] as String),
    dueDate: DateTime.parse(r['due_date'] as String),
    figures: StatementFigures(
      previousBalance: r['previous_balance'] as int,
      payments: r['payments'] as int,
      refunds: r['refunds'] as int,
      purchases: r['purchases'] as int,
      emiInstallments: r['emi_amount'] as int,
      charges: r['charges'] as int,
      totalDue: r['total_due'] as int,
      minimumDue: r['minimum_due'] as int,
    ),
    note: r['note'] as String?,
    paidPaise: (r['paid'] as num?)?.round() ?? 0,
  );

  /// Records a statement exactly as printed.
  ///
  /// [billedEmis] are the card EMIs whose installment appears on it (with
  /// the principal/interest split if the statement shows one). Each EMI
  /// can be billed once per statement.
  ///
  /// [newCharges] is interest, fees and GST on this statement that isn't
  /// already logged; it's recorded once as an expense on the card dated the
  /// statement day (rule 4). Returns the statement id.
  Future<int> addStatement(
    CardStatement s, {
    Map<int, ({int? principal, int? interest})> billedEmis = const {},
    int newCharges = 0,
  }) async {
    final f = s.figures;
    if (f.totalDue < 0 || f.minimumDue < 0 || newCharges < 0) {
      throw const CardException("Amounts can't be negative.");
    }
    if (f.minimumDue > f.totalDue) {
      throw const CardException(
        "The minimum due can't be more than the total.",
      );
    }
    if (s.periodEnd.isBefore(s.periodStart)) {
      throw const CardException('The period ends before it starts.');
    }
    if (s.dueDate.isBefore(s.generatedOn)) {
      throw const CardException('The due date is before the statement date.');
    }
    final db = await _db.database;
    return db.transaction((txn) async {
      final dup = await txn.query(
        'card_statements',
        where: 'card_id = ? AND period_end = ?',
        whereArgs: [s.cardId, isoDate(s.periodEnd)],
      );
      if (dup.isNotEmpty) {
        throw const CardException(
          'A statement for that period is already saved.',
        );
      }
      final row = {
        'card_id': s.cardId,
        'period_start': isoDate(s.periodStart),
        'period_end': isoDate(s.periodEnd),
        'generated_on': isoDate(s.generatedOn),
        'due_date': isoDate(s.dueDate),
        'total_due': f.totalDue,
        'minimum_due': f.minimumDue,
        'previous_balance': f.previousBalance,
        'payments': f.payments,
        'refunds': f.refunds,
        'purchases': f.purchases,
        'emi_amount': f.emiInstallments,
        'charges': f.charges,
        'note': s.note,
        'created_at': DateTime.now().toIso8601String(),
      };
      final id = await txn.insert('card_statements', row);
      for (final MapEntry(key: emiId, value: split) in billedEmis.entries) {
        await txn.insert('card_statement_emis', {
          'statement_id': id,
          'emi_id': emiId,
          'principal': split.principal,
          'interest': split.interest,
        });
      }
      if (newCharges > 0) {
        await txn.insert(
          'txns',
          Transaction(
            date: isoDate(s.generatedOn),
            category: 'fees',
            amountPaise: newCharges,
            note: 'Card interest, fees & taxes',
            type: TxnType.expense,
            createdAt: DateTime.now().toIso8601String(),
            source: 'statement',
            externalRef: 'statement-$id-charges',
            cardId: s.cardId,
          ).toMap()..remove('id'),
        );
      }
      await writeAudit(
        txn,
        entity: 'statement',
        entityId: id,
        action: 'create',
        after: row,
      );
      return id;
    });
  }

  /// Removes a statement that has no payments yet, with its billed-EMI
  /// rows and the charges it recorded.
  Future<void> removeStatement(int id) async {
    final db = await _db.database;
    await db.transaction((txn) async {
      final paid = await txn.query(
        'movements',
        where:
            "link_type = 'statement' AND link_id = ? AND status = 'completed'",
        whereArgs: [id],
      );
      if (paid.isNotEmpty) {
        throw const CardException(
          'Payments are linked to this statement, so it can’t be deleted.',
        );
      }
      final before = await txn.query(
        'card_statements',
        where: 'id = ?',
        whereArgs: [id],
      );
      await txn.delete(
        'card_statement_emis',
        where: 'statement_id = ?',
        whereArgs: [id],
      );
      await txn.delete(
        'txns',
        where: 'external_ref = ?',
        whereArgs: ['statement-$id-charges'],
      );
      await txn.delete('card_statements', where: 'id = ?', whereArgs: [id]);
      await writeAudit(
        txn,
        entity: 'statement',
        entityId: id,
        action: 'delete',
        before: before.firstOrNull,
      );
    });
  }

  /// Pays the card from a bank account: one movement, −account +card,
  /// linked to [statementId] when given. A liability settlement, never an
  /// expense. Returns the movement id.
  Future<int> pay({
    required int cardId,
    required String fromAccount,
    required int amountPaise,
    required DateTime date,
    int? statementId,
    String? reference,
  }) async {
    if (amountPaise <= 0) {
      throw const CardException('Enter the amount you paid.');
    }
    final db = await _db.database;
    return db.transaction((txn) async {
      final acc = await txn.query(
        'accounts',
        columns: ['id'],
        where: 'name = ?',
        whereArgs: [fromAccount],
      );
      if (acc.isEmpty) {
        throw const CardException('Pick the account you paid from.');
      }
      final card = await txn.query(
        'credit_cards',
        where: 'id = ?',
        whereArgs: [cardId],
      );
      if (card.isEmpty) {
        throw const CardException('That card no longer exists.');
      }
      final movement = {
        'ref': AccountRepository.newRef('card'),
        'kind': MovementKind.cardPayment.name,
        'date': isoDate(date),
        'amount': amountPaise,
        'status': MovementStatus.completed.name,
        'note': reference == null || reference.trim().isEmpty
            ? 'Card bill · ${card.first['name']}'
            : 'Card bill · ${card.first['name']} · $reference',
        'created_at': DateTime.now().toIso8601String(),
        'completed_at': DateTime.now().toIso8601String(),
        'link_type': statementId == null ? null : 'statement',
        'link_id': statementId,
      };
      final id = await txn.insert('movements', movement);
      await txn.insert(
        'postings',
        Posting(
          movementId: id,
          ownerType: PostingOwner.account,
          ownerId: acc.first['id'] as int,
          amountPaise: -amountPaise,
        ).toMap(),
      );
      await txn.insert(
        'postings',
        Posting(
          movementId: id,
          ownerType: PostingOwner.card,
          ownerId: cardId,
          amountPaise: amountPaise,
        ).toMap(),
      );
      await writeAudit(
        txn,
        entity: 'movement',
        entityId: id,
        action: 'card_payment',
        after: movement,
      );
      return id;
    });
  }

  Future<List<CardEmi>> emis(int cardId) async {
    final db = await _db.database;
    final rows = await db.rawQuery(
      'SELECT e.*, '
      '(SELECT COUNT(*) FROM card_statement_emis b WHERE b.emi_id = e.id) AS billed, '
      // Null as soon as any billed installment lacks a principal figure.
      '(SELECT CASE WHEN COUNT(*) = COUNT(b.principal) THEN SUM(b.principal) END '
      'FROM card_statement_emis b WHERE b.emi_id = e.id) AS principal_billed '
      'FROM card_emis e WHERE e.card_id = ? ORDER BY e.purchase_date DESC',
      [cardId],
    );
    return [
      for (final r in rows)
        CardEmi(
          id: r['id'] as int,
          cardId: r['card_id'] as int,
          purchaseTxnId: r['purchase_txn_id'] as int?,
          description: r['description'] as String,
          purchaseAmount: r['purchase_amount'] as int,
          purchaseDate: DateTime.parse(r['purchase_date'] as String),
          tenureMonths: r['tenure_months'] as int,
          installment: r['installment'] as int,
          interestTotal: r['interest_total'] as int?,
          fees: r['fees'] as int?,
          taxes: r['taxes'] as int?,
          active: r['status'] == 'active',
          billed: r['billed'] as int,
          principalBilled: (r['billed'] as int) == 0
              ? 0
              : (r['principal_billed'] as num?)?.round(),
        ),
    ];
  }

  /// Converts a purchase on the card into an EMI. The purchase stays the one
  /// expense (rule 10); the EMI only tracks installments left to be billed.
  Future<int> addEmi(CardEmi e) async {
    if (e.purchaseAmount <= 0 || e.installment <= 0 || e.tenureMonths <= 0) {
      throw const CardException(
        'Enter the purchase amount, installment and months.',
      );
    }
    final db = await _db.database;
    return db.transaction((txn) async {
      if (e.purchaseTxnId != null) {
        final p = await txn.query(
          'txns',
          where: "id = ? AND card_id = ? AND type = 'expense'",
          whereArgs: [e.purchaseTxnId, e.cardId],
        );
        if (p.isEmpty) {
          throw const CardException(
            'That purchase isn’t an expense on this card.',
          );
        }
        final already = await txn.query(
          'card_emis',
          where: 'purchase_txn_id = ?',
          whereArgs: [e.purchaseTxnId],
        );
        if (already.isNotEmpty) {
          throw const CardException('That purchase is already on EMI.');
        }
      }
      final row = {
        'card_id': e.cardId,
        'purchase_txn_id': e.purchaseTxnId,
        'description': e.description,
        'purchase_amount': e.purchaseAmount,
        'purchase_date': isoDate(e.purchaseDate),
        'tenure_months': e.tenureMonths,
        'installment': e.installment,
        'interest_total': e.interestTotal,
        'fees': e.fees,
        'taxes': e.taxes,
        'status': 'active',
        'created_at': DateTime.now().toIso8601String(),
      };
      final id = await txn.insert('card_emis', row);
      await writeAudit(
        txn,
        entity: 'card_emi',
        entityId: id,
        action: 'create',
        after: row,
      );
      return id;
    });
  }

  /// Expenses on [cardId], newest first.
  Future<List<Transaction>> spending(int cardId, {int limit = 30}) async {
    final db = await _db.database;
    final rows = await db.query(
      'txns',
      where: 'card_id = ?',
      whereArgs: [cardId],
      orderBy: 'date DESC, id DESC',
      limit: limit,
    );
    return rows.map(Transaction.fromMap).toList();
  }

  /// For statement checks: what the app thinks was spent on the card
  /// between two dates (net of refunds).
  Future<int> spentBetween(
    DatabaseExecutor? ex,
    int cardId,
    DateTime a,
    DateTime b,
  ) async {
    final db = ex ?? await _db.database;
    final r = await db.rawQuery(
      "SELECT SUM(CASE WHEN type = 'refund' THEN -amount ELSE amount END) AS t "
      "FROM txns WHERE card_id = ? AND type IN ('expense', 'refund') "
      'AND date >= ? AND date <= ?',
      [cardId, isoDate(a), isoDate(b)],
    );
    return (r.first['t'] as num?)?.round() ?? 0;
  }
}
