class FirebaseConfig {
  static const String projectId =
      String.fromEnvironment('FIREBASE_PROJECT_ID', defaultValue: '');
  static const String clientEmail =
      String.fromEnvironment('FIREBASE_CLIENT_EMAIL', defaultValue: '');
  static const String clientId =
      String.fromEnvironment('FIREBASE_CLIENT_ID', defaultValue: '');
  static const String privateKeyId =
      String.fromEnvironment('FIREBASE_PRIVATE_KEY_ID', defaultValue: '');
  static const String authUri = 'https://accounts.google.com/o/oauth2/auth';
  static const String tokenUri = 'https://oauth2.googleapis.com/token';
  static const String serviceAccountAssetPath = 'assets/config/firebase_service_account.json';

  static Map<String, dynamic> toMap() {
    return {
      'type': 'service_account',
      'project_id': projectId,
      'private_key_id': privateKeyId,
      'client_email': clientEmail,
      'client_id': clientId,
      'auth_uri': authUri,
      'token_uri': tokenUri,
    };
  }
}
