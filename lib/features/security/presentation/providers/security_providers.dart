import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:myexpence/features/security/domain/services/biometric_service.dart';

class SecurityState {
  final bool isAppLockEnabled;
  final bool isAuthenticated;
  final bool isHardwareAvailable;

  const SecurityState({
    this.isAppLockEnabled = false,
    this.isAuthenticated = false,
    this.isHardwareAvailable = false,
  });

  SecurityState copyWith({
    bool? isAppLockEnabled,
    bool? isAuthenticated,
    bool? isHardwareAvailable,
  }) {
    return SecurityState(
      isAppLockEnabled: isAppLockEnabled ?? this.isAppLockEnabled,
      isAuthenticated: isAuthenticated ?? this.isAuthenticated,
      isHardwareAvailable: isHardwareAvailable ?? this.isHardwareAvailable,
    );
  }
}

class SecurityNotifier extends StateNotifier<SecurityState> {
  final BiometricService _biometricService;

  SecurityNotifier(this._biometricService) : super(const SecurityState()) {
    _init();
  }

  Future<void> _init() async {
    final enabled = await _biometricService.isAppLockEnabled();
    final hardware = await _biometricService.canCheckBiometrics();

    state = state.copyWith(
      isAppLockEnabled: enabled,
      isHardwareAvailable: hardware,
      isAuthenticated: !enabled, // If lock is disabled, user is automatically authenticated
    );
  }

  /// Toggle App Lock setting
  Future<bool> toggleAppLock(bool enable) async {
    if (enable) {
      // Require an immediate successful fingerprint/PIN scan before allowing user to turn ON lock
      final ok = await _biometricService.authenticate(
        reason: 'Authenticate your fingerprint or device PIN to enable App Lock',
      );
      if (!ok) return false;
    }

    await _biometricService.setAppLockEnabled(enable);
    state = state.copyWith(
      isAppLockEnabled: enable,
      isAuthenticated: !enable,
    );
    return true;
  }

  /// Authenticate user via Fingerprint / Face ID / PIN
  Future<bool> authenticate() async {
    final success = await _biometricService.authenticate(
      reason: 'Scan your Fingerprint or enter Device PIN to unlock MyExpense',
    );
    if (success) {
      state = state.copyWith(isAuthenticated: true);
    }
    return success;
  }

  /// Lock app when backgrounded
  void lockApp() {
    if (state.isAppLockEnabled) {
      state = state.copyWith(isAuthenticated: false);
    }
  }
}

final biometricServiceProvider = Provider<BiometricService>((ref) {
  return BiometricService();
});

final securityNotifierProvider = StateNotifierProvider<SecurityNotifier, SecurityState>((ref) {
  final bioService = ref.watch(biometricServiceProvider);
  return SecurityNotifier(bioService);
});
