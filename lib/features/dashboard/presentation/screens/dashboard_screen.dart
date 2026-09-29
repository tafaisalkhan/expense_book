import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:myexpence/core/theme/app_theme.dart';
import 'package:myexpence/core/utils/currency_formatters.dart';
import 'package:myexpence/core/utils/date_formatters.dart';
import 'package:myexpence/features/auth/domain/models/auth_user.dart';
import 'package:myexpence/features/auth/presentation/providers/auth_providers.dart';
import 'package:myexpence/core/utils/category_icon_helper.dart';
import 'package:myexpence/features/categories/presentation/providers/category_providers.dart';
import 'package:myexpence/features/dashboard/presentation/providers/dashboard_providers.dart';
import 'package:myexpence/features/expenses/domain/models/expense_classification.dart';
import 'package:myexpence/features/expenses/presentation/providers/expense_providers.dart';
import 'package:myexpence/features/people/presentation/providers/people_providers.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dashboardAsync = ref.watch(dashboardDataProvider);
    final recentExpensesAsync = ref.watch(recentExpensesProvider);
    final peopleAsync = ref.watch(peopleListProvider);
    final categoriesList = ref.watch(categoriesListProvider).valueOrNull ?? [];
    final categoryMap = {for (var c in categoriesList) c.id: c};

    final now = DateTime.now();
    final monthName = DateFormatters.formatMonthYear(now);

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('MyExpense'),
            Text(
              monthName,
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                fontWeight: FontWeight.normal,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              ref.invalidate(dashboardDataProvider);
              ref.invalidate(recentExpensesProvider);
            },
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(dashboardDataProvider);
          ref.invalidate(recentExpensesProvider);
        },
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16.0),
          physics: const AlwaysScrollableScrollPhysics(),
          child: dashboardAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (err, stack) => Center(child: Text('Error loading dashboard: $err')),
            data: (data) {
              final authUser = ref.watch(authProvider);

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 0. Logged In User Profile Banner
                  if (authUser.isLoggedIn) ...[
                    _buildUserProfileBanner(context, authUser),
                    const SizedBox(height: 16),
                  ],

                  // 1. Monthly Overview Card
                  _buildMonthOverviewCard(context, data),
                  const SizedBox(height: 16),

                  // 2. Today vs Yesterday Comparison Row
                  _buildDailyComparisonRow(context, data),
                  const SizedBox(height: 16),

                  // 3. Zero Spend Banner / Daily Check
                  _buildZeroSpendBanner(context, ref, data),
                  const SizedBox(height: 16),

                  // 4. Classification Breakdown (Required / Need / Optional)
                  _buildClassificationSection(context, data),
                  const SizedBox(height: 24),

                  // 5. Family Member Breakdown
                  _buildFamilySection(context, ref, data, peopleAsync),
                  const SizedBox(height: 24),

                  // 6. Recent Expenses Header & List
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Recent Expenses',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                      ),
                      TextButton(
                        onPressed: () => context.go('/expenses'),
                        child: const Text('See All'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),

                  recentExpensesAsync.when(
                    loading: () => const Center(child: CircularProgressIndicator()),
                    error: (e, _) => Text('Error loading expenses: $e'),
                    data: (expenses) {
                      if (expenses.isEmpty) {
                        return Container(
                          padding: const EdgeInsets.all(24),
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.surfaceContainerHighest.withOpacity(0.3),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Center(
                            child: Column(
                              children: [
                                Icon(Icons.receipt_long, size: 48, color: Colors.grey[400]),
                                const SizedBox(height: 8),
                                const Text('No expenses recorded yet.'),
                                const SizedBox(height: 8),
                                ElevatedButton.icon(
                                  onPressed: () => context.push('/add'),
                                  icon: const Icon(Icons.add),
                                  label: const Text('Add Expense'),
                                ),
                              ],
                            ),
                          ),
                        );
                      }

                      return ListView.separated(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: expenses.length > 5 ? 5 : expenses.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final item = expenses[index];
                          final cat = categoryMap[item.categoryId];
                          final iconName = cat?.icon ?? item.categoryId;
                          final catName = cat?.name ?? item.categoryId;

                          return ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: CategoryIconHelper.buildCategoryAvatar(
                              iconName: iconName,
                              categoryId: item.categoryId,
                              size: 38,
                              iconSize: 20,
                            ),
                            title: Text(
                              item.merchant?.isNotEmpty == true ? item.merchant! : catName,
                              style: const TextStyle(fontWeight: FontWeight.w600),
                            ),
                            subtitle: Text(
                              '${item.merchant?.isNotEmpty == true ? '$catName • ' : ''}${item.expenseDate}',
                              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                            ),
                            trailing: Text(
                              CurrencyFormatters.format(item.amount),
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 15,
                              ),
                            ),
                          );
                        },
                      );
                    },
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildMonthOverviewCard(BuildContext context, DashboardData data) {
    return Card(
      elevation: 0,
      color: AppTheme.primaryColor,
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'THIS MONTH SPENT',
              style: TextStyle(
                color: Colors.white70,
                fontSize: 12,
                fontWeight: FontWeight.w600,
                letterSpacing: 1.1,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              CurrencyFormatters.format(data.monthTotal),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 32,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildOverviewStat('Required', data.classificationBreakdown[ExpenseClassification.required] ?? 0),
                _buildOverviewStat('Optional', data.classificationBreakdown[ExpenseClassification.optional] ?? 0),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOverviewStat(String label, double amount) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(color: Colors.white60, fontSize: 11),
        ),
        const SizedBox(height: 2),
        Text(
          CurrencyFormatters.formatCompact(amount),
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 14,
          ),
        ),
      ],
    );
  }

  Widget _buildDailyComparisonRow(BuildContext context, DashboardData data) {
    return Row(
      children: [
        Expanded(
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('TODAY', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey)),
                      Icon(Icons.today, size: 16, color: Theme.of(context).colorScheme.primary),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    CurrencyFormatters.format(data.todayTotal),
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('YESTERDAY', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey)),
                      Icon(Icons.history, size: 16, color: Colors.grey),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    CurrencyFormatters.format(data.yesterdayTotal),
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildZeroSpendBanner(BuildContext context, WidgetRef ref, DashboardData data) {
    if (data.isZeroSpendConfirmedToday) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.green.withOpacity(0.12),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.green.withOpacity(0.3)),
        ),
        child: const Row(
          children: [
            Icon(Icons.check_circle, color: Colors.green),
            SizedBox(width: 12),
            Expanded(
              child: Text(
                'Zero-Spend Day Confirmed for Today! Great job keeping records complete.',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
              ),
            ),
          ],
        ),
      );
    }

    if (data.todayTotal > 0) {
      return const SizedBox.shrink();
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.amber.withOpacity(0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.amber.withOpacity(0.4)),
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline, color: Colors.amber),
          const SizedBox(width: 12),
          const Expanded(
            child: Text(
              'No expenses recorded today yet.',
              style: TextStyle(fontWeight: FontWeight.w500, fontSize: 13),
            ),
          ),
          OutlinedButton(
            onPressed: () {
              final todayIso = DateFormatters.todayIso();
              ref.read(expenseNotifierProvider.notifier).confirmZeroSpend(todayIso);
            },
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: const Text('Mark Zero-Spend', style: TextStyle(fontSize: 12)),
          ),
        ],
      ),
    );
  }

  Widget _buildClassificationSection(BuildContext context, DashboardData data) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Spending Classification',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
        ),
        const SizedBox(height: 8),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              children: [
                _buildClassificationRow(
                  'Required Commitments',
                  ExpenseClassification.required.description,
                  data.classificationBreakdown[ExpenseClassification.required] ?? 0,
                  AppTheme.requiredColor,
                ),
                const Divider(height: 24),
                _buildClassificationRow(
                  'Discretionary (Optional)',
                  'Potential savings & flexible area',
                  data.classificationBreakdown[ExpenseClassification.optional] ?? 0,
                  AppTheme.optionalColor,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildClassificationRow(String title, String subtitle, double amount, Color color) {
    return Row(
      children: [
        Container(
          width: 12,
          height: 36,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(6),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              Text(
                subtitle,
                style: const TextStyle(fontSize: 11, color: Colors.grey),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
        Text(
          CurrencyFormatters.format(amount),
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
        ),
      ],
    );
  }

  Widget _buildFamilySection(
    BuildContext context,
    WidgetRef ref,
    DashboardData data,
    AsyncValue<List<dynamic>> peopleAsync,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Text(
                'Family & Household Spending',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Row(
              children: [
                TextButton.icon(
                  style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                  onPressed: () => showAddPersonDialog(context, ref),
                  icon: const Icon(Icons.person_add, size: 16),
                  label: const Text('+ Add Member', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                ),
                IconButton(
                  icon: const Icon(Icons.people_outline, size: 20),
                  onPressed: () => context.go('/people'),
                  tooltip: 'Manage Profiles',
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 4),
        peopleAsync.when(
          loading: () => const SizedBox.shrink(),
          error: (_, __) => const SizedBox.shrink(),
          data: (people) {
            final Map<String, String> personNameMap = {'household': 'General Household'};
            for (final p in people) {
              personNameMap[p.uuid] = p.name;
            }

            if (data.personBreakdown.isEmpty) {
              return Card(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Center(
                    child: Text(
                      'No attributed family expenses yet this month.',
                      style: TextStyle(color: Colors.grey[600], fontSize: 13),
                    ),
                  ),
                ),
              );
            }

            return Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  children: data.personBreakdown.entries.map((entry) {
                    final name = personNameMap[entry.key] ?? 'Member';
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6.0),
                      child: Row(
                        children: [
                          CircleAvatar(
                            radius: 16,
                            backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                            child: Text(
                              name.substring(0, 1).toUpperCase(),
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              name,
                              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                            ),
                          ),
                          Text(
                            CurrencyFormatters.format(entry.value),
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _buildUserProfileBanner(BuildContext context, AuthUser authUser) {
    return Card(
      elevation: 0,
      color: AppTheme.primaryColor.withValues(alpha: 0.08),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: AppTheme.primaryColor.withValues(alpha: 0.3)),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        leading: CircleAvatar(
          backgroundColor: AppTheme.primaryColor,
          child: Text(
            (authUser.displayName ?? authUser.email ?? 'G')[0].toUpperCase(),
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(
                authUser.displayName ?? 'Google User',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.teal,
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Text(
                'FIREBASE AUTH',
                style: TextStyle(fontSize: 8, color: Colors.white, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        subtitle: Text(
          authUser.email ?? '',
          style: TextStyle(fontSize: 12, color: Colors.grey[700]),
        ),
        trailing: IconButton(
          icon: const Icon(Icons.settings, color: AppTheme.primaryColor),
          onPressed: () => context.push('/more'),
          tooltip: 'Profile & Settings',
        ),
      ),
    );
  }
}
