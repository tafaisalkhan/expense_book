import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:myexpence/features/backup/cloud_backup_service.dart';
import 'package:myexpence/features/backup/backup_refresh.dart';

class BackupResult {
  final bool success;
  final String message;
  final String? backupDateIso;
  final int? recordCount;
  const BackupResult(
      {required this.success,
      required this.message,
      this.backupDateIso,
      this.recordCount});
}

/// Compatibility entry points for existing account cleanup and older callers.
/// All new transfers use verified monthly access and one UID-owned Storage ZIP.
class FirebaseCloudBackupService {
  Future<BackupResult> backupDataToFirebase(dynamic ref) async {
    try {
      return BackupResult(
          success: true, message: await CloudBackupService().backUp());
    } catch (_) {
      return const BackupResult(
          success: false,
          message:
              'Cloud backup is not available. Check your cloud backup subscription and connection.');
    }
  }

  Future<BackupResult> restoreDataFromFirebase(dynamic ref,
      {String? optionalEmail}) async {
    try {
      final message = await CloudBackupService().restore();
      refreshAfterBackupRestore(ref);
      return BackupResult(success: true, message: message);
    } catch (_) {
      return const BackupResult(
          success: false,
          message:
              'Cloud restore did not finish. Check your cloud backup subscription and connection.');
    }
  }

  /// Permanently purges user backup files and sessions from Cloud Firestore & Storage
  Future<void> deleteCloudData(String? email, String? uid) async {
    final Set<String> targetIds = {};
    if (email != null && email.isNotEmpty && email.contains('@')) {
      final sanitizedEmail =
          email.toLowerCase().trim().replaceAll(RegExp(r'[^a-zA-Z0-9_]'), '_');
      targetIds.add('user_$sanitizedEmail');
    }
    if (uid != null && uid.isNotEmpty) {
      targetIds.add(uid);
    }

    final List<Future> deleteFutures = [
      CloudBackupService().deleteUserData().catchError((_) {}),
    ];
    if (uid != null && uid.isNotEmpty) {
      deleteFutures.add(FirebaseStorage.instance
          .ref(CloudBackupService.pathFor(uid))
          .delete()
          .catchError((_) {}));
    }

    for (final docId in targetIds) {
      deleteFutures.add(
        FirebaseFirestore.instance
            .collection('user_backups')
            .doc(docId)
            .delete()
            .catchError((_) {}),
      );
      deleteFutures.add(
        FirebaseFirestore.instance
            .collection('user_subscriptions')
            .doc(docId)
            .delete()
            .catchError((_) {}),
      );
      deleteFutures.add(
        FirebaseStorage.instance
            .ref()
            .child('user_backups/$docId/myexpense_backup.zip')
            .delete()
            .catchError((_) {}),
      );
      deleteFutures.add(
        FirebaseStorage.instance
            .ref()
            .child('user_backups/$docId/backup.zip')
            .delete()
            .catchError((_) {}),
      );
      deleteFutures.add(
        FirebaseFirestore.instance
            .collection('active_sessions')
            .doc(docId)
            .delete()
            .catchError((_) {}),
      );
      deleteFutures.add(
        FirebaseStorage.instance
            .ref()
            .child('active_sessions/$docId.json')
            .delete()
            .catchError((_) {}),
      );
    }

    try {
      await Future.wait(deleteFutures)
          .timeout(const Duration(milliseconds: 1500), onTimeout: () => []);
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

final firebaseCloudBackupServiceProvider =
    Provider<FirebaseCloudBackupService>((ref) {
  return FirebaseCloudBackupService();
});
