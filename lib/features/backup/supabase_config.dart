class SupabaseBackupConfig {
  /// Pass via `--dart-define=SUPABASE_URL=https://YOUR_REF.supabase.co`
  /// or replace the defaultValue below.
  static const String supabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: '',
  );

  /// Pass via `--dart-define=SUPABASE_ANON_KEY=YOUR_ANON_KEY`
  /// or via `--dart-define-from-file=admob_secrets.json`.
  static const String supabaseAnonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue: '',
  );

  static const String edgeFunctionName = 'cloud-backup';
  static const String storageBucket = 'user-backups';

  static bool get isConfigured =>
      supabaseUrl.trim().isNotEmpty && supabaseAnonKey.trim().isNotEmpty;

  static Uri get edgeFunctionUri =>
      Uri.parse('${supabaseUrl.trim()}/functions/v1/$edgeFunctionName');
}
