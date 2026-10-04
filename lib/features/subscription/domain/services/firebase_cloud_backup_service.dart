import 'dart:convert';
import 'dart:io';
import 'package:archive/archive.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:myexpence/core/database/app_database.dart';
import 'package:myexpence/features/auth/presentation/providers/auth_providers.dart';
import 'package:myexpence/features/budgets/presentation/providers/budget_providers.dart';
import 'package:myexpence/features/calendar/presentation/providers/calendar_providers.dart';
import 'package:myexpence/features/dashboard/presentation/providers/dashboard_providers.dart';
import 'package:myexpence/features/expenses/presentation/providers/expense_providers.dart';
import 'package:myexpence/features/people/presentation/providers/people_providers.dart';
import 'package:myexpence/features/sms_parser/presentation/providers/sms_whitelist_provider.dart';
import 'package:myexpence/features/subscription/presentation/providers/subscription_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

class BackupResult {
  final bool success;
  final String message;
  final String? backupDateIso;
  final int? recordCount;

  const BackupResult({
    required this.success,
    required this.message,
    this.backupDateIso,
    this.recordCount,
  });
}

class FirebaseCloudBackupService {
  final AppDatabase _appDatabase = AppDatabase();

  Future<User?> _getOrCreateFirebaseUser() async {
    try {
      var user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        final anonCred = await FirebaseAuth.instance.signInAnonymously();
        user = anonCred.user;
      }
      return user;
    } catch (_) {
      return FirebaseAuth.instance.currentUser;
    }
  }

  Set<String> _getBackupTargetIds(dynamic ref, User? firebaseUser) {
    final Set<String> targetIds = {};
    final authState = ref.read(authProvider);

    if (firebaseUser != null && firebaseUser.uid.isNotEmpty) {
      targetIds.add(firebaseUser.uid);
    }

    if (authState.uid.isNotEmpty) {
      targetIds.add(authState.uid);
    }

    final email = (firebaseUser?.email != null && firebaseUser!.email!.isNotEmpty)
        ? firebaseUser.email!
        : (authState.email ?? '');

    if (email.isNotEmpty && email.contains('@')) {
      final sanitizedEmail = email.toLowerCase().trim().replaceAll(RegExp(r'[^a-zA-Z0-9_]'), '_');
      targetIds.add('user_$sanitizedEmail');
    }

    if (targetIds.isEmpty) {
      targetIds.add('guest');
    }

    return targetIds;
  }

  /// Compresses database records & settings into a .zip file (NO images) and uploads to Firebase
  Future<BackupResult> backupDataToFirebase(dynamic ref) async {
    try {
      final user = await _getOrCreateFirebaseUser();
      final targetIds = _getBackupTargetIds(ref, user);
      final authState = ref.read(authProvider);
      final targetEmail = user?.email ?? authState.email;
      final primaryUid = user?.uid ?? (authState.uid.isNotEmpty ? authState.uid : 'guest');

      final db = await _appDatabase.database;

      // 1. Fetch text & structured data only (excluding binary receipt images)
      final expenses = await db.query('expenses', where: 'isDeleted = 0');
      final people = await db.query('people');
      final budgets = await db.query('budgets');
      final zeroSpends = await db.query('zero_spend_confirmations');

      // 2. Fetch SharedPreferences settings & trial license info
      final prefs = await SharedPreferences.getInstance();
      final whitelistedSenders = prefs.getStringList('sms_whitelisted_senders') ?? [];
      final geofences = prefs.getString('location_geofences_v1') ?? '[]';
      final mutedPlaces = prefs.getStringList('location_muted_places_v1') ?? [];
      final subTier = prefs.getString('user_sub_tier') ?? 'FREE';
      final subExpiry = prefs.getString('user_sub_expiry');
      final subTrialStart = prefs.getString('user_sub_trial_start');

      final nowIso = DateTime.now().toIso8601String();

      final backupPayload = {
        'version': 1,
        'appVersion': '1.3.0',
        'userId': primaryUid,
        'userEmail': targetEmail,
        'exportedAt': nowIso,
        'sub_tier': subTier,
        'sub_expiry_iso': subExpiry,
        'sub_trial_start_iso': subTrialStart,
        'expenses': expenses,
        'people': people,
        'budgets': budgets,
        'zero_spend_confirmations': zeroSpends,
        'whitelisted_senders': whitelistedSenders,
        'geofences_json': geofences,
        'muted_places': mutedPlaces,
      };

      final jsonString = jsonEncode(backupPayload);
      final jsonBytes = utf8.encode(jsonString);

      // 3. Compress into a .zip archive (Data Only, No Images)
      final archive = Archive();
      archive.addFile(ArchiveFile('myexpense_userdata_backup.json', jsonBytes.length, jsonBytes));
      final zipBytes = ZipEncoder().encode(archive);

      if (zipBytes == null) {
        return const BackupResult(
          success: false,
          message: '⚠️ Failed to create ZIP archive for backup payload.',
        );
      }

      final base64Zip = base64Encode(zipBytes);

      // 4. Save local ZIP backup copy on device filesystem
      try {
        final docsDir = await getApplicationDocumentsDirectory();
        final localZipFile = File('${docsDir.path}/myexpense_local_backup.zip');
        await localZipFile.writeAsBytes(zipBytes);
      } catch (e) {
        debugPrint('Local ZIP save warning: $e');
      }

      // 5. Upload ZIP Archive to Firebase Storage (Primary Cloud Storage across all target keys)
      bool uploadedToCloud = false;
      for (final docId in targetIds) {
        try {
          final storageRef = FirebaseStorage.instance.ref().child('user_backups/$docId/myexpense_backup.zip');
          await storageRef.putData(Uint8List.fromList(zipBytes));
          uploadedToCloud = true;
        } catch (e) {
          debugPrint('Firebase Storage upload notice for $docId: $e');
        }
      }

      // 6. Try Cloud Firestore (Secondary Cloud Storage & Subscription Sync across all target keys)
      final subState = ref.read(subscriptionProvider);
      for (final docId in targetIds) {
        try {
          await FirebaseFirestore.instance.collection('user_backups').doc(docId).set({
            'backupZipBase64': base64Zip,
            'recordCount': expenses.length,
            'updatedAt': FieldValue.serverTimestamp(),
            'userEmail': targetEmail,
            'userId': primaryUid,
            'lastBackupAt': nowIso,
            'hasZipBackup': true,
            'sub_tier': subTier,
            'sub_expiry_iso': subExpiry,
            'sub_trial_start_iso': subTrialStart,
            'isPremium': subState.isPremium,
          }, SetOptions(merge: true));

          // ALSO save dedicated user subscription document in Firebase Cloud
          await FirebaseFirestore.instance.collection('user_subscriptions').doc(docId).set({
            'userId': primaryUid,
            'userEmail': targetEmail,
            'sub_tier': subTier,
            'sub_expiry_iso': subExpiry,
            'sub_trial_start_iso': subTrialStart,
            'isPremium': subState.isPremium,
            'isTrial': subState.isTrial,
            'updatedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));

          uploadedToCloud = true;
        } catch (e) {
          debugPrint('Firestore upload notice for $docId: $e');
        }
      }

      await prefs.setString('cloud_last_backup_date', nowIso);

      return BackupResult(
        success: true,
        message: uploadedToCloud
            ? '✅ Successfully backed up ${expenses.length} expense(s) & settings to Firebase Cloud ($primaryUid) & Device!'
            : '✅ Saved ${expenses.length} expense(s) & settings into ZIP archive on device storage!',
        backupDateIso: nowIso,
        recordCount: expenses.length,
      );
    } catch (e) {
      return BackupResult(
        success: false,
        message: '❌ Backup Error: $e',
      );
    }
  }

  /// Downloads & extracts the .zip archive from Firebase and restores records onto the user's mobile device
  Future<BackupResult> restoreDataFromFirebase(dynamic ref, {String? optionalEmail}) async {
    try {
      final user = await _getOrCreateFirebaseUser();
      final targetIds = _getBackupTargetIds(ref, user);
      if (optionalEmail != null && optionalEmail.trim().contains('@')) {
        final sanitized = optionalEmail.toLowerCase().trim().replaceAll(RegExp(r'[^a-zA-Z0-9_]'), '_');
        targetIds.add('user_$sanitized');
      }

      List<int>? zipBytes;

      // 1. Download ZIP archive from Firebase Storage across target IDs
      for (final docId in targetIds) {
        try {
          final storageRef = FirebaseStorage.instance.ref().child('user_backups/$docId/myexpense_backup.zip');
          zipBytes = await storageRef.getData();
          if (zipBytes != null && zipBytes.isNotEmpty) break;
        } catch (e) {
          debugPrint('Firebase Storage restore notice for $docId: $e');
        }
      }

      // 2. Download base64 ZIP from Cloud Firestore across target IDs
      if (zipBytes == null || zipBytes.isEmpty) {
        for (final docId in targetIds) {
          try {
            final doc = await FirebaseFirestore.instance.collection('user_backups').doc(docId).get();
            if (doc.exists && doc.data()?.containsKey('backupZipBase64') == true) {
              final base64Zip = doc.data()!['backupZipBase64'] as String;
              zipBytes = base64Decode(base64Zip);
              if (zipBytes.isNotEmpty) break;
            }
          } catch (_) {}
        }
      }

      // 3. Fallback: Read local device ZIP archive if Cloud is unavailable or empty (Owner verified only)
      if (zipBytes == null || zipBytes.isEmpty) {
        try {
          final docsDir = await getApplicationDocumentsDirectory();
          final localZipFile = File('${docsDir.path}/myexpense_local_backup.zip');
          if (await localZipFile.exists()) {
            final tempBytes = await localZipFile.readAsBytes();
            final archive = ZipDecoder().decodeBytes(tempBytes);
            for (final file in archive) {
              if (file.name.endsWith('.json')) {
                final jsonContent = utf8.decode(file.content as List<int>);
                final Map<String, dynamic> payload = jsonDecode(jsonContent);
                final String? zipUserId = payload['userId'] as String?;
                final String? zipUserEmail = payload['userEmail'] as String?;
                // Strictly verify local ZIP belongs to the target logged-in user!
                if (targetIds.contains(zipUserId) || (zipUserEmail != null && optionalEmail != null && zipUserEmail.toLowerCase() == optionalEmail.toLowerCase())) {
                  zipBytes = tempBytes;
                }
                break;
              }
            }
          }
        } catch (_) {}
      }

      if (zipBytes == null || zipBytes.isEmpty) {
        return BackupResult(
          success: false,
          message: 'ℹ️ No Firebase Cloud backup found for account key (${targetIds.join(', ')}).',
        );
      }

      // 4. Unzip archive & parse JSON payload
      final archive = ZipDecoder().decodeBytes(zipBytes);
      ArchiveFile? jsonFile;
      for (final file in archive) {
        if (file.name.endsWith('.json')) {
          jsonFile = file;
          break;
        }
      }

      if (jsonFile == null) {
        return const BackupResult(
          success: false,
          message: '⚠️ ZIP backup archive did not contain valid JSON data.',
        );
      }

      final jsonContent = utf8.decode(jsonFile.content as List<int>);
      final Map<String, dynamic> backupPayload = jsonDecode(jsonContent);

      final List expenses = backupPayload['expenses'] as List? ?? [];
      final List people = backupPayload['people'] as List? ?? [];
      final List budgets = backupPayload['budgets'] as List? ?? [];
      final List zeroSpends = backupPayload['zero_spend_confirmations'] as List? ?? [];

      final db = await _appDatabase.database;

      // 5. Restore database records in transaction
      await db.transaction((txn) async {
        if (expenses.isNotEmpty) {
          await txn.delete('expenses');
        }
        for (final item in expenses) {
          final map = Map<String, dynamic>.from(item as Map);
          map.remove('id'); // Allow SQLite AUTOINCREMENT to avoid primary key conflicts
          map['isDeleted'] = (map['isDeleted'] == true || map['isDeleted'] == 1 || map['isDeleted'] == '1') ? 1 : 0;
          if (map['status'] == null || map['status'].toString().isEmpty) {
            map['status'] = 'PAID';
          }
          if (map['currency'] == null || map['currency'].toString().isEmpty) {
            map['currency'] = 'Rs';
          }
          await txn.insert('expenses', map, conflictAlgorithm: ConflictAlgorithm.replace);
        }

        if (people.isNotEmpty) {
          await txn.delete('people');
        }
        for (final item in people) {
          final map = Map<String, dynamic>.from(item as Map);
          map.remove('id');
          if (map['isActive'] != null) {
            map['isActive'] = (map['isActive'] == true || map['isActive'] == 1 || map['isActive'] == '1') ? 1 : 0;
          }
          await txn.insert('people', map, conflictAlgorithm: ConflictAlgorithm.replace);
        }

        if (budgets.isNotEmpty) {
          await txn.delete('budgets');
        }
        for (final item in budgets) {
          final map = Map<String, dynamic>.from(item as Map);
          map.remove('id');
          await txn.insert('budgets', map, conflictAlgorithm: ConflictAlgorithm.replace);
        }

        for (final item in zeroSpends) {
          final map = Map<String, dynamic>.from(item as Map);
          await txn.insert('zero_spend_confirmations', map, conflictAlgorithm: ConflictAlgorithm.replace);
        }
      });

      // 6. Restore SharedPreferences settings & 3-month trial license info
      final prefs = await SharedPreferences.getInstance();

      String? subTier = backupPayload['sub_tier'] as String?;
      String? subExpiry = backupPayload['sub_expiry_iso'] as String?;
      String? subTrialStart = backupPayload['sub_trial_start_iso'] as String?;

      if (subTier == null || subTier.isEmpty) {
        for (final docId in targetIds) {
          try {
            final subDoc = await FirebaseFirestore.instance.collection('user_subscriptions').doc(docId).get();
            if (subDoc.exists && subDoc.data() != null) {
              final data = subDoc.data()!;
              subTier = data['sub_tier'] as String?;
              subExpiry = data['sub_expiry_iso'] as String?;
              subTrialStart = data['sub_trial_start_iso'] as String?;
              if (subTier != null && subTier.isNotEmpty) break;
            }
          } catch (_) {}
        }
      }

      if (subTier != null && subTier.isNotEmpty) {
        await prefs.setString('user_sub_tier', subTier);
      }
      if (subExpiry != null && subExpiry.isNotEmpty) {
        await prefs.setString('user_sub_expiry', subExpiry);
      }
      if (subTrialStart != null && subTrialStart.isNotEmpty) {
        await prefs.setString('user_sub_trial_start', subTrialStart);
      }

      final List<String> whitelistedSenders = List<String>.from(backupPayload['whitelisted_senders'] as List? ?? []);
      if (whitelistedSenders.isNotEmpty) {
        await prefs.setStringList('sms_whitelisted_senders', whitelistedSenders);
        ref.invalidate(smsWhitelistProvider);
      }

      final String? geofencesJson = backupPayload['geofences_json'] as String?;
      if (geofencesJson != null && geofencesJson.isNotEmpty) {
        await prefs.setString('location_geofences_v1', geofencesJson);
      }

      final List<String> mutedPlaces = List<String>.from(backupPayload['muted_places'] as List? ?? []);
      if (mutedPlaces.isNotEmpty) {
        await prefs.setStringList('location_muted_places_v1', mutedPlaces);
      }

      // 7. Refresh Riverpod UI state completely across all feature screens
      try {
        await ref.read(subscriptionProvider.notifier).reloadSubscription();
        ref.invalidate(subscriptionProvider);
        ref.invalidate(recentExpensesProvider);
        ref.invalidate(dashboardDataProvider);
        ref.invalidate(calendarMonthDataProvider);
        ref.invalidate(peopleListProvider);
        ref.invalidate(periodBudgetsProvider);
        ref.invalidate(expenseNotifierProvider);
        ref.invalidate(personNotifierProvider);
        ref.invalidate(budgetNotifierProvider);
        ref.invalidate(smsWhitelistProvider);
      } catch (e) {
        debugPrint('Restore Riverpod invalidation notice: $e');
      }

      return BackupResult(
        success: true,
        message: '🎉 Successfully restored ${expenses.length} expense(s) & settings onto your mobile device!',
        backupDateIso: backupPayload['exportedAt'] as String?,
        recordCount: expenses.length,
      );
    } catch (e) {
      return BackupResult(
        success: false,
        message: '❌ Firebase Restore Error: $e',
      );
    }
  }

  /// Permanently purges user backup files and sessions from Cloud Firestore & Storage
  Future<void> deleteCloudData(String? email, String? uid) async {
    final Set<String> targetIds = {};
    if (email != null && email.isNotEmpty && email.contains('@')) {
      final sanitizedEmail = email.toLowerCase().trim().replaceAll(RegExp(r'[^a-zA-Z0-9_]'), '_');
      targetIds.add('user_$sanitizedEmail');
    }
    if (uid != null && uid.isNotEmpty) {
      targetIds.add(uid);
    }

    final List<Future> deleteFutures = [];

    for (final docId in targetIds) {
      deleteFutures.add(
        FirebaseFirestore.instance.collection('user_backups').doc(docId).delete().catchError((_) {}),
      );
      deleteFutures.add(
        FirebaseFirestore.instance.collection('user_subscriptions').doc(docId).delete().catchError((_) {}),
      );
      deleteFutures.add(
        FirebaseStorage.instance.ref().child('user_backups/$docId/myexpense_backup.zip').delete().catchError((_) {}),
      );
      deleteFutures.add(
        FirebaseStorage.instance.ref().child('user_backups/$docId/backup.zip').delete().catchError((_) {}),
      );
      deleteFutures.add(
        FirebaseFirestore.instance.collection('active_sessions').doc(docId).delete().catchError((_) {}),
      );
      deleteFutures.add(
        FirebaseStorage.instance.ref().child('active_sessions/$docId.json').delete().catchError((_) {}),
      );
    }

    try {
      await Future.wait(deleteFutures).timeout(const Duration(milliseconds: 1500), onTimeout: () => []);
    } catch (_) {}

    await deleteLocalBackupZip();
  }

  /// Deletes local device ZIP backup archive to prevent data cross-contamination between user logins
  Future<void> deleteLocalBackupZip() async {
    try {
      final docsDir = await getApplicationDocumentsDirectory();
      final localZipFile = File('${docsDir.path}/myexpense_local_backup.zip');
      if (await localZipFile.exists()) {
        await localZipFile.delete();
      }
    } catch (e) {
      debugPrint('Local ZIP delete notice: $e');
    }
  }
}

final firebaseCloudBackupServiceProvider = Provider<FirebaseCloudBackupService>((ref) {
  return FirebaseCloudBackupService();
});
