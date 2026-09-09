import 'dart:io';

import 'package:another_telephony/telephony.dart';

/// Thin wrapper over the platform SMS inbox.
///
/// Reading is pull-based (scan the inbox for a window of time) rather than
/// push-based. Background SMS delivery needs a background isolate that
/// aggressive OEM battery managers routinely kill, which would silently
/// drop transactions; re-scanning a window on every launch/resume can't
/// miss anything, and the dedupe key makes repeat scans harmless.
class SmsService {
  SmsService._();
  static final SmsService instance = SmsService._();

  final Telephony _telephony = Telephony.instance;

  bool get isSupported => Platform.isAndroid;

  Future<bool> requestPermission() async {
    if (!isSupported) return false;
    return await _telephony.requestSmsPermissions ?? false;
  }

  /// Inbox messages received on or after [since], newest first.
  /// Returns an empty list rather than throwing when permission is absent,
  /// so a denied permission degrades to "no imports" instead of a crash.
  Future<List<SmsMessage>> inboxSince(DateTime since) async {
    if (!isSupported) return const [];
    try {
      return await _telephony.getInboxSms(
        columns: [SmsColumn.ADDRESS, SmsColumn.BODY, SmsColumn.DATE],
        filter: SmsFilter.where(SmsColumn.DATE)
            .greaterThanOrEqualTo(since.millisecondsSinceEpoch.toString()),
        sortOrder: [OrderBy(SmsColumn.DATE, sort: Sort.DESC)],
      );
    } catch (_) {
      // Permission revoked mid-session, or an OEM ROM that blocks the
      // SMS content provider outright.
      return const [];
    }
  }

  /// Foreground-only listener, for instant logging while the app is open.
  /// Anything that arrives while the app is closed is picked up by the next
  /// scan instead.
  void listenWhileOpen(void Function(SmsMessage) onMessage) {
    if (!isSupported) return;
    try {
      _telephony.listenIncomingSms(
        onNewMessage: onMessage,
        listenInBackground: false,
      );
    } catch (_) {
      // Listener is a convenience — scanning still covers these messages.
    }
  }
}
