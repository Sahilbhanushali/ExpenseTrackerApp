import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';

/// PIN + biometric app lock. The PIN itself is stored via
/// flutter_secure_storage (Android Keystore / iOS Keychain), which already
/// encrypts at rest, so no separate hashing scheme is needed here.
class AppLockService {
  AppLockService._();
  static final AppLockService instance = AppLockService._();

  static const _pinKey = 'app_lock_pin';
  static const _enabledKey = 'app_lock_enabled';

  final _storage = const FlutterSecureStorage();
  final _localAuth = LocalAuthentication();

  Future<bool> isEnabled() async =>
      (await _storage.read(key: _enabledKey)) == 'true';

  Future<bool> hasPin() async => (await _storage.read(key: _pinKey)) != null;

  Future<void> setPin(String pin) async {
    await _storage.write(key: _pinKey, value: pin);
    await _storage.write(key: _enabledKey, value: 'true');
  }

  Future<bool> verifyPin(String pin) async =>
      (await _storage.read(key: _pinKey)) == pin;

  /// Disables the lock and forgets the PIN.
  Future<void> disable() async {
    await _storage.delete(key: _pinKey);
    await _storage.write(key: _enabledKey, value: 'false');
  }

  Future<bool> canUseBiometrics() async {
    try {
      return await _localAuth.canCheckBiometrics &&
          await _localAuth.isDeviceSupported();
    } catch (_) {
      return false;
    }
  }

  Future<bool> authenticateWithBiometrics() async {
    try {
      return await _localAuth.authenticate(
        localizedReason: 'Unlock Expense Tracker',
        biometricOnly: true,
      );
    } catch (_) {
      return false;
    }
  }
}
