import 'package:flutter/foundation.dart';

import '../../core/finance/calendar_events.dart';
import '../../core/finance/salary_cycle.dart';
import '../../core/utils/money_formatter.dart';
import '../../core/utils/notification_service.dart';
import '../../data/models/recurring_bill.dart';
import '../accounts/accounts_controller.dart';
import '../allocation/allocation_needs.dart';
import '../cards/cards_controller.dart';
import '../cycles/cycle_card.dart';
import '../cycles/cycle_controller.dart';
import '../income/income_controller.dart';
import '../loans/loans_controller.dart';
import '../recurring/recurring_controller.dart';
import '../settings/settings_controller.dart';

/// Every dated money event — salary, expected income, EMIs, card dues and
/// statement days, recurring bills, planned transfers — from live data,
/// plus one reminder per obligation.
class CalendarController extends ChangeNotifier {
  /// How far ahead events are built.
  static const horizonDays = 60;

  final List<ChangeNotifier> _sources = [];
  CycleController? _cycles;
  IncomeController? _income;
  LoansController? _loans;
  CardsController? _cards;
  RecurringController? _recurring;
  AccountsController? _accounts;
  SettingsController? _settings;

  /// Tests may skip scheduling notifications.
  final bool scheduleReminders;
  CalendarController({this.scheduleReminders = true});

  List<FinEvent> _events = [];
  List<FinEvent> get events => _events;

  void attach({
    required CycleController cycles,
    required IncomeController income,
    required LoansController loans,
    required CardsController cards,
    required RecurringController recurring,
    required AccountsController accounts,
    required SettingsController settings,
  }) {
    for (final s in _sources) {
      s.removeListener(refresh);
    }
    _cycles = cycles;
    _income = income;
    _loans = loans;
    _cards = cards;
    _recurring = recurring;
    _accounts = accounts;
    _settings = settings;
    _sources
      ..clear()
      ..addAll([cycles, income, loans, cards, recurring, accounts, settings]);
    for (final s in _sources) {
      s.addListener(refresh);
    }
  }

  /// The next [days] days (today included) plus anything overdue.
  List<FinEvent> upcoming(int days, {DateTime? today}) {
    final t = dateOnly(today ?? DateTime.now());
    return eventsBetween(events, t, t.add(Duration(days: days - 1)), t);
  }

  Future<void> refresh() async {
    if (_settings == null) return;
    final today = dateOnly(DateTime.now());
    _events = build(today);
    notifyListeners();
    if (scheduleReminders) await _syncReminders();
  }

