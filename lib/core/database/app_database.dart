import 'dart:io';
import 'package:path/path.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:myexpence/core/database/database_migrations.dart';

class AppDatabase {
  static const String _dbName = 'myexpense.db';
  static const int _dbVersion = 3;

  Database? _db;

  Future<Database> get database async {
    if (_db != null && _db!.isOpen) return _db!;
    _db = await _initDatabase();
    return _db!;
  }

  Future<Database> _initDatabase() async {
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    }

    final dbPath = await getDatabasesPath();
    final path = join(dbPath, _dbName);

    final db = await openDatabase(
      path,
      version: _dbVersion,
      onCreate: DatabaseMigrations.onCreate,
      onUpgrade: DatabaseMigrations.onUpgrade,
    );

    // Sync any newly added default categories/subcategories into SQLite
    await DatabaseMigrations.ensureDefaultCategories(db);

    return db;
  }

  Future<void> clearAllData() async {
    final db = await database;
    await db.delete('expenses');
    await db.delete('budgets');
    await db.delete('receipts');
    await db.delete('zero_spend_confirmations');
    await db.delete('people');

    // Re-seed initial default family member 'Me'
    await db.execute('''
      INSERT OR IGNORE INTO people (id, name, isStudent, monthlyBudget, createdAt)
      VALUES (1, 'Me', 0, NULL, '${DateTime.now().toIso8601String()}')
    ''');
  }

  Future<void> close() async {
    if (_db != null && _db!.isOpen) {
      await _db!.close();
      _db = null;
    }
  }
}
