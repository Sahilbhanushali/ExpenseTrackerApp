import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'guardian_models.dart';

/// Thin wrapper over the `spendo/guardian` channel (GuardianChannel.kt).
/// Every call degrades to "unavailable" off Android or when the native side
/// isn't registered (tests), instead of throwing into the UI.
class GuardianPlatform {
  const GuardianPlatform();

  static const _channel = MethodChannel('spendo/guardian');

  bool get supported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  Future<T?> _call<T>(String method, [Object? args]) async {
    if (!supported) return null;
    try {
      return await _channel.invokeMethod<T>(method, args);
    } on MissingPluginException {
      return null;
    } on PlatformException catch (e) {
      debugPrint('Guardian $method failed: ${e.code}');
      return null;
    }
  }

  Future<GuardianState?> getState() async {
    final m = await _call<Map<Object?, Object?>>('getState');
    return m == null ? null : GuardianState.fromMap(m);
  }

  Future<GuardianState?> updateSettings(Map<String, Object> values) async {
    final m = await _call<Map<Object?, Object?>>('updateSettings', values);
    return m == null ? null : GuardianState.fromMap(m);
  }

  Future<bool> pushSnapshot(String json) async =>
      await _call<bool>('pushSnapshot', json) ?? false;

  /// 'ok', 'usageAccess', 'overlay', 'startFailed', or null if unavailable.
  Future<String?> setEnabled(bool enabled) =>
      _call<String>('setEnabled', enabled);

  /// [kind]: usageAccess | overlay | notifications | battery.
  Future<bool> openSettings(String kind) async =>
      await _call<bool>('openSettings', kind) ?? false;

  Future<GuardianState?> resetStats() async {
    final m = await _call<Map<Object?, Object?>>('resetStats');
    return m == null ? null : GuardianState.fromMap(m);
  }

  /// 'ok', 'overlay', 'noData', 'noBudget', or null if unavailable.
  Future<String?> previewOverlay() => _call<String>('previewOverlay');
}
