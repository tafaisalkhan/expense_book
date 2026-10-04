import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:myexpence/core/config/firebase_config.dart';
import 'package:myexpence/core/providers/core_providers.dart';
import 'package:myexpence/features/auth/domain/models/auth_user.dart';
import 'package:myexpence/features/budgets/presentation/providers/budget_providers.dart';
import 'package:myexpence/features/calendar/presentation/providers/calendar_providers.dart';
import 'package:myexpence/features/dashboard/presentation/providers/dashboard_providers.dart';
import 'package:myexpence/features/expenses/presentation/providers/expense_providers.dart';
import 'package:myexpence/features/people/presentation/providers/people_providers.dart';
import 'package:myexpence/features/security/presentation/providers/security_providers.dart';
import 'package:myexpence/features/sms_parser/presentation/providers/sms_whitelist_provider.dart';
import 'package:myexpence/features/subscription/domain/services/firebase_cloud_backup_service.dart';
import 'package:myexpence/features/subscription/presentation/providers/subscription_providers.dart';

class AuthNotifier extends StateNotifier<AuthUser> {
  static const String projectId = FirebaseConfig.projectId;
  static const String _keyIsLoggedIn = 'auth_is_logged_in';
  static const String _keyUserEmail = 'auth_user_email';
  static const String _keyUserUid = 'auth_user_uid';
  static const String _keyUserName = 'auth_user_name';
  static const String _keySessionToken = 'auth_session_token';

  final Ref? _ref;
  String? _currentSessionToken;
  StreamSubscription<DocumentSnapshot>? _activeSessionSub;
  Timer? _sessionPollTimer;

  AuthNotifier([this._ref]) : super(AuthUser.anonymous()) {
    _loadAuthState();
    _listenToAuthChanges();
  }

  void _listenToAuthChanges() {
    try {
      FirebaseAuth.instance.authStateChanges().listen((user) {
        if (user != null) {
          final userEmail = user.email ?? '';
          final userName = (user.displayName != null && user.displayName!.isNotEmpty)
              ? user.displayName!
              : (userEmail.contains('@') ? userEmail.split('@').first : 'Google User');

          if (userEmail.isNotEmpty && state.email != userEmail) {
            _saveAndSetState(user.uid, userEmail, userName);
          }
        }
      });
    } catch (_) {}
  }

  String _generateSessionToken() {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final randomVal = 100000 + Random().nextInt(899999);
    return '${timestamp}_$randomVal';
  }

