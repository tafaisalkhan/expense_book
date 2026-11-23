import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

class BackupSnapshot {
  static const maxZipBytes = 50 * 1024 * 1024;
  static const maxJsonBytes = 150 * 1024 * 1024;
  static const tables = [
    'categories',
    'subcategories',
    'people',
    'receipts',
    'expenses',
    'budgets',
    'recurring_expenses',
    'zero_spend_confirmations'
  ];
  static const settingsKeys = [
    'app_currency_code',
    'app_currency_symbol',
    'sms_whitelisted_senders_v2',
    'location_geofences_v1',
    'location_muted_places_v1'
  ];

  final Map<String, dynamic> payload;
  const BackupSnapshot(this.payload);
  int get expenseCount =>
      (payload['expenses'] as List).where((e) => e['isDeleted'] != 1).length;
  int get missingAttachments => payload['missingAttachments'] as int? ?? 0;

  static Future<BackupSnapshot> capture(
      Database db, SharedPreferences prefs) async {
    final data = await db.transaction((txn) async => <String, dynamic>{
          for (final table in tables)
            table: (await txn.query(table))
                .map((r) => Map<String, dynamic>.from(r))
                .toList(),
        });
    var missing = 0;
    Future<void> embedVoice(Map<String, dynamic> row) async {
      final path = row['voiceNotePath'] as String?;
      if (path != null && path.isNotEmpty) {
        if (await File(path).exists()) {
          row['voiceNoteBase64'] = base64Encode(await File(path).readAsBytes());
          row['voiceFileExtension'] = p.extension(path);
        } else if ((row['voiceNoteBase64'] as String? ?? '').isEmpty) {
          missing++;
        }
      }
      row['voiceNotePath'] = null;
    }

    for (final row in data['expenses'] as List) {
      await embedVoice(row);
    }
    for (final row in data['recurring_expenses'] as List) {
      final template = Map<String, dynamic>.from(
          jsonDecode(row['templateJson'] as String) as Map);
      await embedVoice(template);
      row['templateJson'] = jsonEncode(template);
    }
    for (final row in data['receipts'] as List) {
      final path = row['imagePath'] as String;
      if (path.isNotEmpty && await File(path).exists()) {
        row['imageBase64'] = base64Encode(await File(path).readAsBytes());
        row['imageExtension'] = p.extension(path);
      } else if (path.isNotEmpty) {
        missing++;
      }
      row['imagePath'] = '';
    }
    return BackupSnapshot({
      'format': 'myexpense-backup',
      'version': 3,
      'schemaVersion': 6,
      'exportedAt': DateTime.now().toUtc().toIso8601String(),
      ...data,
      'missingAttachments': missing,
      'settings': {
        for (final key in settingsKeys)
          if (prefs.containsKey(key)) key: prefs.get(key)
      },
    });
  }

  Uint8List toZip() {
    final bytes = utf8.encode(jsonEncode(payload));
    if (bytes.length > maxJsonBytes) {
      throw const FormatException('Backup data exceeds the 150 MB limit.');
    }
    final encoded = ZipEncoder().encode(Archive()
      ..addFile(ArchiveFile('myexpense_backup.json', bytes.length, bytes)))!;
    if (encoded.length > maxZipBytes) {
      throw const FormatException('Compressed backup exceeds the 50 MB limit.');
    }
    return Uint8List.fromList(encoded);
  }

