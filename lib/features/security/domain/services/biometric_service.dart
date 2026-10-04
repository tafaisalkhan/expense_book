import 'package:flutter/foundation.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

class BiometricService {
  final LocalAuthentication _auth = LocalAuthentication();
  static const String _prefKeyAppLock = 'app_lock_security_enabled_v1';

  /// Check if device hardware supports biometrics or device PIN/Pattern
  Future<bool> canCheckBiometrics() async {
    if (kIsWeb) return false;
    try {
      final bool canAuthenticateWithBiometrics = await _auth.canCheckBiometrics;
      final bool isDeviceSupported = await _auth.isDeviceSupported();
      return canAuthenticateWithBiometrics || isDeviceSupported;
    } catch (_) {
      return false;
    }
  }

  /// Get list of available biometric hardware features (fingerprint, face, etc.)
  Future<List<BiometricType>> getAvailableBiometrics() async {
    if (kIsWeb) return [];
    try {
      return await _auth.getAvailableBiometrics();
    } catch (_) {
      return [];
    }
  }

  /// Check whether App Lock is enabled by user in settings (defaults to false)
  Future<bool> isAppLockEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.containsKey(_prefKeyAppLock)) {
      return prefs.getBool(_prefKeyAppLock) ?? false;
    }
    return false;
  }

  /// Enable or disable App Lock in SharedPreferences
  Future<void> setAppLockEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefKeyAppLock, enabled);
  }

  /// Prompt user for Fingerprint / Face ID / Device Passcode authentication
  Future<bool> authenticate({String reason = 'Authenticate to access MyExpense financial records'}) async {
    if (kIsWeb) return true;
    try {
      final bool authenticated = await _auth.authenticate(
        localizedReason: reason,
        biometricOnly: false,
        persistAcrossBackgrounding: true,
      );
      return authenticated;
    } catch (_) {
      return false;
    }
  }
}
