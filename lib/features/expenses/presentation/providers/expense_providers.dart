import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:myexpence/core/providers/core_providers.dart';
import 'package:myexpence/features/calendar/presentation/providers/calendar_providers.dart';
import 'package:myexpence/features/dashboard/presentation/providers/dashboard_providers.dart';
import 'package:myexpence/features/expenses/domain/models/expense.dart';

final recentExpensesProvider = FutureProvider<List<Expense>>((ref) async {
  final repo = ref.watch(expenseRepositoryProvider);
  return await repo.getRecentExpenses(limit: 20);
});

final allExpensesProvider = FutureProvider<List<Expense>>((ref) async {
  final repo = ref.watch(expenseRepositoryProvider);
  return await repo.getAllExpenses();
});

final pendingRecurringExpensesProvider =
    FutureProvider<List<Expense>>((ref) async {
  await ref.watch(recurringExpenseServiceProvider).generateDueExpenses();
  return ref.watch(expenseRepositoryProvider).getPendingExpenses();
});

class ExpenseNotifier extends StateNotifier<AsyncValue<void>> {
  final Ref ref;

  ExpenseNotifier(this.ref) : super(const AsyncValue.data(null));

  Future<void> addExpense(Expense expense) async {
    state = const AsyncValue.loading();
    try {
      final repo = ref.read(expenseRepositoryProvider);
      await repo.addExpense(expense);
      ref.invalidate(recentExpensesProvider);
      ref.invalidate(allExpensesProvider);
      ref.invalidate(dashboardDataProvider);
      ref.invalidate(calendarMonthDataProvider);
      state = const AsyncValue.data(null);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  Future<void> updateExpense(Expense expense) async {
    state = const AsyncValue.loading();
    try {
      final repo = ref.read(expenseRepositoryProvider);
      await repo.updateExpense(expense);
      ref.invalidate(recentExpensesProvider);
      ref.invalidate(allExpensesProvider);
      ref.invalidate(dashboardDataProvider);
      ref.invalidate(calendarMonthDataProvider);
      state = const AsyncValue.data(null);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  Future<void> deleteExpense(String uuid) async {
    state = const AsyncValue.loading();
    try {
      final repo = ref.read(expenseRepositoryProvider);
      await repo.deleteExpense(uuid);
      ref.invalidate(recentExpensesProvider);
      ref.invalidate(allExpensesProvider);
      ref.invalidate(dashboardDataProvider);
      ref.invalidate(calendarMonthDataProvider);
      state = const AsyncValue.data(null);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  Future<void> approveExpense(String uuid) async {
    await ref.read(expenseRepositoryProvider).approveExpense(uuid);
    _refreshExpenses();
  }

  Future<void> rejectExpense(String uuid) async {
    await ref.read(expenseRepositoryProvider).rejectExpense(uuid);
    _refreshExpenses();
  }

  void _refreshExpenses() {
    ref.invalidate(pendingRecurringExpensesProvider);
    ref.invalidate(recentExpensesProvider);
    ref.invalidate(allExpensesProvider);
    ref.invalidate(dashboardDataProvider);
    ref.invalidate(calendarMonthDataProvider);
  }

  Future<void> confirmZeroSpend(String date) async {
    state = const AsyncValue.loading();
    try {
      final repo = ref.read(expenseRepositoryProvider);
      await repo.confirmZeroSpendDay(date);
      ref.invalidate(dashboardDataProvider);
      ref.invalidate(calendarMonthDataProvider);
      state = const AsyncValue.data(null);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }
}

final expenseNotifierProvider =
    StateNotifierProvider<ExpenseNotifier, AsyncValue<void>>((ref) {
  return ExpenseNotifier(ref);
});
