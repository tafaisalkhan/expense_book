import 'package:sqflite/sqflite.dart';
import 'package:myexpence/core/database/app_database.dart';
import 'package:myexpence/features/expenses/domain/models/expense.dart';
import 'package:myexpence/features/expenses/domain/models/expense_classification.dart';
import 'package:myexpence/features/expenses/domain/repositories/expense_repository.dart';
import 'package:uuid/uuid.dart';

class SqliteExpenseRepository implements IExpenseRepository {
  final AppDatabase appDatabase;
  final Uuid _uuidGen = const Uuid();

  SqliteExpenseRepository(this.appDatabase);

  @override
  Future<Expense> addExpense(Expense expense) async {
    final db = await appDatabase.database;
    final now = DateTime.now().toIso8601String();
    final newUuid = expense.uuid.isNotEmpty ? expense.uuid : _uuidGen.v4();

    final toInsert = expense.copyWith(
      uuid: newUuid,
      createdAt: now,
      updatedAt: now,
    );

    final id = await db.insert('expenses', toInsert.toMap());
    return toInsert.copyWith(id: id);
  }

  @override
  Future<void> updateExpense(Expense expense) async {
    final db = await appDatabase.database;
    final now = DateTime.now().toIso8601String();
    final updated = expense.copyWith(updatedAt: now);

    await db.update(
      'expenses',
      updated.toMap(),
      where: 'uuid = ?',
      whereArgs: [expense.uuid],
    );
  }

  @override
  Future<void> deleteExpense(String uuid) async {
    final db = await appDatabase.database;
    final now = DateTime.now().toIso8601String();

    await db.update(
      'expenses',
      {'isDeleted': 1, 'updatedAt': now},
      where: 'uuid = ?',
      whereArgs: [uuid],
    );
  }

  @override
  Future<Expense?> getExpenseByUuid(String uuid) async {
    final db = await appDatabase.database;
    final maps = await db.query(
      'expenses',
      where: 'uuid = ? AND isDeleted = 0',
      whereArgs: [uuid],
    );
    if (maps.isEmpty) return null;
    return Expense.fromMap(maps.first);
  }

  @override
  Future<List<Expense>> getExpensesForPeriod({
    required String startDate,
    required String endDate,
    String? personId,
    String? categoryId,
    ExpenseClassification? classification,
  }) async {
    final db = await appDatabase.database;

    String where = 'expenseDate >= ? AND expenseDate <= ? AND isDeleted = 0';
    List<dynamic> args = [startDate, endDate];

    if (personId != null) {
      if (personId == 'household') {
        where += ' AND personId IS NULL';
      } else {
        where += ' AND personId = ?';
        args.add(personId);
      }
    }

    if (categoryId != null) {
      where += ' AND categoryId = ?';
      args.add(categoryId);
    }

    if (classification != null) {
      where += ' AND classification = ?';
      args.add(classification.code);
    }

    final maps = await db.query(
      'expenses',
      where: where,
      whereArgs: args,
      orderBy: 'expenseDate DESC, expenseTime DESC, id DESC',
    );

    return maps.map((map) => Expense.fromMap(map)).toList();
  }

  @override
  Future<double> getTotalSpentForPeriod({
    required String startDate,
    required String endDate,
    String? personId,
    ExpenseClassification? classification,
  }) async {
    final db = await appDatabase.database;

    String where =
        "expenseDate >= ? AND expenseDate <= ? AND isDeleted = 0 AND status IN ('PAID', 'APPROVED')";
    List<dynamic> args = [startDate, endDate];

    if (personId != null) {
      if (personId == 'household') {
        where += ' AND personId IS NULL';
      } else {
        where += ' AND personId = ?';
        args.add(personId);
      }
    }

    if (classification != null) {
      where += ' AND classification = ?';
      args.add(classification.code);
    }

    final result = await db.rawQuery(
      'SELECT SUM(amount) as total FROM expenses WHERE $where',
      args,
    );

    final totalNum = result.first['total'];
    if (totalNum == null) return 0.0;
    return (totalNum as num).toDouble();
  }

  @override
  Future<Map<ExpenseClassification, double>> getSpendingByClassification({
    required String startDate,
    required String endDate,
  }) async {
    final db = await appDatabase.database;

    final result = await db.rawQuery('''
      SELECT classification, SUM(amount) as total
      FROM expenses
      WHERE expenseDate >= ? AND expenseDate <= ? AND isDeleted = 0 AND status IN ('PAID', 'APPROVED')
      GROUP BY classification
    ''', [startDate, endDate]);

    final Map<ExpenseClassification, double> map = {
      ExpenseClassification.urgent: 0.0,
      ExpenseClassification.required: 0.0,
      ExpenseClassification.optional: 0.0,
      ExpenseClassification.lost: 0.0,
    };

    for (final row in result) {
      final code = row['classification'] as String;
      final total = (row['total'] as num).toDouble();
      final classification = ExpenseClassification.fromCode(code);
      map[classification] = total;
    }

    return map;
  }

