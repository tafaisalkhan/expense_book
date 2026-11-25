import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import 'package:myexpence/core/database/app_database.dart';
import 'backup_snapshot.dart';
import 'supabase_config.dart';

class CloudBackupMetadata {
  final String exportedAt;
  final int sizeBytes;
  final int expenseCount;
  const CloudBackupMetadata({
    required this.exportedAt,
    required this.sizeBytes,
    this.expenseCount = 0,
  });
}

class CloudBackupService {
  static const monthlyProductId = 'cloud_backup_monthly_v2'; // $0.99 / month (100 MB)
  static const yearlyProductId = 'cloud_backup_yearly';   // $5.99 / year (600 MB)
  static const int monthlyMaxZipBytes = 100 * 1024 * 1024;
  static const int yearlyMaxZipBytes = 600 * 1024 * 1024;
  static const String vipOwnerEmail = 'muhammadfaysal.khan7@gmail.com';
  static const Set<String> subscriptionProductIds = {
    monthlyProductId,
    yearlyProductId,
  };

  static bool isVipOwnerUser([User? user]) {
    final current = user ?? FirebaseAuth.instance.currentUser;
    final email = current?.email?.trim().toLowerCase() ?? '';
    return email == vipOwnerEmail;
  }

  static int maxZipBytesForProduct(String? productId) =>
      productId == yearlyProductId ? yearlyMaxZipBytes : monthlyMaxZipBytes;

  static int maxZipMbForProduct(String? productId) =>
      productId == yearlyProductId ? 600 : 100;

  static String pathFor(String uid) => 'backups/expense/$uid/latest.zip';
  static String accountHash(String uid) =>
      sha256.convert(utf8.encode(uid)).toString();

  Future<String> signedInUid() async {
    final user = FirebaseAuth.instance.currentUser;
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    if (user == null ||
        user.isAnonymous ||
        prefs.getBool('auth_is_logged_in') != true ||
        prefs.getString('auth_user_uid') != user.uid) {
      throw StateError('Sign in with Google to use cloud backup.');
    }
    return user.uid;
  }

