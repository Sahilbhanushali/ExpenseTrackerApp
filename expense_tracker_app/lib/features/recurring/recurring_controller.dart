import 'package:flutter/foundation.dart';

import '../../core/utils/notification_service.dart';
import '../../data/models/recurring_bill.dart';
import '../../data/models/transaction.dart';
import '../../data/repositories/account_repository.dart';
import '../../data/repositories/recurring_repository.dart';
import '../../data/repositories/transaction_repository.dart';

/// One auto-logged bill or repayment, surfaced to the UI right after
/// checkDue() runs — the in-app equivalent of bot.py's check_recurring()
/// chat notification.
class DueBillResult {
  final RecurringBill bill;
  final String message;
  const DueBillResult({required this.bill, required this.message});
}

/// Recurring bills + EMI — port of bot.py's recurring_cmd/emi_cmd/check_recurring.
/// There's no server JobQueue here, so due bills are checked on app launch/resume.
class RecurringController extends ChangeNotifier {
  final RecurringRepository _recurringRepo;
  final TransactionRepository _txnRepo;
  final AccountRepository _accountRepo;

  RecurringController({
    RecurringRepository? recurringRepo,
    TransactionRepository? txnRepo,
    AccountRepository? accountRepo,
  })  : _recurringRepo = recurringRepo ?? RecurringRepository(),
        _txnRepo = txnRepo ?? TransactionRepository(),
        _accountRepo = accountRepo ?? AccountRepository();

  List<RecurringBill> _bills = [];
  List<RecurringBill> get bills => _bills;

  Future<void> init() => refresh();

  Future<void> refresh() async {
    _bills = await _recurringRepo.list();
    notifyListeners();
  }

  Future<int> addBill({
    required double amount,
    required String category,
    String? note,
    required int dayOfMonth,
    RecurringType type = RecurringType.expense,
  }) async {
    final id = await _recurringRepo.add(
      RecurringBill(amount: amount, category: category, note: note, dayOfMonth: dayOfMonth, type: type),
    );
    await NotificationService.instance.scheduleRecurringReminder(
      billId: id,
      dayOfMonth: dayOfMonth,
      title: type == RecurringType.income ? 'Income due' : 'Recurring bill due',
      body: '$category · ${note ?? 'no note'}',
    );
    await refresh();
    return id;
  }

  Future<void> remove(int id) async {
    await _recurringRepo.remove(id);
    await NotificationService.instance.cancel(id);
    await refresh();
  }

  /// Logs this month's installment now, schedules the rest as a
  /// self-limiting recurring entry — port of emi_cmd.
  Future<void> logEmi({
    required double monthlyAmount,
    required String category,
    String? note,
    required int months,
    int? dueDay,
  }) async {
    final account = await _accountRepo.defaultAccount();
    final now = DateTime.now();
    final date =
        '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    await _txnRepo.add(Transaction(
      date: date,
      category: category,
      amount: monthlyAmount,
      note: note,
      type: TxnType.expense,
      createdAt: now.toIso8601String(),
      account: account,
    ));
    final remainingMonths = months - 1;
    if (remainingMonths > 0) {
      final id = await _recurringRepo.add(RecurringBill(
        amount: monthlyAmount,
        category: category,
        note: note,
        dayOfMonth: dueDay ?? now.day,
        installmentsRemaining: remainingMonths,
      ));
      await NotificationService.instance.scheduleRecurringReminder(
        billId: id,
        dayOfMonth: dueDay ?? now.day,
        title: 'EMI due',
        body: '$category · ${note ?? 'no note'}',
      );
    }
    await refresh();
  }

  /// Auto-logs any recurring bill that's come due and hasn't fired this
  /// month yet — call on app launch/resume. Mirrors check_recurring().
  Future<List<DueBillResult>> checkDue() async {
    final today = DateTime.now();
    final month = '${today.year.toString().padLeft(4, '0')}-${today.month.toString().padLeft(2, '0')}';
    final due = await _recurringRepo.due(today);
    if (due.isEmpty) return [];

    final results = <DueBillResult>[];
    for (final bill in due) {
      if (bill.loanId != null) {
        final result = await _txnRepo.repay(bill.loanId!, bill.amount);
        if (result == null) {
          await _recurringRepo.remove(bill.id!);
          continue;
        }
        final finished = await _recurringRepo.markRun(bill.id!, month);
        final loanSettled = result.row.isSettled;
        if (loanSettled && !finished) {
          await _recurringRepo.remove(bill.id!);
        }
        final person = result.row.counterparty ?? 'them';
        results.add(DueBillResult(
          bill: bill,
          message: loanSettled
              ? 'Auto-applied repayment to $person — fully settled!'
              : 'Auto-applied repayment to $person: ${result.applied}',
        ));
      } else {
        final account = await _accountRepo.defaultAccount();
        final isIncome = bill.type == RecurringType.income;
        await _txnRepo.add(Transaction(
          date: '${today.year.toString().padLeft(4, '0')}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}',
          category: bill.category,
          amount: bill.amount,
          note: bill.note,
          type: isIncome ? TxnType.income : TxnType.expense,
          createdAt: today.toIso8601String(),
          account: account,
        ));
        final finished = await _recurringRepo.markRun(bill.id!, month);
        results.add(DueBillResult(
          bill: bill,
          message: '${isIncome ? 'Auto-logged income' : 'Auto-logged recurring bill'}: '
              '${bill.category} ${bill.amount}'
              '${finished ? ' — that was the last installment' : ''}',
        ));
      }
    }
    await refresh();
    return results;
  }
}
