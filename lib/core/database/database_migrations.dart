import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

class DatabaseMigrations {
  static Future<void> onCreate(Database db, int version) async {
    // 1. Create Categories Table
    await db.execute('''
      CREATE TABLE categories (
        id TEXT PRIMARY KEY,
        uuid TEXT NOT NULL,
        name TEXT NOT NULL,
        icon TEXT NOT NULL,
        defaultClassification TEXT NOT NULL,
        isSystem INTEGER NOT NULL DEFAULT 1,
        isActive INTEGER NOT NULL DEFAULT 1,
        sortOrder INTEGER NOT NULL
      );
    ''');

    // 2. Create Subcategories Table
    await db.execute('''
      CREATE TABLE subcategories (
        id TEXT PRIMARY KEY,
        uuid TEXT NOT NULL,
        categoryId TEXT NOT NULL,
        name TEXT NOT NULL,
        defaultClassification TEXT NOT NULL,
        isActive INTEGER NOT NULL DEFAULT 1,
        sortOrder INTEGER NOT NULL,
        FOREIGN KEY (categoryId) REFERENCES categories(id) ON DELETE CASCADE
      );
    ''');

    // 3. Create People Table
    await db.execute('''
      CREATE TABLE people (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        uuid TEXT UNIQUE NOT NULL,
        name TEXT NOT NULL,
        relationship TEXT,
        nickname TEXT,
        schoolName TEXT,
        grade TEXT,
        notes TEXT,
        isActive INTEGER NOT NULL DEFAULT 1,
        createdAt TEXT NOT NULL,
        updatedAt TEXT NOT NULL
      );
    ''');

    // 4. Create Expenses Table
    await db.execute('''
      CREATE TABLE expenses (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        uuid TEXT UNIQUE NOT NULL,
        amount REAL NOT NULL,
        currency TEXT NOT NULL DEFAULT 'Rs',
        categoryId TEXT NOT NULL,
        subcategoryId TEXT,
        personId TEXT,
        classification TEXT NOT NULL,
        expenseDate TEXT NOT NULL,
        expenseTime TEXT,
        createdAt TEXT NOT NULL,
        updatedAt TEXT NOT NULL,
        merchant TEXT,
        description TEXT,
        paymentMethod TEXT NOT NULL DEFAULT 'Cash',
        locationId TEXT,
        receiptId TEXT,
        recurringOccurrenceId TEXT,
        notes TEXT,
        status TEXT NOT NULL DEFAULT 'PAID',
        isDeleted INTEGER NOT NULL DEFAULT 0
      );
    ''');

    // 5. Create Zero Spend Confirmations Table
    await db.execute('''
      CREATE TABLE zero_spend_confirmations (
        date TEXT PRIMARY KEY,
        confirmedAt TEXT NOT NULL
      );
    ''');

    // 6. Create Budgets Table (V2)
    await db.execute('''
      CREATE TABLE budgets (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        uuid TEXT UNIQUE NOT NULL,
        period TEXT NOT NULL,
        categoryId TEXT,
        personId TEXT,
        amount REAL NOT NULL,
        warningThreshold REAL NOT NULL DEFAULT 0.90,
        createdAt TEXT NOT NULL,
        updatedAt TEXT NOT NULL
      );
    ''');

    // 7. Create Receipts Table (V3)
    await db.execute('''
      CREATE TABLE receipts (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        uuid TEXT UNIQUE NOT NULL,
        imagePath TEXT NOT NULL,
        rawOcrText TEXT,
        merchant TEXT,
        detectedTotal REAL,
        detectedDate TEXT,
        scanDate TEXT NOT NULL,
        fileHash TEXT,
        createdAt TEXT NOT NULL
      );
    ''');

    // 8. Create Indexes
    await db.execute('CREATE INDEX idx_expenses_date ON expenses(expenseDate);');
    await db.execute('CREATE INDEX idx_expenses_category ON expenses(categoryId);');
    await db.execute('CREATE INDEX idx_expenses_person ON expenses(personId);');
    await db.execute('CREATE INDEX idx_expenses_status ON expenses(status);');
    await db.execute('CREATE INDEX idx_budgets_period ON budgets(period);');

    // Seed Categories & Subcategories from JSON
    await ensureDefaultCategories(db);

    // Seed Initial Family Profiles
    await _seedDefaultPeople(db);
  }

  static Future<void> ensureDefaultCategories(Database db) async {
    try {
      final jsonString = await rootBundle.loadString('assets/config/default_categories.json');
      final List<dynamic> catList = json.decode(jsonString);

      const uuidGen = Uuid();
      final Batch batch = db.batch();

      for (final cat in catList) {
        final catId = cat['id'] as String;
        batch.insert(
          'categories',
          {
            'id': catId,
            'uuid': uuidGen.v4(),
            'name': cat['name'],
            'icon': cat['icon'],
            'defaultClassification': cat['defaultClassification'],
            'isSystem': 1,
            'isActive': 1,
            'sortOrder': cat['sortOrder'],
          },
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );

        final subList = cat['subcategories'] as List<dynamic>? ?? [];
        for (final sub in subList) {
          batch.insert(
            'subcategories',
            {
              'id': sub['id'],
              'uuid': uuidGen.v4(),
              'categoryId': catId,
              'name': sub['name'],
              'defaultClassification': sub['defaultClassification'],
              'isActive': 1,
              'sortOrder': sub['sortOrder'],
            },
            conflictAlgorithm: ConflictAlgorithm.ignore,
          );
        }
      }

      await batch.commit(noResult: true);
    } catch (e) {
      // Fallback if asset loading fails in unit tests
    }
  }

  static Future<void> _seedDefaultPeople(Database db) async {
    const uuidGen = Uuid();
    final now = DateTime.now().toIso8601String();
    final Batch batch = db.batch();

    final defaultPeople = [
      {'name': 'Me', 'relationship': 'Self'},
    ];

    for (final person in defaultPeople) {
      batch.insert('people', {
        'uuid': uuidGen.v4(),
        'name': person['name'],
        'relationship': person['relationship'],
        'schoolName': person['schoolName'],
        'grade': person['grade'],
        'isActive': 1,
        'createdAt': now,
        'updatedAt': now,
      });
    }

    await batch.commit(noResult: true);
  }

  static Future<void> onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS budgets (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          uuid TEXT UNIQUE NOT NULL,
          period TEXT NOT NULL,
          categoryId TEXT,
          personId TEXT,
          amount REAL NOT NULL,
          warningThreshold REAL NOT NULL DEFAULT 0.90,
          createdAt TEXT NOT NULL,
          updatedAt TEXT NOT NULL
        );
      ''');
      await db.execute('CREATE INDEX IF NOT EXISTS idx_budgets_period ON budgets(period);');
    }

    if (oldVersion < 3) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS receipts (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          uuid TEXT UNIQUE NOT NULL,
          imagePath TEXT NOT NULL,
          rawOcrText TEXT,
          merchant TEXT,
          detectedTotal REAL,
          detectedDate TEXT,
          scanDate TEXT NOT NULL,
          fileHash TEXT,
          createdAt TEXT NOT NULL
        );
      ''');
    }
  }
}
