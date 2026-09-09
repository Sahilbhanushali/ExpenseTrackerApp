import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../core/utils/sms_parser.dart';
import '../../core/utils/sms_service.dart';
import '../../data/models/pending_transaction.dart';
import '../../data/models/transaction.dart';
import '../../data/repositories/account_repository.dart';
import '../../data/repositories/pending_transaction_repository.dart';
import '../../data/repositories/transaction_repository.dart';

/// Outcome of one scan, so the UI can say what actually happened rather
/// than just "done".
class SmsScanResult {
  final int logged;
  final int queued;
  final int skipped;

  /// Rows deleted before re-importing. Only ever non-zero for
  /// [SmsImportController.reimport].
  final int removed;

  const SmsScanResult({
    this.logged = 0,
    this.queued = 0,
    this.skipped = 0,
    this.removed = 0,
  });

  int get total => logged + queued;
}

/// Turns bank SMS into transactions.
///
/// Confident messages (recognisable bank sender + a bank reference number +
/// account digits) are logged straight away; anything weaker is queued for
/// review instead of being trusted. Every write is keyed by
/// [ParsedSms.dedupeKey] so re-scanning the same inbox is a no-op.
class SmsImportController extends ChangeNotifier {
  final TransactionRepository _txnRepo;
  final PendingTransactionRepository _pendingRepo;
  final AccountRepository _accountRepo;
  final SmsService _sms;

  SmsImportController({
    TransactionRepository? txnRepo,
    PendingTransactionRepository? pendingRepo,
    AccountRepository? accountRepo,
    SmsService? smsService,
  }) : _txnRepo = txnRepo ?? TransactionRepository(),
       _pendingRepo = pendingRepo ?? PendingTransactionRepository(),
       _accountRepo = accountRepo ?? AccountRepository(),
       _sms = smsService ?? SmsService.instance;

  /// How far back the very first scan looks. Later scans only need a small
  /// overlapping window because dedupe makes repeats free.
  static const _firstScanWindow = Duration(days: 180);
  static const _routineScanWindow = Duration(days: 7);

  List<PendingTransaction> _pending = [];
  List<PendingTransaction> get pending => _pending;
  int get pendingCount => _pending.length;

  bool _scanning = false;
  bool get isScanning => _scanning;

  bool get isSupported => _sms.isSupported;

  /// Set once the user has granted SMS access and the first backfill ran.
  ///
  /// Persisted, because it survives restarts: without this the app forgot
  /// the feature was on every launch, showed the setup panel again, and
  /// never ran the routine scan.
  static const _enabledKey = 'sms_import_enabled';
  final _storage = const FlutterSecureStorage();

  bool _enabled = false;
  bool get isEnabled => _enabled;

  Future<void> init() async {
    _enabled = await _readEnabled();
    await refresh();
    // Only auto-scan when the feature was already set up — never prompt
    // for SMS permission unasked on first launch.
    if (_enabled) {
      _sms.listenWhileOpen((msg) => ingest(msg.body, sender: msg.address));
      await scan();
    }
  }

  Future<bool> _readEnabled() async {
    try {
      return (await _storage.read(key: _enabledKey)) == 'true';
    } catch (_) {
      // Keystore unavailable (some OEM ROMs after a restore). Treating this
      // as "off" only costs the user one extra tap.
      return false;
    }
  }

  /// Turns the feature off and forgets what it queued, without touching
  /// transactions already logged.
  Future<void> disable() async {
    _enabled = false;
    try {
      await _storage.write(key: _enabledKey, value: 'false');
    } catch (_) {
      // Best-effort: the in-memory flag is already off for this session.
    }
    await _pendingRepo.clearAll();
    await refresh();
  }

  Future<void> refresh() async {
    _pending = await _pendingRepo.listPending();
    notifyListeners();
  }

  /// Asks for SMS access and runs the initial backfill. Returns false when
  /// permission was denied.
  Future<bool> enable() async {
    final granted = await _sms.requestPermission();
    if (!granted) return false;
    _enabled = true;
    try {
      await _storage.write(key: _enabledKey, value: 'true');
    } catch (_) {
      // Not fatal — the feature works this session, just needs re-enabling
      // after a restart.
    }
    _sms.listenWhileOpen((msg) => ingest(msg.body, sender: msg.address));
    await scan(firstRun: true);
    return true;
  }

