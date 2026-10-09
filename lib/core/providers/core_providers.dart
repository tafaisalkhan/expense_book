import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:myexpence/core/database/app_database.dart';
import 'package:myexpence/core/notifications/notification_service.dart';
import 'package:myexpence/features/budgets/data/repositories/budget_repository_impl.dart';
import 'package:myexpence/features/budgets/domain/repositories/budget_repository.dart';
import 'package:myexpence/features/categories/data/repositories/category_repository_impl.dart';
import 'package:myexpence/features/categories/domain/repositories/category_repository.dart';
import 'package:myexpence/features/expenses/data/repositories/expense_repository_impl.dart';
import 'package:myexpence/features/expenses/domain/repositories/expense_repository.dart';
import 'package:myexpence/features/expenses/domain/services/recurring_expense_service.dart';
import 'package:myexpence/features/people/data/repositories/person_repository_impl.dart';
import 'package:myexpence/features/people/domain/repositories/person_repository.dart';
import 'package:myexpence/features/receipts/data/repositories/receipt_repository_impl.dart';
import 'package:myexpence/features/receipts/domain/repositories/receipt_repository.dart';

final appDatabaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(() {
    db.close();
  });
  return db;
});

final personRepositoryProvider = Provider<IPersonRepository>((ref) {
  final db = ref.watch(appDatabaseProvider);
  return SqlitePersonRepository(db);
});

final categoryRepositoryProvider = Provider<ICategoryRepository>((ref) {
  final db = ref.watch(appDatabaseProvider);
  return SqliteCategoryRepository(db);
});

final expenseRepositoryProvider = Provider<IExpenseRepository>((ref) {
  final db = ref.watch(appDatabaseProvider);
  return SqliteExpenseRepository(db);
});

final recurringExpenseServiceProvider =
    Provider<RecurringExpenseService>((ref) {
  return RecurringExpenseService(ref.watch(appDatabaseProvider));
});

final notificationServiceProvider = Provider<NotificationService>((ref) {
  return NotificationService();
});

final budgetRepositoryProvider = Provider<IBudgetRepository>((ref) {
  final db = ref.watch(appDatabaseProvider);
  return SqliteBudgetRepository(db);
});

final receiptRepositoryProvider = Provider<IReceiptRepository>((ref) {
  final db = ref.watch(appDatabaseProvider);
  return SqliteReceiptRepository(db);
});
