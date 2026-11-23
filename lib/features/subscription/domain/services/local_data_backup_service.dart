import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:myexpence/core/database/app_database.dart';
import 'package:myexpence/features/backup/backup_snapshot.dart';
import 'package:myexpence/features/backup/backup_refresh.dart';
import 'package:myexpence/features/backup/cloud_backup_service.dart';

class LocalBackupResult {
  final bool success;
  final String message;
  final String? backupDateIso;
  final int? recordCount;
  final String? filePath;
  const LocalBackupResult(
      {required this.success,
      required this.message,
      this.backupDateIso,
      this.recordCount,
      this.filePath});
}

class LocalDataBackupService {
  Future<LocalBackupResult> downloadLocalDataFile(WidgetRef ref) async {
    try {
      final snapshot = await BackupSnapshot.capture(
          await AppDatabase().database, await SharedPreferences.getInstance());
      final bytes = snapshot.toZip();
      final path = await FilePicker.platform.saveFile(
          dialogTitle: 'Save your backup',
          fileName:
              'myexpense_backup_${DateTime.now().millisecondsSinceEpoch}.zip',
          type: FileType.custom,
          allowedExtensions: ['zip'],
          bytes: bytes);
      if (path == null) {
        return const LocalBackupResult(
            success: false, message: 'Backup canceled.');
      }
      if (!Platform.isAndroid && !Platform.isIOS) {
        await File(path).writeAsBytes(bytes, flush: true);
      }
      return LocalBackupResult(
          success: true,
          message: snapshot.missingAttachments == 0
              ? 'Backup saved with ${snapshot.expenseCount} expenses and your available attachments.'
              : 'Backup saved. ${snapshot.missingAttachments} attachment(s) were already missing from this device.',
          backupDateIso: snapshot.payload['exportedAt'] as String,
          recordCount: snapshot.expenseCount,
          filePath: path);
    } catch (_) {
      return const LocalBackupResult(
          success: false,
          message:
              'The backup could not be saved. Check available storage and try again.');
    }
  }

  Future<LocalBackupResult> restoreFromSelectedFile(WidgetRef ref) async {
    try {
      final selection = await FilePicker.platform
          .pickFiles(type: FileType.custom, allowedExtensions: ['json', 'zip']);
      final path = selection?.files.single.path;
      if (path == null) {
        return const LocalBackupResult(
            success: false, message: 'Restore canceled.');
      }
      final file = File(path);
      final zip = path.toLowerCase().endsWith('.zip');
      if (await file.length() >
          (zip ? BackupSnapshot.maxZipBytes : BackupSnapshot.maxJsonBytes)) {
        return const LocalBackupResult(
            success: false,
            message: 'This backup is larger than the supported limit.');
      }
      final snapshot = BackupSnapshot.read(await file.readAsBytes(), zip: zip);
      if (!ref.context.mounted) {
        return const LocalBackupResult(
            success: false, message: 'Restore canceled.');
      }
      final confirmed = await showDialog<bool>(
          context: ref.context,
          builder: (context) => AlertDialog(
                title: const Text('Replace local data?'),
                content: Text(
                    'Restore ${snapshot.expenseCount} expenses from this backup? This replaces the existing expenses, people, budgets and receipts on this device.'),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('Cancel')),
                  FilledButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('Replace and restore'))
                ],
              ));
      if (confirmed != true) {
        return const LocalBackupResult(
            success: false, message: 'Restore canceled.');
      }
      await CloudBackupService().exclusive(() async => snapshot.restore(
          await AppDatabase().database,
          await SharedPreferences.getInstance(),
          await getApplicationDocumentsDirectory()));
      if (ref.context.mounted) refreshAfterBackupRestore(ref);
      return LocalBackupResult(
          success: true,
          message:
              'Restored ${snapshot.expenseCount} expenses and your saved data.',
          recordCount: snapshot.expenseCount,
          backupDateIso: snapshot.payload['exportedAt'] as String,
          filePath: path);
    } catch (_) {
      return const LocalBackupResult(
          success: false,
          message:
              'Restore did not finish. Check that this is a complete MyExpense backup and try again.');
    }
  }
}

final localDataBackupServiceProvider =
    Provider<LocalDataBackupService>((ref) => LocalDataBackupService());