  /// Throws away everything SMS import has written and imports the inbox
  /// again from scratch.
  ///
  /// The detection rules get stricter over time; rows written by an older,
  /// looser version stay in the ledger until something removes them. This
  /// is that something. Hand-entered transactions are untouched — only
  /// rows marked source 'sms' are removed — and anything genuine is
  /// re-created by the scan that follows.
  Future<SmsScanResult> reimport() async {
    if (_scanning) return const SmsScanResult();
    final removed = await _txnRepo.deleteBySource('sms');
    await _pendingRepo.clearAll();
    final result = await scan(firstRun: true);
    await refresh();
    return SmsScanResult(
      logged: result.logged,
      queued: result.queued,
      skipped: result.skipped,
      removed: removed,
    );
  }

  Future<SmsScanResult> scan({bool firstRun = false}) async {
    if (!_sms.isSupported || _scanning) return const SmsScanResult();
    _scanning = true;
    notifyListeners();

    var logged = 0, queued = 0, skipped = 0;
    try {
      final since = DateTime.now().subtract(
        firstRun ? _firstScanWindow : _routineScanWindow,
      );
      final messages = await _sms.inboxSince(since);

      for (final msg in messages) {
        final body = msg.body;
        if (body == null) continue;
        final outcome = await ingest(
          body,
          sender: msg.address,
          receivedAt: msg.date != null
              ? DateTime.fromMillisecondsSinceEpoch(msg.date!)
              : null,
          notify: false,
        );
        switch (outcome) {
          case SmsIngestOutcome.logged:
            logged++;
          case SmsIngestOutcome.queued:
            queued++;
          case SmsIngestOutcome.skipped:
            skipped++;
        }
      }
      await _pendingRepo.pruneHandled();
    } finally {
      _scanning = false;
      await refresh();
    }
    return SmsScanResult(logged: logged, queued: queued, skipped: skipped);
  }

  /// Parses one message and either logs it, queues it, or drops it.
  Future<SmsIngestOutcome> ingest(
    String? body, {
    String? sender,
    DateTime? receivedAt,
    bool notify = true,
  }) async {
    if (body == null) return SmsIngestOutcome.skipped;

    final parsed = parseTransactionSms(
      body,
      sender: sender,
      receivedAt: receivedAt,
    );
    if (parsed == null) return SmsIngestOutcome.skipped;

    if (await _pendingRepo.isKnown(parsed.dedupeKey())) {
      return SmsIngestOutcome.skipped;
    }

    if (parsed.isAutoLoggable) {
      await _logParsed(parsed, source: 'sms');
      if (notify) await refresh();
      return SmsIngestOutcome.logged;
    }

    await _pendingRepo.add(
      PendingTransaction.fromParsed(
        parsed,
        source: 'sms',
        rawBody: body,
        sender: sender,
      ),
    );
    if (notify) await refresh();
    return SmsIngestOutcome.queued;
  }

  /// Approves a queued item into the ledger.
  Future<void> approve(PendingTransaction p) async {
    await _txnRepo.add(
      Transaction(
        date: _isoDate(p.occurredAt),
        category: p.category,
        amountPaise: p.amountPaise,
        note: p.displayTitle,
        type: p.direction == SmsDirection.credit
            ? TxnType.income
            : TxnType.expense,
        createdAt: DateTime.now().toIso8601String(),
        account: await _accountForTail(p.accountTail),
        source: p.source,
        externalRef: p.externalRef,
      ),
    );
    await _pendingRepo.setStatus(p.id!, 'approved');
    await refresh();
  }

  Future<void> dismiss(PendingTransaction p) async {
    // Kept as a dismissed row rather than deleted, so the next inbox scan
    // doesn't resurrect the message the user just rejected.
    await _pendingRepo.setStatus(p.id!, 'dismissed');
    await refresh();
  }

  Future<void> _logParsed(ParsedSms parsed, {required String source}) async {
    await _txnRepo.add(
      Transaction(
        date: _isoDate(parsed.occurredAt),
        category: parsed.category,
        amountPaise: parsed.amountPaise,
        note: parsed.merchant ?? 'Auto-detected',
        type: parsed.direction == SmsDirection.credit
            ? TxnType.income
            : TxnType.expense,
        createdAt: DateTime.now().toIso8601String(),
        account: await _accountForTail(parsed.accountTail),
        source: source,
        externalRef: parsed.dedupeKey(),
      ),
    );
  }

  /// Matches "A/c XX1234" to an account whose name mentions those digits,
  /// falling back to the default account. Without this every auto-logged
  /// row would pile onto one account and the per-account balances would
  /// drift from reality.
  Future<String?> _accountForTail(String? tail) async {
    final fallback = await _accountRepo.defaultAccount();
    if (tail == null) return fallback;
    final accounts = await _accountRepo.list();
    for (final a in accounts) {
      if (a.name.contains(tail)) return a.name;
    }
    return fallback;
  }

  String _isoDate(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';
}

/// What happened to one parsed message.
enum SmsIngestOutcome { logged, queued, skipped }