  Future<void> _updateCloudSession(String docKey, String token, String email) async {
    // 1. Update Firebase Storage active session record
    try {
      final jsonBytes = utf8.encode(jsonEncode({
        'sessionToken': token,
        'email': email,
        'lastLoginAt': DateTime.now().millisecondsSinceEpoch,
      }));
      final storageRef = FirebaseStorage.instance.ref().child('active_sessions/$docKey.json');
      await storageRef.putData(Uint8List.fromList(jsonBytes));
    } catch (e) {
      debugPrint('Firebase Storage active session registration notice: $e');
    }

    // 2. Update Cloud Firestore active session record
    try {
      await FirebaseFirestore.instance.collection('active_sessions').doc(docKey).set({
        'sessionToken': token,
        'email': email,
        'lastLoginAt': FieldValue.serverTimestamp(),
        'platform': kIsWeb ? 'web' : defaultTargetPlatform.name,
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('Firestore active session registration notice: $e');
    }
  }

  Future<void> _registerAndListenActiveSession(String email) async {
    if (email.isEmpty || !email.contains('@')) return;

    final prefs = await SharedPreferences.getInstance();
    _currentSessionToken ??= prefs.getString(_keySessionToken);
    if (_currentSessionToken == null || _currentSessionToken!.isEmpty) {
      _currentSessionToken = _generateSessionToken();
      await prefs.setString(_keySessionToken, _currentSessionToken!);
    }

    User? firebaseUser;
    try {
      firebaseUser = FirebaseAuth.instance.currentUser;
    } catch (_) {}
    final String docKey = (firebaseUser != null && firebaseUser.uid.isNotEmpty)
        ? firebaseUser.uid
        : 'user_${email.toLowerCase().trim().replaceAll(RegExp(r'[^a-zA-Z0-9_]'), '_')}';

    await _updateCloudSession(docKey, _currentSessionToken!, email);
    _startActiveSessionMonitoring(docKey);
  }

  void triggerLogoutDialog(String reason) {
    if (state.requiresLogoutDialog) return;
    _sessionPollTimer?.cancel();
    _activeSessionSub?.cancel();
    state = state.copyWith(
      requiresLogoutDialog: true,
      logoutDialogReason: reason,
    );
  }

  void _startActiveSessionMonitoring(String docKey) {
    _sessionPollTimer?.cancel();
    _activeSessionSub?.cancel();

    final String registeredToken = _currentSessionToken ?? '';
    if (registeredToken.isEmpty) return;

    // Listen to Cloud Firestore real-time active session changes for this user account
    try {
      _activeSessionSub = FirebaseFirestore.instance
          .collection('active_sessions')
          .doc(docKey)
          .snapshots()
          .listen(
        (snapshot) {
          if (snapshot.exists && snapshot.data() != null) {
            // Ignore uncommitted local writes
            if (snapshot.metadata.hasPendingWrites) return;

            final data = snapshot.data() as Map<String, dynamic>;
            final remoteToken = data['sessionToken'] as String?;
            if (remoteToken != null &&
                _currentSessionToken != null &&
                _currentSessionToken!.isNotEmpty &&
                remoteToken != _currentSessionToken &&
                remoteToken != registeredToken) {
              debugPrint('⚠️ Remote active session token ($remoteToken) != local token ($_currentSessionToken). Triggering logout popup...');
              triggerLogoutDialog('You have been logged out because your account was logged into from another device.');
            }
          }
        },
        onError: (error) {
          debugPrint('Firestore session listener notice: $error');
        },
      );
    } catch (e) {
      debugPrint('Firestore session listener notice: $e');
    }
  }

  Future<void> _loadAuthState() async {
    User? firebaseUser;
    try {
      firebaseUser = FirebaseAuth.instance.currentUser;
    } catch (_) {}

    final prefs = await SharedPreferences.getInstance();

    String? email = firebaseUser?.email ?? prefs.getString(_keyUserEmail);
    String? name = firebaseUser?.displayName ?? prefs.getString(_keyUserName);
    String uid = firebaseUser?.uid ?? prefs.getString(_keyUserUid) ?? '';
    bool isLoggedIn = firebaseUser != null || (prefs.getBool(_keyIsLoggedIn) ?? false);

    if (isLoggedIn && email != null && email.isNotEmpty) {
      final displayName = (name != null && name.isNotEmpty)
          ? name
          : (email.contains('@') ? email.split('@').first : 'Google User');

      state = AuthUser(
        uid: uid.isNotEmpty ? uid : 'google_${email.hashCode}',
        email: email,
        displayName: displayName,
        isLoggedIn: true,
      );

      await _registerAndListenActiveSession(email);
    }
  }

  Future<bool> signInWithGoogle() async {
    try {
      final GoogleSignIn googleSignIn = GoogleSignIn(
        serverClientId: '61987252093-s5oc67k22aj8gs8947rmsdsaemjlpfuq.apps.googleusercontent.com',
        scopes: ['email', 'profile'],
      );
      final GoogleSignInAccount? googleUser = await googleSignIn.signIn();

      if (googleUser != null) {
        String uid = googleUser.id;
        String userEmail = googleUser.email;
        String userName = (googleUser.displayName != null && googleUser.displayName!.isNotEmpty)
            ? googleUser.displayName!
            : userEmail.split('@').first;

        try {
          final GoogleSignInAuthentication googleAuth = await googleUser.authentication;
          if (googleAuth.idToken != null || googleAuth.accessToken != null) {
            final OAuthCredential credential = GoogleAuthProvider.credential(
              accessToken: googleAuth.accessToken,
              idToken: googleAuth.idToken,
            );

            final UserCredential userCredential = await FirebaseAuth.instance.signInWithCredential(credential);
            if (userCredential.user != null) {
              uid = userCredential.user!.uid;
              userEmail = userCredential.user!.email ?? userEmail;
              if (userCredential.user!.displayName != null && userCredential.user!.displayName!.isNotEmpty) {
                userName = userCredential.user!.displayName!;
              }
            }
          } else {
            final UserCredential anonUser = await FirebaseAuth.instance.signInAnonymously();
            if (anonUser.user != null) {
              uid = anonUser.user!.uid;
            }
          }
        } catch (e) {
          debugPrint('Firebase Auth credential exchange fallback: $e');
          try {
            final UserCredential anonUser = await FirebaseAuth.instance.signInAnonymously();
            if (anonUser.user != null) {
              uid = anonUser.user!.uid;
            }
          } catch (_) {}
        }

        return await _saveAndSetState(uid, userEmail, userName);
      }
    } catch (e, stack) {
      debugPrint('Google Sign-In Exception: $e');
      debugPrint(stack.toString());
    }

    return false;
  }

  Future<bool> signInWithGoogleEmail(String email, {String? name}) async {
    final trimmedEmail = email.trim();
    if (trimmedEmail.isEmpty || !trimmedEmail.contains('@')) {
      return false;
    }

    final displayName = (name != null && name.trim().isNotEmpty)
        ? name.trim()
        : trimmedEmail.split('@').first;
    final uid = 'google_${trimmedEmail.hashCode}';

    return await _saveAndSetState(uid, trimmedEmail, displayName);
  }

  void _invalidateAllDataProviders() {
    if (_ref == null) return;
    try {
      _ref.invalidate(recentExpensesProvider);
      _ref.invalidate(dashboardDataProvider);
      _ref.invalidate(calendarMonthDataProvider);
      _ref.invalidate(peopleListProvider);
      _ref.invalidate(periodBudgetsProvider);
      _ref.invalidate(expenseNotifierProvider);
      _ref.invalidate(personNotifierProvider);
      _ref.invalidate(budgetNotifierProvider);
      _ref.invalidate(subscriptionProvider);
      _ref.invalidate(smsWhitelistProvider);
    } catch (e) {
      debugPrint('Provider invalidation notice: $e');
    }
  }

  Future<bool> _saveAndSetState(String uid, String email, String name) async {
    _currentSessionToken = _generateSessionToken();

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyIsLoggedIn, true);
    await prefs.setString(_keyUserEmail, email);
    await prefs.setString(_keyUserUid, uid);
    await prefs.setString(_keyUserName, name);
    await prefs.setString(_keySessionToken, _currentSessionToken!);

    state = AuthUser(
      uid: uid,
      email: email,
      displayName: name,
      isLoggedIn: true,
    );

    if (_ref != null) {
      try {
        final db = _ref.read(appDatabaseProvider);
        await db.clearAllData();
      } catch (_) {}

      _invalidateAllDataProviders();
    }

    await _registerAndListenActiveSession(email);

    // Auto-restore cloud backup for the newly logged in user if available
    if (_ref != null) {
      try {
        final backupService = FirebaseCloudBackupService();
        await backupService.restoreDataFromFirebase(_ref!, optionalEmail: email);
      } catch (e) {
        debugPrint('Cloud restore notice on sign in: $e');
      }
      _invalidateAllDataProviders();
    }

    return true;
  }

  Future<void> clearAllLocalData() async {
    try {
      await FirebaseCloudBackupService().deleteLocalBackupZip();
    } catch (_) {}

    if (_ref != null) {
      try {
        final db = _ref.read(appDatabaseProvider);
        await db.clearAllData();
      } catch (_) {}

      _invalidateAllDataProviders();
    }
  }

  Future<void> signOut({String? reason}) async {
    _sessionPollTimer?.cancel();
    _sessionPollTimer = null;

    final email = state.email;
    if (email != null && email.isNotEmpty) {
      final sanitizedEmail = email.toLowerCase().trim().replaceAll(RegExp(r'[^a-zA-Z0-9_]'), '_');
      final docKey = 'user_$sanitizedEmail';
      try {
        FirebaseFirestore.instance.collection('active_sessions').doc(docKey).delete().catchError((_) {});
      } catch (_) {}
    }

    await _activeSessionSub?.cancel();
    _activeSessionSub = null;
    _currentSessionToken = null;

    try {
      await FirebaseCloudBackupService().deleteLocalBackupZip();
    } catch (_) {}

    try {
      await GoogleSignIn().disconnect();
    } catch (_) {}
    try {
      await GoogleSignIn().signOut();
      await FirebaseAuth.instance.signOut();
    } catch (_) {}

    if (_ref != null) {
      try {
        final db = _ref.read(appDatabaseProvider);
        await db.clearAllData();
      } catch (_) {}

      _invalidateAllDataProviders();
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyIsLoggedIn);
    await prefs.remove(_keyUserEmail);
    await prefs.remove(_keyUserUid);
    await prefs.remove(_keyUserName);
    await prefs.remove(_keySessionToken);

    if (_ref != null) {
      try {
        _ref.read(securityNotifierProvider.notifier).lockApp();
      } catch (_) {}
    }

    state = AuthUser.anonymous(notice: reason);
  }

  Future<bool> deleteAccount() async {
    final String? targetEmail = state.email;
    final String targetUid = state.uid;

    _sessionPollTimer?.cancel();
    _sessionPollTimer = null;

    _activeSessionSub?.cancel();
    _activeSessionSub = null;
    _currentSessionToken = null;

    // 1. Launch non-blocking remote cloud data purge in background
    unawaited(
      FirebaseCloudBackupService()
          .deleteCloudData(targetEmail, targetUid)
          .catchError((e) => debugPrint('Cloud data delete notice: $e')),
    );

    // 2. Perform local data clearing & auth sign-out in parallel
    final List<Future> cleanupFutures = [];

    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      cleanupFutures.add(
        user.delete().timeout(const Duration(seconds: 1), onTimeout: () {}).catchError((_) {}),
      );
    }
    cleanupFutures.add(
      GoogleSignIn().disconnect().catchError((_) => null),
    );
    cleanupFutures.add(
      GoogleSignIn().signOut().catchError((_) => null),
    );
    cleanupFutures.add(
      FirebaseAuth.instance.signOut().catchError((_) {}),
    );

    if (_ref != null) {
      try {
        final db = _ref.read(appDatabaseProvider);
        cleanupFutures.add(db.clearAllData().catchError((_) {}));
      } catch (_) {}
    }

    try {
      await Future.wait(cleanupFutures).timeout(const Duration(seconds: 1), onTimeout: () => []);
    } catch (_) {}

    if (_ref != null) {
      _invalidateAllDataProviders();
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyIsLoggedIn);
    await prefs.remove(_keyUserEmail);
    await prefs.remove(_keyUserUid);
    await prefs.remove(_keyUserName);
    await prefs.remove(_keySessionToken);

    if (_ref != null) {
      try {
        _ref.read(securityNotifierProvider.notifier).lockApp();
      } catch (_) {}
    }

    state = AuthUser.anonymous(notice: 'User account deleted successfully.');
    return true;
  }

  @override
  void dispose() {
    _sessionPollTimer?.cancel();
    _activeSessionSub?.cancel();
    super.dispose();
  }
}

final authProvider = StateNotifierProvider<AuthNotifier, AuthUser>((ref) {
  return AuthNotifier(ref);
});
