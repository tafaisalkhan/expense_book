import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:myexpence/core/theme/app_theme.dart';
import 'package:myexpence/features/auth/domain/models/auth_user.dart';
import 'package:myexpence/features/auth/presentation/providers/auth_providers.dart';
import 'package:myexpence/features/security/presentation/providers/security_providers.dart';

class AppLockOverlayWrapper extends ConsumerStatefulWidget {
  final Widget child;

  const AppLockOverlayWrapper({super.key, required this.child});

  @override
  ConsumerState<AppLockOverlayWrapper> createState() => _AppLockOverlayWrapperState();
}

class _AppLockOverlayWrapperState extends ConsumerState<AppLockOverlayWrapper> with WidgetsBindingObserver {
  bool _isAuthenticating = false;
  Timer? _delayTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _delayTimer?.cancel();
      _delayTimer = Timer(const Duration(milliseconds: 300), () {
        if (mounted) {
          _checkAndPromptAuth();
        }
      });
    });
  }

  @override
  void dispose() {
    _delayTimer?.cancel();
    _delayTimer = null;
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState lifecycleState) {
    if (lifecycleState == AppLifecycleState.paused || lifecycleState == AppLifecycleState.hidden) {
      // Re-lock app when user switches apps or locks phone screen
      ref.read(securityNotifierProvider.notifier).lockApp();
    } else if (lifecycleState == AppLifecycleState.resumed) {
      _delayTimer?.cancel();
      _delayTimer = Timer(const Duration(milliseconds: 300), () {
        if (mounted) {
          _checkAndPromptAuth();
        }
      });
    }
  }

  Future<void> _checkAndPromptAuth({bool force = false}) async {
    final secState = ref.read(securityNotifierProvider);
    if (secState.isAppLockEnabled && !secState.isAuthenticated && (!_isAuthenticating || force)) {
      _isAuthenticating = true;
      try {
        await ref.read(securityNotifierProvider.notifier).authenticate();
      } finally {
        if (mounted) {
          setState(() {
            _isAuthenticating = false;
          });
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<SecurityState>(securityNotifierProvider, (previous, next) {
      if (next.isAppLockEnabled && !next.isAuthenticated) {
        _checkAndPromptAuth();
      }
    });

    ref.listen<AuthUser>(authProvider, (previous, next) {
      if (next.isLoggedIn && (previous == null || !previous.isLoggedIn)) {
        ref.read(securityNotifierProvider.notifier).lockApp();
        Future.delayed(const Duration(milliseconds: 200), () {
          if (mounted) {
            _checkAndPromptAuth(force: true);
          }
        });
      }
    });

    final authUser = ref.watch(authProvider);
    final secState = ref.watch(securityNotifierProvider);

    // App Lock ONLY protects active logged-in sessions. If user is logged out, allow login screen.
    if (!authUser.isLoggedIn) {
      return widget.child;
    }

    // If App Lock is enabled AND logged-in user is NOT authenticated, display full lock screen shield
    if (secState.isAppLockEnabled && !secState.isAuthenticated) {
      return Scaffold(
        backgroundColor: Colors.white,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                GestureDetector(
                  onTap: () {
                    _checkAndPromptAuth(force: true);
                  },
                  child: Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: AppTheme.primaryColor.withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.fingerprint,
                      size: 80,
                      color: AppTheme.primaryColor,
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                const Text(
                  'MyExpense is Locked',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Tap the fingerprint icon above or button below to scan your Fingerprint / PIN and unlock MyExpense.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey[600],
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 36),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primaryColor,
                      foregroundColor: Colors.white,
                      elevation: 2,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    onPressed: () {
                      _checkAndPromptAuth(force: true);
                    },
                    icon: const Icon(Icons.lock_open, size: 22),
                    label: const Text(
                      'Unlock with Fingerprint / PIN',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return widget.child;
  }
}