  Future<String> _firebaseIdToken() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw StateError('Sign in with Google to use cloud backup.');
    final token = await user.getIdToken();
    if (token == null || token.isEmpty) {
      throw StateError('Could not verify your Google session.');
    }
    return token;
  }

  void _checkUid(String uid) {
    if (FirebaseAuth.instance.currentUser?.uid != uid) {
      throw StateError('Your account changed. Please try again.');
    }
  }

  Future<Map<String, dynamic>> _callEdge(Map<String, dynamic> body) async {
    if (!SupabaseBackupConfig.isConfigured) {
      throw StateError(
          'Cloud backup service is temporarily unavailable.');
    }
    final idToken = await _firebaseIdToken();
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 25);
    try {
      final req = await client.postUrl(SupabaseBackupConfig.edgeFunctionUri);
      req.headers.set('Content-Type', 'application/json');
      req.headers.set('apikey', SupabaseBackupConfig.supabaseAnonKey);
      req.headers.set('Authorization', 'Bearer $idToken');
      req.write(jsonEncode(body));
      final res = await req.close().timeout(const Duration(seconds: 40));
      final text = await utf8.decodeStream(res);
      if (res.statusCode == 403) throw const CloudSubscriptionRequired();
      if (res.statusCode == 404) throw StateError('object-not-found');
      if (res.statusCode < 200 || res.statusCode >= 300) {
        throw HttpException('Cloud backup error ${res.statusCode}: $text');
      }
      return Map<String, dynamic>.from(jsonDecode(text) as Map);
    } finally {
      client.close(force: true);
    }
  }

  /// Obtains server-verified subscription status using Firebase ID Token.
  Future<Map<String, dynamic>> access(
      {String? productId, String? purchaseToken}) async {
    final uid = await signedInUid();
    final isVip = isVipOwnerUser();
    try {
      final result = await _callEdge(<String, dynamic>{
        'action': 'access',
        if (productId != null) 'productId': productId,
        if (purchaseToken != null) 'purchaseToken': purchaseToken,
      });
      _checkUid(uid);
      if (isVip) {
        return <String, dynamic>{
          ...result,
          'active': true,
          'productId': yearlyProductId,
          'maxSizeBytes': yearlyMaxZipBytes,
          'vipOwner': true,
        };
      }
      return result;
    } on CloudSubscriptionRequired {
      if (isVip) {
        return <String, dynamic>{
          'active': true,
          'productId': yearlyProductId,
          'maxSizeBytes': yearlyMaxZipBytes,
          'vipOwner': true,
        };
      }
      rethrow;
    }
  }

  /// Purges this user's Supabase ZIP backup and metadata on account deletion.
  Future<void> deleteUserData() async {
    if (!SupabaseBackupConfig.isConfigured) return;
    if (FirebaseAuth.instance.currentUser == null) return;
    try {
      await _callEdge({'action': 'delete_data'})
          .timeout(const Duration(seconds: 6));
    } catch (_) {}
  }

  Future<T> exclusive<T>(Future<T> Function() action) async {
    final db = await AppDatabase().database;
    final owner = const Uuid().v4();
    final now = DateTime.now().millisecondsSinceEpoch;
    await db.execute(
        'CREATE TABLE IF NOT EXISTS backup_operation_lock (id INTEGER PRIMARY KEY, owner TEXT NOT NULL, expires INTEGER NOT NULL)');
    await db.transaction((txn) async {
      final rows = await txn.query('backup_operation_lock', where: 'id = 1');
      if (rows.isNotEmpty && (rows.single['expires'] as int) > now) {
        throw StateError(
            'A backup or restore is already running. Please wait.');
      }
      await txn.rawInsert(
          'INSERT OR REPLACE INTO backup_operation_lock(id,owner,expires) VALUES(1,?,?)',
          [owner, now + const Duration(minutes: 10).inMilliseconds]);
    });
    try {
      return await action();
    } finally {
      await db.delete('backup_operation_lock',
          where: 'owner = ?', whereArgs: [owner]);
    }
  }

  Future<String> backUp({bool automatic = false, String? expectedUid}) async {
    final uid = await signedInUid();
    if (expectedUid != null && expectedUid != uid) {
      throw StateError('Backup account changed.');
    }
    final entitlement = await access();
    if (entitlement['active'] != true) throw const CloudSubscriptionRequired();
    final isVipOwner = isVipOwnerUser();
    return exclusive(() async {
      final prefs = await SharedPreferences.getInstance();
      if (automatic &&
          !isVipOwner &&
          (prefs.getString('cloud_schedule_owner') != uid ||
              (prefs.getString('cloud_schedule') ?? 'off') == 'off')) {
        return 'Automatic backup is off.';
      }
      final snapshot =
          await BackupSnapshot.capture(await AppDatabase().database, prefs);
      final stableData = Map<String, dynamic>.from(snapshot.payload)
        ..remove('exportedAt');
      final fingerprint =
          sha256.convert(utf8.encode(jsonEncode(stableData))).toString();
      if (automatic && prefs.getString('cloud_hash_$uid') == fingerprint) {
        final existing = await metadata();
        if (existing != null) return 'No changes since the last backup.';
      }
      final activeProductId = entitlement['productId'] as String?;
      final limitBytes = maxZipBytesForProduct(activeProductId);
      final bytes = snapshot.toZip(maxBytes: limitBytes);
      _checkUid(uid);

      final urlRes = await _callEdge({
        'action': 'upload_url',
        'sizeBytes': bytes.length,
      });
      final signedUrl = urlRes['signedUrl'] as String;
      await _uploadBytes(signedUrl, bytes);

      final exportedAt = snapshot.payload['exportedAt'] as String;
      await _callEdge({
        'action': 'commit_metadata',
        'exportedAt': exportedAt,
        'sizeBytes': bytes.length,
        'expenseCount': snapshot.expenseCount,
      });

      _checkUid(uid);
      await prefs.setString('cloud_last_success_$uid', exportedAt);
      await prefs.setString('cloud_hash_$uid', fingerprint);
      await prefs.remove('cloud_last_error_$uid');
      return snapshot.missingAttachments == 0
          ? 'Cloud ZIP backup saved.'
          : 'Backup saved. ${snapshot.missingAttachments} attachment(s) were missing from this device.';
    });
  }

  Future<void> _uploadBytes(String signedUrl, List<int> bytes) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 30);
    try {
      final req = await client.putUrl(Uri.parse(signedUrl));
      req.headers.set('Content-Type', 'application/zip');
      req.headers.set('x-upsert', 'true');
      req.contentLength = bytes.length;
      req.add(bytes);
      final res = await req.close().timeout(const Duration(minutes: 3));
      if (res.statusCode < 200 || res.statusCode >= 300) {
        final body = await utf8.decodeStream(res);
        throw HttpException('Upload failed (${res.statusCode}): $body');
      }
    } finally {
      client.close(force: true);
    }
  }

  Future<String> restore() async {
    final uid = await signedInUid();
    if ((await access())['active'] != true) {
      throw const CloudSubscriptionRequired();
    }
    return exclusive(() async {
      final urlRes = await _callEdge({'action': 'download_url'});
      final signedUrl = urlRes['signedUrl'] as String;
      final client = HttpClient()..connectionTimeout = const Duration(seconds: 30);
      final List<int> bytes;
      try {
        final req = await client.getUrl(Uri.parse(signedUrl));
        final res = await req.close().timeout(const Duration(minutes: 3));
        if (res.statusCode == 404) throw StateError('object-not-found');
        if (res.statusCode < 200 || res.statusCode >= 300) {
          throw HttpException('Download failed (${res.statusCode})');
        }
        final builder = BytesBuilder(copy: false);
        await for (final chunk in res) {
          builder.add(chunk);
        }
        bytes = builder.takeBytes();
      } finally {
        client.close(force: true);
      }
      final snapshot = BackupSnapshot.read(bytes);
      _checkUid(uid);
      await snapshot.restore(
          await AppDatabase().database,
          await SharedPreferences.getInstance(),
          await getApplicationDocumentsDirectory(),
          checkAccount: () => _checkUid(uid));
      return 'Restored ${snapshot.expenseCount} expenses and your saved data.';
    });
  }

  Future<CloudBackupMetadata?> metadata() async {
    await signedInUid();
    try {
      final res = await _callEdge({'action': 'metadata'});
      final raw = res['metadata'];
      if (raw is! Map) return null;
      return CloudBackupMetadata(
        exportedAt: raw['exported_at'] as String? ?? '',
        sizeBytes: (raw['size_bytes'] as num?)?.toInt() ?? 0,
        expenseCount: (raw['expense_count'] as num?)?.toInt() ?? 0,
      );
    } catch (_) {
      return null;
    }
  }

  /// Automatic hourly backup + fresh-build auto-restore for VIP owner account (`muhammadfaysal.khan7@gmail.com`).
  /// - If the local database has 0 expenses on a new build/install and a Cloud ZIP exists on Supabase,
  ///   it automatically downloads and restores the Cloud ZIP first.
  /// - Otherwise, if >= 1 hour has elapsed since the last cloud backup, it uploads the latest Cloud ZIP.
  Future<String?> runVipOwnerHourlySync({bool forceUploadIfDue = true}) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || !isVipOwnerUser(user)) return null;
    final uid = await signedInUid();
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();

    // 1. Check if this is a fresh install / new build with 0 local expenses and a remote backup ready
    final db = await AppDatabase().database;
    final countRows = await db.rawQuery('SELECT COUNT(*) AS cnt FROM expenses');
    final localExpenseCount = (countRows.first['cnt'] as int?) ?? 0;
    final alreadyAutoRestored =
        prefs.getBool('vip_auto_restored_once_$uid') ?? false;

    if (localExpenseCount == 0 && !alreadyAutoRestored) {
      final remoteMeta = await metadata();
      if (remoteMeta != null && remoteMeta.sizeBytes > 0) {
        final msg = await restore();
        await prefs.setBool('vip_auto_restored_once_$uid', true);
        await prefs.setInt(
            'vip_last_hourly_sync_ms_$uid', DateTime.now().millisecondsSinceEpoch);
        return 'Auto-restored from Supabase: $msg';
      }
    }

    // 2. Otherwise check if >= 1 hour has passed since last automatic hourly backup
    if (!forceUploadIfDue) return null;
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final lastSyncMs = prefs.getInt('vip_last_hourly_sync_ms_$uid') ?? 0;
    if (nowMs - lastSyncMs < const Duration(hours: 1).inMilliseconds) {
      return null;
    }
    final result = await backUp(automatic: true, expectedUid: uid);
    await prefs.setInt('vip_last_hourly_sync_ms_$uid', nowMs);
    return result;
  }
}

class CloudSubscriptionRequired implements Exception {
  const CloudSubscriptionRequired();
  @override
  String toString() =>
      'An active \$0.99/mo or \$5.99/yr subscription is required for cloud backup.';
}
