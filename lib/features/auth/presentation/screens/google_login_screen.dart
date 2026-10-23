import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:myexpence/core/theme/app_theme.dart';
import 'package:myexpence/core/utils/network_helper.dart';
import 'package:myexpence/features/auth/domain/models/auth_user.dart';
import 'package:myexpence/features/auth/presentation/providers/auth_providers.dart';

class GoogleLoginScreen extends ConsumerStatefulWidget {
  const GoogleLoginScreen({super.key});

  @override
  ConsumerState<GoogleLoginScreen> createState() => _GoogleLoginScreenState();
}

class _GoogleLoginScreenState extends ConsumerState<GoogleLoginScreen> {
  bool _isLoading = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final authState = ref.read(authProvider);
      if (authState.isLoggedIn && mounted) {
        context.go('/dashboard');
      }
    });
  }

  Future<void> _handleGoogleSignIn() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final hasInternet = await NetworkHelper.hasInternetConnection();
    if (!hasInternet) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage =
              'Internet not available right now. Please check your network connection and try again.';
        });
      }
      return;
    }

    try {
      final success = await ref.read(authProvider.notifier).signInWithGoogle();

      if (mounted) {
        setState(() {
          _isLoading = false;
        });

        if (success) {
          context.go('/dashboard');
        } else {
          setState(() {
            _errorMessage = ref.read(authProvider.notifier).lastSignInError ??
                'Google Sign-In could not be completed. Please try again.';
          });
        }
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage =
              'Internet not available right now. Please check your network connection and try again.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authProvider);
    ref.listen<AuthUser>(authProvider, (previous, next) {
      if (next.isLoggedIn && mounted) {
        context.go('/dashboard');
      }
    });

    return Scaffold(
      backgroundColor: Colors.grey[50],
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // App Logo / Branding
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: AppTheme.primaryColor.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.account_balance_wallet,
                    size: 64,
                    color: AppTheme.primaryColor,
                  ),
                ),
                const SizedBox(height: 24),

                Text(
                  'Welcome to My Expence Book',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  'Sign in with Google OAuth to automatically load your email address and profile name.',
                  style: TextStyle(
                      color: Colors.grey[600], fontSize: 13, height: 1.4),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 32),

                // Pure 1-Tap Google Sign-In Card
                Card(
                  elevation: 2,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20)),
                  child: Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Text(
                          'Google Sign-In',
                          style: TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 18),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '1-Tap Google Sign-In (Auto-loads email & full name)',
                          style:
                              TextStyle(color: Colors.grey[600], fontSize: 12),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 24),
                        if (authState.loggedOutNotice != null) ...[
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.amber[50],
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: Colors.amber[600]!),
                            ),
                            child: Row(
                              children: [
                                Icon(Icons.warning_amber_rounded,
                                    color: Colors.amber[900], size: 20),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    authState.loggedOutNotice!,
                                    style: TextStyle(
                                        color: Colors.amber[900],
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),
                        ],
                        if (_errorMessage != null) ...[
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.red[50],
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.red[300]!),
                            ),
                            child: Text(
                              _errorMessage!,
                              style: const TextStyle(
                                  color: Colors.red, fontSize: 12),
                              textAlign: TextAlign.center,
                            ),
                          ),
                          const SizedBox(height: 16),
                        ],
                        SizedBox(
                          height: 52,
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.white,
                              foregroundColor: Colors.black87,
                              elevation: 2,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                                side: BorderSide(color: Colors.grey[300]!),
                              ),
                            ),
                            onPressed: _isLoading ? null : _handleGoogleSignIn,
                            child: _isLoading
                                ? const SizedBox(
                                    height: 24,
                                    width: 24,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2.5),
                                  )
                                : Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Container(
                                        width: 28,
                                        height: 28,
                                        decoration: const BoxDecoration(
                                          color: Colors.redAccent,
                                          shape: BoxShape.circle,
                                        ),
                                        alignment: Alignment.center,
                                        child: const Text(
                                          'G',
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 16,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      const Text(
                                        'Continue with Google',
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 16,
                                        ),
                                      ),
                                    ],
                                  ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 32),

                // Security notice
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.shield, size: 16, color: Colors.grey[600]),
                    const SizedBox(width: 6),
                    Text(
                      'Secured by Firebase Google Authentication',
                      style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
