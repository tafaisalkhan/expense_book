import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:myexpence/core/database/database_migrations.dart';
import 'package:myexpence/features/backup/backup_snapshot.dart';
import 'package:myexpence/features/backup/cloud_backup_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  late Database db;
  late SharedPreferences prefs;
  late Directory files;
  setUp(() async {
    SharedPreferences.setMockInitialValues({
      'app_currency_code': 'USD',
      'auth_user_uid': 'secret-account',
      'user_sub_tier': 'PREMIUM_MONTHLY',
      'cloud_schedule': 'daily'
    });
    prefs = await SharedPreferences.getInstance();
    files = await Directory.systemTemp.createTemp('myexpense-backup-test');
    db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath,
        options: OpenDatabaseOptions(
            version: 6, onCreate: DatabaseMigrations.onCreate));
  });
  tearDown(() async {
    await db.close();
    await files.delete(recursive: true);
  });

  test('ZIP embeds images and voices and preserves IDs, links and empty tables',
      () async {
    final voice = File('${files.path}/voice.m4a');
    final image = File('${files.path}/receipt.png');
    await voice.writeAsBytes([1, 2, 3, 4]);
    await image.writeAsBytes([5, 6, 7]);
    await db.delete('people');
    await db.insert('people', {
      'id': 42,
      'uuid': 'p42',
      'name': 'Family',
      'createdAt': '2026-11-20',
      'updatedAt': '2026-11-20'
    });
    await db.insert('receipts', {
      'id': 23,
      'uuid': 'r23',
      'imagePath': image.path,
      'scanDate': '2026-11-20',
      'createdAt': '2026-11-20'
    });
    await db.insert('expenses', {
      'id': 17,
      'uuid': 'e17',
      'amount': 25,
      'categoryId': 'cat_food',
      'personId': '42',
      'receiptId': '23',
      'classification': 'REQUIRED',
      'expenseDate': '2026-11-20',
      'createdAt': '2026-11-20',
      'updatedAt': '2026-11-20',
      'voiceNotePath': voice.path
    });
    final snapshot = await BackupSnapshot.capture(db, prefs);
    final decoded = BackupSnapshot.read(snapshot.toZip());
    expect(decoded.expenseCount, 1);
    expect(decoded.missingAttachments, 0);
    expect(decoded.payload['settings'], {'app_currency_code': 'USD'});
    expect(decoded.payload['sub_tier'], isNull);
    expect((decoded.payload['receipts'] as List).single['imageBase64'],
        base64Encode([5, 6, 7]));
    await voice.delete();
    await image.delete();
    await db.insert('budgets', {
      'uuid': 'extra',
      'period': '2026-11',
      'amount': 100,
      'createdAt': '2026-11-20',
      'updatedAt': '2026-11-20'
    });
    await prefs.setString('app_currency_code', 'PKR');
    await decoded.restore(db, prefs, files);
    final expense = (await db.query('expenses')).single;
    expect(expense['id'], 17);
    expect(expense['personId'], '42');
    expect(expense['receiptId'], '23');
    expect(await File(expense['voiceNotePath'] as String).readAsBytes(),
        [1, 2, 3, 4]);
    expect(
        await File((await db.query('receipts')).single['imagePath'] as String)
            .readAsBytes(),
        [5, 6, 7]);
    expect(await db.query('budgets'), isEmpty);
    expect(prefs.getString('app_currency_code'), 'USD');
    expect(prefs.getString('auth_user_uid'), 'secret-account');
  });

  test('missing audio file falls back to embedded voice bytes', () async {
    await db.insert('expenses', {
      'uuid': 'voice-fallback',
      'amount': 5,
      'categoryId': 'cat_food',
      'classification': 'REQUIRED',
      'expenseDate': '2026-11-20',
      'createdAt': '2026-11-20',
      'updatedAt': '2026-11-20',
      'voiceNotePath': '/missing/audio.m4a',
      'voiceNoteBase64': base64Encode([8, 9])
    });
    final snapshot = await BackupSnapshot.capture(db, prefs);
    expect(snapshot.missingAttachments, 0);
    await snapshot.restore(db, prefs, files);
    expect(
        await File(
                (await db.query('expenses')).single['voiceNotePath'] as String)
            .readAsBytes(),
        [8, 9]);
  });

  test('partial, unrelated and credential-bearing JSON is rejected', () async {
    final valid = await BackupSnapshot.capture(db, prefs);
    final incomplete = {...valid.payload}..remove('expenses');
    expect(
        () => BackupSnapshot.read(utf8.encode(jsonEncode(incomplete)),
            zip: false),
        throwsFormatException);
    final unsafe = {
      ...valid.payload,
      'settings': {'auth_user_uid': 'other-user'}
    };
    expect(
        () => BackupSnapshot.read(utf8.encode(jsonEncode(unsafe)), zip: false),
        throwsFormatException);
    expect(() => BackupSnapshot.read(utf8.encode('{"version":3}'), zip: false),
        throwsFormatException);
  });

  test(
      'restore failure rolls back all database tables and removes staged files',
      () async {
    final snapshot = await BackupSnapshot.capture(db, prefs);
    final before = await db.query('categories');
    snapshot.payload['expenses'] = [
      {'unexpected_column': 'invalid'}
    ];
    await expectLater(
        snapshot.restore(db, prefs, files), throwsA(isA<DatabaseException>()));
    expect(await db.query('categories'), before);
    expect(files.listSync(), isEmpty);
  });

  test('account change aborts restore before replacing local data', () async {
    final snapshot = await BackupSnapshot.capture(db, prefs);
    final before = await db.query('categories');
    await expectLater(
        snapshot.restore(db, prefs, files,
            checkAccount: () => throw StateError('Account changed')),
        throwsStateError);
    expect(await db.query('categories'), before);
  });

  test('legacy JSON keeps IDs and cannot restore subscription entitlements',
      () async {
    final snapshot = await BackupSnapshot.capture(db, prefs);
    final legacy = {
      ...snapshot.payload,
      'version': 2,
      'sub_tier': 'PREMIUM_YEARLY'
    };
    legacy.remove('format');
    legacy.remove('settings');
    final decoded =
        BackupSnapshot.read(utf8.encode(jsonEncode(legacy)), zip: false);
    await decoded.restore(db, prefs, files);
    expect(prefs.getString('user_sub_tier'), 'PREMIUM_MONTHLY');
  });

  test('UID paths are separate and account identifiers are consistently hashed',
      () {
    expect(CloudBackupService.pathFor('a'), 'backups/expense/a/latest.zip');
    expect(CloudBackupService.pathFor('a'),
        isNot(CloudBackupService.pathFor('b')));
    expect(CloudBackupService.accountHash('user-a'), hasLength(64));
    expect(CloudBackupService.accountHash('user-a'),
        isNot(CloudBackupService.accountHash('user-b')));
    expect(
        CloudBackupService.maxZipBytesForProduct(
            CloudBackupService.monthlyProductId),
        100 * 1024 * 1024);
    expect(
        CloudBackupService.maxZipBytesForProduct(
            CloudBackupService.yearlyProductId),
        600 * 1024 * 1024);
  });
}
