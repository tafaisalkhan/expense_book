import 'package:myexpence/features/budgets/presentation/providers/budget_providers.dart';
import 'package:myexpence/features/calendar/presentation/providers/calendar_providers.dart';
import 'package:myexpence/features/categories/presentation/providers/category_providers.dart';
import 'package:myexpence/features/dashboard/presentation/providers/dashboard_providers.dart';
import 'package:myexpence/features/expenses/presentation/providers/expense_providers.dart';
import 'package:myexpence/features/people/presentation/providers/people_providers.dart';
import 'package:myexpence/features/settings/presentation/providers/settings_providers.dart';
import 'package:myexpence/features/sms_parser/presentation/providers/sms_whitelist_provider.dart';

void refreshAfterBackupRestore(dynamic ref) {
  ref.invalidate(categoriesListProvider);
  ref.invalidate(categoryNotifierProvider);
  ref.invalidate(pendingRecurringExpensesProvider);
  ref.invalidate(recentExpensesProvider);
  ref.invalidate(allExpensesProvider);
  ref.invalidate(dashboardDataProvider);
  ref.invalidate(calendarMonthDataProvider);
  ref.invalidate(peopleListProvider);
  ref.invalidate(periodBudgetsProvider);
  ref.invalidate(expenseNotifierProvider);
  ref.invalidate(personNotifierProvider);
  ref.invalidate(budgetNotifierProvider);
  ref.invalidate(smsWhitelistProvider);
  ref.invalidate(currencyNotifierProvider);
}
