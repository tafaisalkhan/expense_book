import 'package:myexpence/features/expenses/domain/models/expense.dart';
import 'package:myexpence/features/expenses/domain/models/expense_classification.dart';

abstract class IExpenseRepository {
  Future<Expense> addExpense(Expense expense);
  Future<void> updateExpense(Expense expense);
  Future<void> deleteExpense(String uuid);
  Future<Expense?> getExpenseByUuid(String uuid);
  Future<List<Expense>> getExpensesForPeriod({
    required String startDate,
    required String endDate,
    String? personId,
    String? categoryId,
    ExpenseClassification? classification,
  });
  Future<double> getTotalSpentForPeriod({
    required String startDate,
    required String endDate,
    String? personId,
    ExpenseClassification? classification,
  });
  Future<Map<ExpenseClassification, double>> getSpendingByClassification({
    required String startDate,
    required String endDate,
  });
  Future<Map<String, double>> getSpendingByCategory({
    required String startDate,
    required String endDate,
    String? personId,
  });
  Future<Map<String, double>> getSpendingByPerson({
    required String startDate,
    required String endDate,
  });
  Future<List<Expense>> getRecentExpenses({int limit = 10});
  Future<List<Expense>> getAllExpenses();
  Future<Map<String, double>> getSpendingBySubcategory({
    required String startDate,
    required String endDate,
    String? personId,
  });
  Future<List<Expense>> getPendingExpenses();
  Future<void> approveExpense(String uuid);
  Future<void> rejectExpense(String uuid);
  Future<void> confirmZeroSpendDay(String date);
  Future<bool> isZeroSpendDayConfirmed(String date);
}
