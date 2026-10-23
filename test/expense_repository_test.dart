import 'package:flutter_test/flutter_test.dart';
import 'package:myexpence/core/database/app_database.dart';
import 'package:myexpence/features/expenses/data/repositories/expense_repository_impl.dart';
import 'package:myexpence/features/expenses/domain/models/expense.dart';
import 'package:myexpence/features/expenses/domain/models/expense_classification.dart';
import 'package:myexpence/features/expenses/domain/models/payment_method.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:uuid/uuid.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late Database testDb;
  late SqliteExpenseRepository repository;

  setUp(() async {
    testDb = await openDatabase(
      inMemoryDatabasePath,
      version: 1,
      onCreate: (db, version) async {
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
            isDeleted INTEGER NOT NULL DEFAULT 0,
            allocationsJson TEXT NOT NULL DEFAULT '[]',
            voiceNotePath TEXT,
            voiceNoteBase64 TEXT,
            voiceDurationSeconds INTEGER
          );
        ''');
        await db.execute('''
          CREATE TABLE zero_spend_confirmations (
            date TEXT PRIMARY KEY,
            confirmedAt TEXT NOT NULL
          );
        ''');
      },
    );

    final mockAppDb = TestAppDatabase(testDb);
    repository = SqliteExpenseRepository(mockAppDb);
  });

  tearDown(() async {
    await testDb.close();
  });

  test('Backdated expense counts against expenseDate and NOT createdAt',
      () async {
    const uuidGen = Uuid();
    final expense = Expense(
      uuid: uuidGen.v4(),
      amount: 5000.0,
      categoryId: 'cat_car',
      subcategoryId: 'sub_car_fuel',
      classification: ExpenseClassification.required,
      expenseDate: '2026-09-21',
      createdAt: '2026-09-23T10:00:00.000Z',
      updatedAt: '2026-09-23T10:00:00.000Z',
      paymentMethod: PaymentMethod.cash,
    );

    await repository.addExpense(expense);

    final mondayTotal = await repository.getTotalSpentForPeriod(
      startDate: '2026-09-21',
      endDate: '2026-09-21',
    );
    expect(mondayTotal, equals(5000.0));

    final wednesdayTotal = await repository.getTotalSpentForPeriod(
      startDate: '2026-09-23',
      endDate: '2026-09-23',
    );
    expect(wednesdayTotal, equals(0.0));
  });

  test('Deleted expense disappears from totals and list queries', () async {
    const uuidGen = Uuid();
    final expense = Expense(
      uuid: uuidGen.v4(),
      amount: 1200.0,
      categoryId: 'cat_food',
      classification: ExpenseClassification.optional,
      expenseDate: '2026-09-24',
      createdAt: DateTime.now().toIso8601String(),
      updatedAt: DateTime.now().toIso8601String(),
    );

    final inserted = await repository.addExpense(expense);
    expect(
        await repository.getTotalSpentForPeriod(
            startDate: '2026-09-24', endDate: '2026-09-24'),
        equals(1200.0));

    await repository.deleteExpense(inserted.uuid);
    expect(
        await repository.getTotalSpentForPeriod(
            startDate: '2026-09-24', endDate: '2026-09-24'),
        equals(0.0));
  });

  test('Zero-spend confirmation is stored and does not create an expense',
      () async {
    const targetDate = '2026-09-22';
    await repository.confirmZeroSpendDay(targetDate);

    final isConfirmed = await repository.isZeroSpendDayConfirmed(targetDate);
    expect(isConfirmed, isTrue);

    final totalSpent = await repository.getTotalSpentForPeriod(
        startDate: targetDate, endDate: targetDate);
    expect(totalSpent, equals(0.0));
  });

  test('getAllExpenses retrieves all non-deleted expenses', () async {
    const uuidGen = Uuid();
    for (int i = 0; i < 25; i++) {
      await repository.addExpense(Expense(
        uuid: uuidGen.v4(),
        amount: 100.0 * (i + 1),
        categoryId: 'cat_food',
        classification: ExpenseClassification.required,
        expenseDate: '2026-09-25',
        createdAt: DateTime.now().toIso8601String(),
        updatedAt: DateTime.now().toIso8601String(),
      ));
    }

    final all = await repository.getAllExpenses();
    expect(all.length, equals(25));

    final recent = await repository.getRecentExpenses(limit: 20);
    expect(recent.length, equals(20));
  });

  test('getSpendingBySubcategory groups spending by subcategory accurately', () async {
    const uuidGen = Uuid();
    await repository.addExpense(Expense(
      uuid: uuidGen.v4(),
      amount: 1500.0,
      categoryId: 'cat_car',
      subcategoryId: 'sub_fuel',
      classification: ExpenseClassification.required,
      expenseDate: '2026-09-25',
      createdAt: DateTime.now().toIso8601String(),
      updatedAt: DateTime.now().toIso8601String(),
    ));

    await repository.addExpense(Expense(
      uuid: uuidGen.v4(),
      amount: 500.0,
      categoryId: 'cat_car',
      subcategoryId: 'sub_fuel',
      classification: ExpenseClassification.required,
      expenseDate: '2026-09-25',
      createdAt: DateTime.now().toIso8601String(),
      updatedAt: DateTime.now().toIso8601String(),
    ));

    await repository.addExpense(Expense(
      uuid: uuidGen.v4(),
      amount: 800.0,
      categoryId: 'cat_car',
      subcategoryId: 'sub_parking',
      classification: ExpenseClassification.optional,
      expenseDate: '2026-09-25',
      createdAt: DateTime.now().toIso8601String(),
      updatedAt: DateTime.now().toIso8601String(),
    ));

    final subSpending = await repository.getSpendingBySubcategory(
      startDate: '2026-09-25',
      endDate: '2026-09-25',
    );

    expect(subSpending['sub_fuel'], equals(2000.0));
    expect(subSpending['sub_parking'], equals(800.0));
  });
}

class TestAppDatabase implements AppDatabase {
  final Database db;
  TestAppDatabase(this.db);

  @override
  Future<Database> get database async => db;

  @override
  Future<void> clearAllData() async {}

  @override
  Future<void> close() async {}
}