  @visibleForTesting
  List<FinEvent> build(DateTime today) {
    final end = today.add(const Duration(days: horizonDays));
    final cur = _settings!.config.currency;
    String fmt(int p) => formatMoney(p, cur);
    final out = <FinEvent>[];

    final cycle = _cycles?.current;
    final standing = cycle?.standing;
    if (cycle != null && standing != null) {
      final w = standing.window;
      final expected = _cycles!.profile.expectedNetPaise;
      out.add(
        FinEvent(
          key: 'salary:${isoDate(cycle.cycle.start)}',
          date: standing.salaryLate ? today : w.earliest,
          kind: EventKind.salary,
          title: standing.salaryLate ? 'Salary is late' : 'Salary expected',
          amount: expected,
          flow: MoneyFlow.incoming,
          detail: standing.salaryLate
              ? 'Expected by ${shortDate(w.latest)}. Record it when it arrives — that starts the next cycle.'
              : 'Between ${shortDate(w.earliest)} and ${shortDate(w.latest)}. '
                    'Recording it starts the next salary cycle.',
        ),
      );
    }

    for (final e in _income?.pending ?? const []) {
      out.add(
        FinEvent(
          key: 'income:${e.id}',
          date: e.expectedDate,
          kind: EventKind.income,
          title: e.note ?? 'Expected income',
          amount: e.amountPaise,
          flow: MoneyFlow.incoming,
          detail: 'Not counted until you mark it received.',
        ),
      );
    }

    for (final l in _loans?.active ?? const []) {
      for (final i in l.due.where((i) => !i.dueDate.isAfter(end))) {
        out.add(
          FinEvent(
            key: 'emi:${l.loan.id}:${i.id}',
            date: i.dueDate,
            kind: EventKind.emi,
            title: '${l.loan.name} EMI ${i.seq}',
            amount: i.remaining,
            flow: MoneyFlow.outgoing,
            detail: l.loan.account == null ? null : 'From ${l.loan.account}',
          ),
        );
      }
    }

    for (final c in _cards?.cards ?? const []) {
      final st = c.latest;
      if (st != null) {
        final s = st.standing(today);
        if (s.remaining > 0) {
          out.add(
            FinEvent(
              key: 'card:${c.card.id}:${st.id}',
              date: st.dueDate,
              kind: EventKind.cardDue,
              title: '${c.card.name} bill',
              amount: s.remaining,
              flow: MoneyFlow.outgoing,
              detail: s.minimumRemaining > 0
                  ? 'Minimum ${fmt(s.minimumRemaining)}. Paying less than the total charges interest.'
                  : null,
            ),
          );
        }
      }
      final day = c.card.statementDay;
      if (day != null && c.card.active) {
        final next = nextDayOfMonth(day, today);
        out.add(
          FinEvent(
            key: 'stmt:${c.card.id}:${isoDate(next)}',
            date: next,
            kind: EventKind.statement,
            title: '${c.card.name} statement',
            flow: MoneyFlow.info,
            detail: 'Add it in Credit cards when it arrives.',
          ),
        );
      }
    }

    for (final b in _recurring?.bills ?? const <RecurringBill>[]) {
      if (!b.active || b.loanId != null) continue;
      final due = nextBillDate(b, today);
      if (due.isAfter(end)) continue;
      final income = b.type == RecurringType.income;
      out.add(
        FinEvent(
          key: 'bill:${b.id}:${due.year}-${due.month}',
          date: due,
          kind: income ? EventKind.billIncome : EventKind.bill,
          title: b.note?.isNotEmpty == true ? b.note! : b.category,
          amount: b.amountPaise,
          flow: income ? MoneyFlow.incoming : MoneyFlow.outgoing,
        ),
      );
    }

    for (final t in _accounts?.planned ?? const []) {
      final d = DateTime.parse(t.date);
      out.add(
        FinEvent(
          key: 'transfer:${t.id}',
          date: d.isBefore(today) ? today : d,
          kind: EventKind.transfer,
          title: '${t.fromAccount} → ${t.toAccount}',
          amount: t.amountPaise,
          flow: MoneyFlow.info,
          detail: 'Planned — mark it done once it happens at the bank.',
        ),
      );
    }
    return out;
  }

  /// One reminder per obligation, keyed by the event. Recurring bills keep
  /// their own monthly reminder, so they aren't scheduled twice.
  Future<void> _syncReminders() async => NotificationService.instance
      .syncCalendarReminders(reminderPlan(DateTime.now()));

  /// The reminders that should exist right now — at most one per event.
  @visibleForTesting
  List<({int id, DateTime at, String title, String body})> reminderPlan(
    DateTime now,
  ) {
    final config = _settings!.config;
    final cur = config.currency;
    final wanted = <({int id, DateTime at, String title, String body})>[];
    if (config.remindersOn) {
      for (final e in _events) {
        if (e.kind == EventKind.bill || e.kind == EventKind.billIncome) {
          continue;
        }
        final at = reminderTime(e, config.reminderDaysBefore, now);
        if (at == null) continue;
        final when = config.reminderDaysBefore == 0
            ? 'today'
            : config.reminderDaysBefore == 1
            ? 'tomorrow'
            : 'on ${shortDate(e.date)}';
        wanted.add((
          id: reminderId(e.key),
          at: at,
          title: e.title,
          body: [
            if (e.amount != null) formatMoney(e.amount!, cur),
            switch (e.flow) {
              MoneyFlow.outgoing => 'due $when',
              MoneyFlow.incoming => 'expected $when',
              MoneyFlow.info => when,
            },
          ].join(' '),
        ));
      }
    }
    return wanted;
  }

  @override
  void dispose() {
    for (final s in _sources) {
      s.removeListener(refresh);
    }
    super.dispose();
  }
}
