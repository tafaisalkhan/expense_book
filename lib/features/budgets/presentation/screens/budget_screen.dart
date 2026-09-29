import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:myexpence/core/theme/app_theme.dart';
import 'package:myexpence/core/utils/currency_formatters.dart';
import 'package:myexpence/features/budgets/domain/models/budget.dart';
import 'package:myexpence/features/budgets/presentation/providers/budget_providers.dart';
import 'package:myexpence/features/categories/presentation/providers/category_providers.dart';
import 'package:myexpence/features/dashboard/presentation/providers/dashboard_providers.dart';
import 'package:uuid/uuid.dart';

class BudgetScreen extends ConsumerWidget {
  const BudgetScreen({super.key});

  void _showSetBudgetDialog(BuildContext context, WidgetRef ref, {String? categoryId, String? categoryName, Budget? existing}) {
    final controller = TextEditingController(text: existing != null ? existing.amount.toStringAsFixed(0) : '');
    final period = ref.read(currentPeriodProvider);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(categoryId == null ? 'Set Total Monthly Budget' : 'Set Budget for $categoryName'),
        content: TextField(
          controller: controller,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(
            labelText: 'Budget Amount (Rs)',
            prefixText: 'Rs ',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              final amount = double.tryParse(controller.text) ?? 0.0;
              if (amount <= 0) return;

              final nowStr = DateTime.now().toIso8601String();
              final budget = Budget(
                uuid: existing?.uuid ?? const Uuid().v4(),
                period: period,
                categoryId: categoryId,
                amount: amount,
                createdAt: existing?.createdAt ?? nowStr,
                updatedAt: nowStr,
              );

              await ref.read(budgetNotifierProvider.notifier).setBudget(budget);
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final period = ref.watch(currentPeriodProvider);
    final budgetsAsync = ref.watch(periodBudgetsProvider);
    final dashboardAsync = ref.watch(dashboardDataProvider);
    final categoriesAsync = ref.watch(categoriesListProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text('Budgets ($period)'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: 'Set Monthly Budget',
            onPressed: () {
              final budgets = ref.read(periodBudgetsProvider).value ?? [];
              final totalBudget = budgets.cast<Budget?>().firstWhere((b) => b?.categoryId == null, orElse: () => null);
              _showSetBudgetDialog(context, ref, existing: totalBudget);
            },
          ),
        ],
      ),
      body: dashboardAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (err, _) => Center(child: Text('Error: $err')),
            data: (dashboardData) {
              final monthSpent = dashboardData.monthTotal;

              return budgetsAsync.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (err, _) => Center(child: Text('Error loading budgets: $err')),
                data: (budgets) {
                  final Budget? totalBudget = budgets.cast<Budget?>().firstWhere(
                        (b) => b?.categoryId == null,
                        orElse: () => null,
                      );

                  final double totalBudgetAmount = totalBudget?.amount ?? 0.0;
                  final double remaining = totalBudgetAmount - monthSpent;
                  final double overallProgress = totalBudgetAmount > 0 ? (monthSpent / totalBudgetAmount) : 0.0;

                  return SingleChildScrollView(
                    padding: const EdgeInsets.only(left: 16, right: 16, top: 16, bottom: 90),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Total Monthly Budget Overview Card
                        Card(
                          color: AppTheme.primaryColor,
                          child: Padding(
                            padding: const EdgeInsets.all(20),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    const Text('TOTAL MONTHLY BUDGET', style: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.bold)),
                                    IconButton(
                                      icon: const Icon(Icons.edit, color: Colors.white, size: 20),
                                      onPressed: () => _showSetBudgetDialog(context, ref, existing: totalBudget),
                                    ),
                                  ],
                                ),
                                Text(
                                  CurrencyFormatters.format(totalBudgetAmount),
                                  style: const TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.bold),
                                ),
                                const SizedBox(height: 12),
                                LinearProgressIndicator(
                                  value: overallProgress.clamp(0.0, 1.0),
                                  backgroundColor: Colors.white24,
                                  color: overallProgress >= 1.0
                                      ? Colors.redAccent
                                      : (overallProgress >= 0.9 ? Colors.amberAccent : Colors.white),
                                  minHeight: 8,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                const SizedBox(height: 12),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text('Spent: ${CurrencyFormatters.formatCompact(monthSpent)}', style: const TextStyle(color: Colors.white, fontSize: 13)),
                                    Text('Remaining: ${CurrencyFormatters.formatCompact(remaining)}', style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 24),

                        // Category Budgets Section
                        Text('Category Budgets', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                        const SizedBox(height: 8),

                        categoriesAsync.when(
                          loading: () => const CircularProgressIndicator(),
                          error: (e, _) => Text('Error loading categories: $e'),
                          data: (categories) {
                            return Column(
                              children: categories.map((cat) {
                                final catSpent = dashboardData.categoryBreakdown[cat.id] ?? 0.0;
                                final Budget? catBudget = budgets.cast<Budget?>().firstWhere(
                                      (b) => b?.categoryId == cat.id,
                                      orElse: () => null,
                                    );

                                final double catBudgetAmount = catBudget?.amount ?? 0.0;
                                final double progress = catBudgetAmount > 0 ? (catSpent / catBudgetAmount) : 0.0;

                                return Card(
                                  margin: const EdgeInsets.only(bottom: 8),
                                  child: Padding(
                                    padding: const EdgeInsets.all(16),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                          children: [
                                            Text(cat.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                                            Row(
                                              children: [
                                                Text(
                                                  catBudgetAmount > 0
                                                      ? '${CurrencyFormatters.formatCompact(catSpent)} / ${CurrencyFormatters.formatCompact(catBudgetAmount)}'
                                                      : 'Spent: ${CurrencyFormatters.formatCompact(catSpent)}',
                                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                                ),
                                                IconButton(
                                                  icon: const Icon(Icons.edit, size: 18),
                                                  onPressed: () => _showSetBudgetDialog(context, ref, categoryId: cat.id, categoryName: cat.name, existing: catBudget),
                                                ),
                                              ],
                                            ),
                                          ],
                                        ),
                                        if (catBudgetAmount > 0) ...[
                                          const SizedBox(height: 8),
                                          LinearProgressIndicator(
                                            value: progress.clamp(0.0, 1.0),
                                            backgroundColor: Colors.grey[200],
                                            color: progress >= 1.0 ? Colors.red : (progress >= 0.9 ? Colors.amber : AppTheme.primaryColor),
                                            minHeight: 6,
                                            borderRadius: BorderRadius.circular(3),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                );
                              }).toList(),
                            );
                          },
                        ),
                      ],
                    ),
                  );
                },
              );
            },
          ),
    );
  }
}
