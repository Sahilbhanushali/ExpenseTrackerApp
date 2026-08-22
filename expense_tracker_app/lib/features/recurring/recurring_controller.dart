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
  }) : _recurringRepo = recurringRepo ?? RecurringRepository(),
       _txnRepo = txnRepo ?? TransactionRepository(),
       _accountRepo = accountRepo ?? AccountRepository();

  List<RecurringBill> _bills = [];
  List<RecurringBill> get bills => _bills;

  /// Bills whose day has arrived but haven't been logged this month yet —
  /// surfaced for the user to confirm, never written automatically.
  List<RecurringBill> _due = [];
  List<RecurringBill> get due => _due;

  Future<void> init() => refresh();

  Future<void> refresh() async {
    _bills = await _recurringRepo.list();
    _due = await _recurringRepo.due(DateTime.now());
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
      RecurringBill(
        amount: amount,
        category: category,
        note: note,
        dayOfMonth: dayOfMonth,
        type: type,
      ),
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

  Future<void> update(
    int id, {
    double? amount,
    String? category,
    String? note,
    int? dayOfMonth,
  }) async {
    await _recurringRepo.update(
      id,
      amount: amount,
      category: category,
      note: note,
      dayOfMonth: dayOfMonth,
    );
    if (dayOfMonth != null) {
      final bill = _bills.firstWhere(
        (b) => b.id == id,
        orElse: () =>
            RecurringBill(amount: 0, category: '', dayOfMonth: dayOfMonth),
      );
      await NotificationService.instance.scheduleRecurringReminder(
        billId: id,
        dayOfMonth: dayOfMonth,
        title: bill.type == RecurringType.income
            ? 'Income due'
            : 'Recurring bill due',
        body:
            '${category ?? bill.category} · ${note ?? bill.note ?? 'no note'}',
      );
    }
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
    await _txnRepo.add(
      Transaction(
        date: date,
        category: category,
        amount: monthlyAmount,
        note: note,
        type: TxnType.expense,
        createdAt: now.toIso8601String(),
        account: account,
      ),
    );
    final remainingMonths = months - 1;
    if (remainingMonths > 0) {
      // The installment just logged above already covers this month — stamp
      // last_run_month at creation time (not via markRun, which would also
      // decrement installmentsRemaining a second time for the same
      // payment), otherwise a due day <= today — the common case, since
      // "now" is exactly when someone logs the first payment — makes this
      // brand-new bill show up as due again immediately, inviting a second
      // payment for the same month.
      final month =
          '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}';
      final id = await _recurringRepo.add(
        RecurringBill(
          amount: monthlyAmount,
          category: category,
          note: note,
          dayOfMonth: dueDay ?? now.day,
          installmentsRemaining: remainingMonths,
          lastRunMonth: month,
        ),
      );
      await NotificationService.instance.scheduleRecurringReminder(
        billId: id,
        dayOfMonth: dueDay ?? now.day,
        title: 'EMI due',
        body: '$category · ${note ?? 'no note'}',
      );
    }
    await refresh();
  }

  /// Read-only: refreshes which bills have come due, without logging
  /// anything. Safe to call on every launch/resume — never writes to the
  /// ledger, so re-opening the app can't double-add a bill.
  Future<List<RecurringBill>> refreshDue() async {
    _due = await _recurringRepo.due(DateTime.now());
    notifyListeners();
    return _due;
  }

  /// Logs a single due bill now, on explicit user confirmation (tapping
  /// "Log now" in the UI). Mirrors bot.py's check_recurring() logic, but
  /// only ever runs for one bill, once, when the user asks for it.
  Future<DueBillResult> logDue(RecurringBill bill) async {
    final today = DateTime.now();
    final month =
        '${today.year.toString().padLeft(4, '0')}-${today.month.toString().padLeft(2, '0')}';
    DueBillResult result;

    if (bill.loanId != null) {
      final repayResult = await _txnRepo.repay(bill.loanId!, bill.amount);
      if (repayResult == null) {
        await _recurringRepo.remove(bill.id!);
        result = DueBillResult(
          bill: bill,
          message: 'That loan is gone — reminder removed.',
        );
      } else {
        final finished = await _recurringRepo.markRun(bill.id!, month);
        final loanSettled = repayResult.row.isSettled;
        if (loanSettled && !finished) {
          await _recurringRepo.remove(bill.id!);
        }
        final person = repayResult.row.counterparty ?? 'them';
        result = DueBillResult(
          bill: bill,
          message: loanSettled
              ? 'Applied repayment to $person — fully settled!'
              : 'Applied repayment to $person: ${repayResult.applied}',
        );
      }
    } else {
      final account = await _accountRepo.defaultAccount();
      final isIncome = bill.type == RecurringType.income;
      await _txnRepo.add(
        Transaction(
          date:
              '${today.year.toString().padLeft(4, '0')}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}',
          category: bill.category,
          amount: bill.amount,
          note: bill.note,
          type: isIncome ? TxnType.income : TxnType.expense,
          createdAt: today.toIso8601String(),
          account: account,
        ),
      );
      final finished = await _recurringRepo.markRun(bill.id!, month);
      result = DueBillResult(
        bill: bill,
        message:
            '${isIncome ? 'Logged income' : 'Logged bill'}: '
            '${bill.category} ${bill.amount}'
            '${finished ? ' — that was the last installment' : ''}',
      );
    }

    await refresh();
    return result;
  }
}
