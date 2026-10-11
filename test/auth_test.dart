import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:myexpence/core/config/firebase_config.dart';
import 'package:myexpence/features/auth/domain/models/auth_user.dart';
import 'package:myexpence/features/auth/presentation/providers/auth_providers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Google Auth Tests', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('AuthUser model factory and copyWith', () {
      final user = AuthUser.anonymous();
      expect(user.isLoggedIn, false);
      final loggedInUser = user.copyWith(isLoggedIn: true, email: 'user@gmail.com');
      expect(loggedInUser.isLoggedIn, true);
      expect(loggedInUser.email, 'user@gmail.com');
    });

    test('Initial Auth state is anonymous / logged out', () {
      final notifier = AuthNotifier();
      expect(notifier.state.isLoggedIn, false);
      expect(notifier.state.email, null);
    });

    test('Valid Google Email login updates state successfully', () async {
      final notifier = AuthNotifier();
      final result = await notifier.signInWithGoogleEmail('testuser@gmail.com');

      expect(result, true);
      expect(notifier.state.isLoggedIn, true);
      expect(notifier.state.email, 'testuser@gmail.com');
      expect(notifier.state.displayName, 'testuser');
      expect(notifier.state.uid.startsWith('google_'), true);
    });

    test('Invalid email without @ returns false', () async {
      final notifier = AuthNotifier();
      final result = await notifier.signInWithGoogleEmail('invalidemail');

      expect(result, false);
      expect(notifier.state.isLoggedIn, false);
    });

    test('Sign out clears logged in state', () async {
      final notifier = AuthNotifier();
      await notifier.signInWithGoogleEmail('testuser@gmail.com');
      expect(notifier.state.isLoggedIn, true);

      await notifier.signOut();
      expect(notifier.state.isLoggedIn, false);
      expect(notifier.state.email, null);
    });

    test('Existing user login or restart does not wipe database', () async {
      final notifier = AuthNotifier();
      await notifier.signInWithGoogleEmail('testuser@gmail.com');
      expect(notifier.state.isLoggedIn, true);

      final result = await notifier.signInWithGoogleEmail('testuser@gmail.com');
      expect(result, true);
      expect(notifier.state.email, 'testuser@gmail.com');
    });

    test('Firebase Service Account configuration is valid', () {
      final map = FirebaseConfig.toMap();
      expect(map['project_id'], 'myexpenses-d3cb0');
      expect(map['client_email'], 'firebase-adminsdk-fbsvc@myexpenses-d3cb0.iam.gserviceaccount.com');
      expect(map['client_id'], '106822137642666279953');
    });
  });
}