  static BackupSnapshot read(List<int> bytes, {bool zip = true}) {
    if (bytes.length > (zip ? maxZipBytes : maxJsonBytes)) {
      throw const FormatException('The backup is too large.');
    }
    List<int> jsonBytes = bytes;
    if (zip) {
      final archive = ZipDecoder().decodeBytes(bytes);
      final files = archive.files
          .where((f) => f.isFile && f.name.endsWith('.json'))
          .toList();
      if (files.length != 1 || files.single.size > maxJsonBytes) {
        throw const FormatException(
            'The ZIP must contain one supported JSON backup.');
      }
      jsonBytes = files.single.content as List<int>;
      if (jsonBytes.length > maxJsonBytes) {
        throw const FormatException('Uncompressed backup is too large.');
      }
    }
    final data = jsonDecode(utf8.decode(jsonBytes));
    if (data is! Map<String, dynamic> ||
        ![2, 3].contains(data['version']) ||
        (data['version'] == 3 && data['format'] != 'myexpense-backup') ||
        DateTime.tryParse(data['exportedAt'] as String? ?? '') == null ||
        tables.any((t) =>
            data[t] is! List || (data[t] as List).any((r) => r is! Map))) {
      throw const FormatException('This is not a complete MyExpense backup.');
    }
    final settings = data['settings'];
    if (data['version'] == 3 &&
        (settings is! Map ||
            settings.entries.any((e) =>
                !settingsKeys.contains(e.key) ||
                !(e.value is String ||
                    (e.value is List &&
                        (e.value as List).every((v) => v is String)))))) {
      throw const FormatException('Backup settings are invalid.');
    }
    return BackupSnapshot(data);
  }

  Future<void> restore(
      Database db, SharedPreferences prefs, Directory documents,
      {void Function()? checkAccount}) async {
    final staging = await Directory(p.join(documents.path,
            'restored_media_${DateTime.now().microsecondsSinceEpoch}'))
        .create(recursive: true);
    var index = 0;
    Future<String?> materialize(
        String? value, String? extension, String fallback) async {
      if (value == null || value.isEmpty) return null;
      final suffix = RegExp(r'^\.[a-zA-Z0-9]{1,6}$').hasMatch(extension ?? '')
          ? extension!
          : fallback;
      final file = File(p.join(staging.path, '${index++}$suffix'));
      await file.writeAsBytes(base64Decode(value), flush: true);
      return file.path;
    }

    final rows = <String, List<Map<String, dynamic>>>{};
    try {
      // Stage and validate all binary data before changing the database.
      for (final table in tables) {
        rows[table] = [];
        for (final original in payload[table] as List) {
          final row = Map<String, dynamic>.from(original as Map);
          if (table == 'expenses') {
            row['voiceNotePath'] = await materialize(
                row['voiceNoteBase64'] as String?,
                row.remove('voiceFileExtension') as String?,
                '.m4a');
          } else if (table == 'receipts') {
            row['imagePath'] = await materialize(
                    row.remove('imageBase64') as String?,
                    row.remove('imageExtension') as String?,
                    '.jpg') ??
                '';
          } else if (table == 'recurring_expenses') {
            final template = Map<String, dynamic>.from(
                jsonDecode(row['templateJson'] as String) as Map);
            template['voiceNotePath'] = await materialize(
                template['voiceNoteBase64'] as String?,
                template.remove('voiceFileExtension') as String?,
                '.m4a');
            row['templateJson'] = jsonEncode(template);
          }
          rows[table]!.add(row);
        }
      }
      checkAccount?.call();
      await db.transaction((txn) async {
        checkAccount?.call();
        for (final table in tables.reversed) {
          await txn.delete(table);
        }
        for (final table in tables) {
          for (final row in rows[table]!) {
            await txn.insert(table, row);
          }
        }
      });
    } catch (_) {
      await staging.delete(recursive: true);
      rethrow;
    }
    final savedSettings = payload['settings'] as Map? ?? {};
    for (final key in settingsKeys) {
      final value = savedSettings[key];
      if (value is String) {
        await prefs.setString(key, value);
      } else if (value is List) {
        await prefs.setStringList(key, List<String>.from(value));
      }
    }
    // Legacy JSON contained these settings at the top level. Never restore auth,
    // premium flags, biometric secrets, account identity or backup schedules.
    if (payload['version'] == 2) {
      final senders = payload['whitelisted_senders'];
      if (senders is List && senders.every((v) => v is String)) {
        await prefs.setStringList(
            'sms_whitelisted_senders_v2', List<String>.from(senders));
      }
    }
  }
}
