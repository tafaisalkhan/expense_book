import 'dart:convert';
import 'dart:io';
import 'package:archive/archive.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import 'package:myexpence/core/database/app_database.dart';
import 'package:myexpence/features/budgets/presentation/providers/budget_providers.dart';
import 'package:myexpence/features/calendar/presentation/providers/calendar_providers.dart';
import 'package:myexpence/features/dashboard/presentation/providers/dashboard_providers.dart';
import 'package:myexpence/features/expenses/presentation/providers/expense_providers.dart';
import 'package:myexpence/features/people/presentation/providers/people_providers.dart';
import 'package:myexpence/features/sms_parser/presentation/providers/sms_whitelist_provider.dart';
import 'package:myexpence/features/subscription/presentation/providers/subscription_providers.dart';

class LocalBackupResult {
  final bool success;
  final String message;
  final String? backupDateIso;
  final int? recordCount;
  final String? filePath;

  const LocalBackupResult({
    required this.success,
    required this.message,
    this.backupDateIso,
    this.recordCount,
    this.filePath,
  });
}

class LocalDataBackupService {
  final AppDatabase _appDatabase = AppDatabase();

  /// Exports all local database records & settings into a downloadable JSON backup file
  Future<LocalBackupResult> downloadLocalDataFile(WidgetRef ref) async {
    try {
      final db = await _appDatabase.database;

      final expenses = await db.query('expenses', where: 'isDeleted = 0');
      final people = await db.query('people');
      final budgets = await db.query('budgets');
      final zeroSpends = await db.query('zero_spend_confirmations');

      final prefs = await SharedPreferences.getInstance();
      final whitelistedSenders = prefs.getStringList('sms_whitelisted_senders_v2') ??
          prefs.getStringList('sms_whitelisted_senders') ?? [];
      final geofences = prefs.getString('location_geofences_v1') ?? '[]';
      final mutedPlaces = prefs.getStringList('location_muted_places_v1') ?? [];
      final subTier = prefs.getString('user_sub_tier') ?? 'FREE';
      final subExpiry = prefs.getString('user_sub_expiry');

      final nowIso = DateTime.now().toIso8601String();
      final timestampStr = DateTime.now().millisecondsSinceEpoch;

      final backupPayload = {
        'version': 1,
        'appVersion': '1.3.0',
        'exportedAt': nowIso,
        'sub_tier': subTier,
        'sub_expiry_iso': subExpiry,
        'expenses': expenses,
        'people': people,
        'budgets': budgets,
        'zero_spend_confirmations': zeroSpends,
        'whitelisted_senders': whitelistedSenders,
        'geofences_json': geofences,
        'muted_places': mutedPlaces,
      };

      final jsonString = const JsonEncoder.withIndent('  ').convert(backupPayload);

      // Save file to public Downloads directory on Android
      Directory? targetDir;
      if (Platform.isAndroid) {
        final pubDownload = Directory('/storage/emulated/0/Download');
        if (pubDownload.existsSync()) {
          targetDir = pubDownload;
        }
      }
      targetDir ??= await getDownloadsDirectory() ?? await getExternalStorageDirectory() ?? await getApplicationDocumentsDirectory();

      final targetFile = File('${targetDir.path}/myexpense_data_backup_$timestampStr.json');
      await targetFile.writeAsString(jsonString);

      return LocalBackupResult(
        success: true,
        message: '✅ Downloaded ${expenses.length} expense(s) to Downloads folder!\nSaved as: ${targetFile.path}',
        backupDateIso: nowIso,
        recordCount: expenses.length,
        filePath: targetFile.path,
      );
    } catch (e) {
      return LocalBackupResult(
        success: false,
        message: '❌ Download Error: $e',
      );
    }
  }

  /// Restores data from a user-selected JSON or ZIP file from device storage
  Future<LocalBackupResult> restoreFromSelectedFile(WidgetRef ref) async {
    try {
      final FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.any,
      );

      if (result == null || result.files.isEmpty || result.files.first.path == null) {
        return const LocalBackupResult(
          success: false,
          message: 'ℹ️ Restore cancelled — no backup file selected.',
        );
      }

      final String filePath = result.files.first.path!;
      final File file = File(filePath);

      if (!await file.exists()) {
        return const LocalBackupResult(
          success: false,
          message: '❌ Selected file does not exist on device.',
        );
      }

      final Uint8List fileBytes = await file.readAsBytes();
      String jsonContent = '';

      if (filePath.toLowerCase().endsWith('.zip')) {
        final archive = ZipDecoder().decodeBytes(fileBytes);
        ArchiveFile? jsonFile;
        for (final item in archive) {
          if (item.name.endsWith('.json')) {
            jsonFile = item;
            break;
          }
        }
        if (jsonFile == null) {
          return const LocalBackupResult(
            success: false,
            message: '⚠️ Selected ZIP file does not contain a valid JSON backup.',
          );
        }
        jsonContent = utf8.decode(jsonFile.content as List<int>);
      } else {
        jsonContent = utf8.decode(fileBytes);
      }

      final Map<String, dynamic> backupPayload = jsonDecode(jsonContent);

      final List expenses = backupPayload['expenses'] as List? ?? [];
      final List people = backupPayload['people'] as List? ?? [];
      final List budgets = backupPayload['budgets'] as List? ?? [];
      final List zeroSpends = backupPayload['zero_spend_confirmations'] as List? ?? [];

      final db = await _appDatabase.database;

      await db.transaction((txn) async {
        if (expenses.isNotEmpty) {
          await txn.delete('expenses');
        }
        for (final item in expenses) {
          final map = Map<String, dynamic>.from(item as Map);
          map.remove('id');
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

      final prefs = await SharedPreferences.getInstance();

      final List<String> whitelistedSenders = List<String>.from(backupPayload['whitelisted_senders'] as List? ?? []);
      if (whitelistedSenders.isNotEmpty) {
        await prefs.setStringList('sms_whitelisted_senders_v2', whitelistedSenders);
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

      // Refresh Riverpod UI state across feature screens
      try {
        await ref.read(subscriptionProvider.notifier).reloadSubscription();
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
        debugPrint('Local Restore Riverpod invalidation notice: $e');
      }

      return LocalBackupResult(
        success: true,
        message: '🎉 Successfully restored ${expenses.length} expense(s) & settings from file!',
        backupDateIso: backupPayload['exportedAt'] as String?,
        recordCount: expenses.length,
        filePath: filePath,
      );
    } catch (e) {
      return LocalBackupResult(
        success: false,
        message: '❌ Restore File Error: $e',
      );
    }
  }
}

final localDataBackupServiceProvider = Provider<LocalDataBackupService>((ref) {
  return LocalDataBackupService();
});