  @override
  Future<Map<String, double>> getSpendingByCategory({
    required String startDate,
    required String endDate,
    String? personId,
  }) async {
    final db = await appDatabase.database;

    String where =
        "expenseDate >= ? AND expenseDate <= ? AND isDeleted = 0 AND status IN ('PAID', 'APPROVED')";
    List<dynamic> args = [startDate, endDate];

    if (personId != null) {
      if (personId == 'household') {
        where += ' AND personId IS NULL';
      } else {
        where += ' AND personId = ?';
        args.add(personId);
      }
    }

    final result = await db.rawQuery('''
      SELECT categoryId, SUM(amount) as total
      FROM expenses
      WHERE $where
      GROUP BY categoryId
      ORDER BY total DESC
    ''', args);

    final Map<String, double> map = {};
    for (final row in result) {
      final catId = row['categoryId'] as String;
      final total = (row['total'] as num).toDouble();
      map[catId] = total;
    }

    return map;
  }

  @override
  Future<Map<String, double>> getSpendingByPerson({
    required String startDate,
    required String endDate,
  }) async {
    final db = await appDatabase.database;

    final result = await db.rawQuery('''
      SELECT personId, SUM(amount) as total
      FROM expenses
      WHERE expenseDate >= ? AND expenseDate <= ? AND isDeleted = 0 AND status IN ('PAID', 'APPROVED')
      GROUP BY personId
      ORDER BY total DESC
    ''', [startDate, endDate]);

    final Map<String, double> map = {};
    for (final row in result) {
      final personId = (row['personId'] as String?) ?? 'household';
      final total = (row['total'] as num).toDouble();
      map[personId] = total;
    }

    return map;
  }

  @override
  Future<List<Expense>> getRecentExpenses({int limit = 10}) async {
    final db = await appDatabase.database;
    final maps = await db.query(
      'expenses',
      where: 'isDeleted = 0',
      orderBy: 'expenseDate DESC, createdAt DESC',
      limit: limit,
    );
    return maps.map((map) => Expense.fromMap(map)).toList();
  }

  @override
  Future<List<Expense>> getAllExpenses() async {
    final db = await appDatabase.database;
    final maps = await db.query(
      'expenses',
      where: 'isDeleted = 0',
      orderBy: 'expenseDate DESC, createdAt DESC',
    );
    return maps.map((map) => Expense.fromMap(map)).toList();
  }

  @override
  Future<Map<String, double>> getSpendingBySubcategory({
    required String startDate,
    required String endDate,
    String? personId,
  }) async {
    final db = await appDatabase.database;

    String where =
        "expenseDate >= ? AND expenseDate <= ? AND isDeleted = 0 AND status IN ('PAID', 'APPROVED')";
    List<dynamic> args = [startDate, endDate];

    if (personId != null) {
      if (personId == 'household') {
        where += ' AND personId IS NULL';
      } else {
        where += ' AND personId = ?';
        args.add(personId);
      }
    }

    final result = await db.rawQuery('''
      SELECT 
        CASE 
          WHEN subcategoryId IS NOT NULL AND subcategoryId != '' THEN subcategoryId 
          ELSE 'uncategorized' 
        END as subId, 
        SUM(amount) as total
      FROM expenses
      WHERE $where
      GROUP BY subId
      ORDER BY total DESC
    ''', args);

    final Map<String, double> map = {};
    for (final row in result) {
      final subId = row['subId'] as String;
      final total = (row['total'] as num).toDouble();
      map[subId] = total;
    }

    return map;
  }

  @override
  Future<List<Expense>> getPendingExpenses() async {
    final db = await appDatabase.database;
    final maps = await db.query(
      'expenses',
      where: "isDeleted = 0 AND status = 'PENDING'",
      orderBy: 'expenseDate DESC, id DESC',
    );
    return maps.map((map) => Expense.fromMap(map)).toList();
  }

  @override
  Future<void> approveExpense(String uuid) async {
    final db = await appDatabase.database;
    await db.update(
        'expenses',
        {
          'status': 'APPROVED',
          'updatedAt': DateTime.now().toIso8601String(),
        },
        where: 'uuid = ? AND status = ?',
        whereArgs: [uuid, 'PENDING']);
  }

  @override
  Future<void> rejectExpense(String uuid) async {
    final db = await appDatabase.database;
    await db.update(
        'expenses',
        {
          'isDeleted': 1,
          'updatedAt': DateTime.now().toIso8601String(),
        },
        where: 'uuid = ? AND status = ?',
        whereArgs: [uuid, 'PENDING']);
  }

  @override
  Future<void> confirmZeroSpendDay(String date) async {
    final db = await appDatabase.database;
    final now = DateTime.now().toIso8601String();
    await db.insert(
      'zero_spend_confirmations',
      {'date': date, 'confirmedAt': now},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  @override
  Future<bool> isZeroSpendDayConfirmed(String date) async {
    final db = await appDatabase.database;
    final maps = await db.query(
      'zero_spend_confirmations',
      where: 'date = ?',
      whereArgs: [date],
    );
    return maps.isNotEmpty;
  }
}
