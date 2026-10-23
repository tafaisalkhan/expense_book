import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:myexpence/core/theme/app_theme.dart';
import 'package:myexpence/core/utils/currency_formatters.dart';
import 'package:myexpence/features/analytics/presentation/providers/analytics_providers.dart';
import 'package:myexpence/features/analytics/presentation/widgets/period_comparison_widget.dart';
import 'package:myexpence/features/categories/presentation/providers/category_providers.dart';
import 'package:myexpence/features/expenses/domain/models/expense.dart';
import 'package:myexpence/features/expenses/domain/models/expense_classification.dart';

class AnalyticsScreen extends ConsumerStatefulWidget {
  const AnalyticsScreen({super.key});

  @override
  ConsumerState<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends ConsumerState<AnalyticsScreen> {
  bool _showSubcategories = false;

  @override
  Widget build(BuildContext context) {
    final selectedPeriod = ref.watch(selectedReportPeriodProvider);
    final reportAsync = ref.watch(analyticsReportDataProvider);
    final categoriesList = ref.watch(categoriesListProvider).valueOrNull ?? [];
    final categoryMap = {for (var c in categoriesList) c.id: c};

    return Scaffold(
      appBar: AppBar(
        title: const Text('Spending Analytics & Reports'),
      ),
      body: Column(
        children: [
          // Period Selector ScrollBar
          Container(
            color: Theme.of(context).cardColor,
            padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 12.0),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: ReportPeriod.values.map((period) {
                  final isSelected = selectedPeriod == period;
                  return Padding(
                    padding: const EdgeInsets.only(right: 8.0),
                    child: FilterChip(
                      label: Text(period.label),
                      selected: isSelected,
                      selectedColor: AppTheme.primaryColor.withOpacity(0.2),
                      checkmarkColor: AppTheme.primaryColor,
                      labelStyle: TextStyle(
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                        color: isSelected ? AppTheme.primaryColor : null,
                      ),
                      onSelected: (_) async {
                        if (period == ReportPeriod.custom) {
                          final pickerRange = await showDateRangePicker(
                            context: context,
                            firstDate: DateTime(2020),
                            lastDate: DateTime.now().add(const Duration(days: 365)),
                          );
                          if (pickerRange != null) {
                            ref.read(customDateRangeProvider.notifier).state = CustomDateRange(
                              startDate: pickerRange.start,
                              endDate: pickerRange.end,
                            );
                            ref.read(selectedReportPeriodProvider.notifier).state = ReportPeriod.custom;
                          }
                        } else {
                          ref.read(selectedReportPeriodProvider.notifier).state = period;
                        }
                      },
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
          const Divider(height: 1),

          // Main Content
          Expanded(
            child: reportAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (err, _) => Center(child: Text('Error loading analytics report: $err')),
              data: (data) {
                final reqAmount = data.classificationBreakdown[ExpenseClassification.required] ?? 0;
                final optAmount = data.classificationBreakdown[ExpenseClassification.optional] ?? 0;
                final total = reqAmount + optAmount;

                return SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Period Comparison Widget
                      const PeriodComparisonWidget(),
                      const SizedBox(height: 20),

                      // Period Total Overview Header
                      Card(
                        color: Theme.of(context).colorScheme.surfaceContainerHighest.withOpacity(0.3),
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    data.periodLabel.toUpperCase(),
                                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    CurrencyFormatters.format(data.totalSpent),
                                    style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                                  ),
                                ],
                              ),
                              Text(
                                '${data.expenses.length} Expenses',
                                style: const TextStyle(fontWeight: FontWeight.w600, color: AppTheme.primaryColor),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),

                      // Classification Pie Chart Card
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(20.0),
                          child: Column(
                            children: [
                              Text(
                                '${data.periodLabel} Classification',
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                              ),
                              const SizedBox(height: 20),

                              if (total == 0)
                                const Padding(
                                  padding: EdgeInsets.symmetric(vertical: 32),
                                  child: Text('No expenses recorded for this period.'),
                                )
                              else ...[
                                SizedBox(
                                  height: 200,
                                  child: PieChart(
                                    PieChartData(
                                      sectionsSpace: 4,
                                      centerSpaceRadius: 40,
                                      sections: [
                                        if (reqAmount > 0)
                                          PieChartSectionData(
                                            color: AppTheme.requiredColor,
                                            value: reqAmount,
                                            title: '${((reqAmount / total) * 100).toStringAsFixed(0)}%',
                                            radius: 50,
                                            titleStyle: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                                          ),
                                        if (optAmount > 0)
                                          PieChartSectionData(
                                            color: AppTheme.optionalColor,
                                            value: optAmount,
                                            title: '${((optAmount / total) * 100).toStringAsFixed(0)}%',
                                            radius: 50,
                                            titleStyle: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                                          ),
                                      ],
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 20),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                                  children: [
                                    _buildLegend('Required', AppTheme.requiredColor, reqAmount),
                                    _buildLegend('Optional', AppTheme.optionalColor, optAmount),
                                  ],
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),

                      // Optional Savings Opportunity Banner
                      if (optAmount > 0)
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: AppTheme.optionalColor.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: AppTheme.optionalColor.withOpacity(0.3)),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.savings_outlined, color: AppTheme.optionalColor, size: 32),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'Potentially Adjustable Spending',
                                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: AppTheme.optionalColor),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      'You spent ${CurrencyFormatters.format(optAmount)} on optional items in this period. Reducing discretionary spending here offers savings potential.',
                                      style: const TextStyle(fontSize: 12),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      const SizedBox(height: 24),

                      // Category / Subcategory Breakdown Section
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text(
                              _showSubcategories
                                  ? 'Top Subcategories (${data.periodLabel})'
                                  : 'Top Categories (${data.periodLabel})',
                              style: Theme.of(context)
                                  .textTheme
                                  .titleMedium
                                  ?.copyWith(fontWeight: FontWeight.bold),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          SegmentedButton<bool>(
                            segments: const [
                              ButtonSegment(
                                value: false,
                                label: Text('Category', style: TextStyle(fontSize: 11)),
                              ),
                              ButtonSegment(
                                value: true,
                                label: Text('Subcategory', style: TextStyle(fontSize: 11)),
                              ),
                            ],
                            selected: {_showSubcategories},
                            onSelectionChanged: (val) {
                              setState(() {
                                _showSubcategories = val.first;
                              });
                            },
                            style: const ButtonStyle(
                              visualDensity: VisualDensity.compact,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Builder(
                        builder: (context) {
                          final List<MapEntry<String, double>> entries;
                          if (_showSubcategories) {
                            final subNameMap = <String, String>{};
                            for (final cat in categoryMap.values) {
                              for (final sub in cat.subcategories) {
                                subNameMap[sub.id] = sub.name;
                                if (sub.uuid != null) subNameMap[sub.uuid!] = sub.name;
                              }
                            }
                            final map = <String, double>{};
                            for (final exp in data.expenses) {
                              if (exp.isDeleted || exp.status == ExpenseStatus.cancelled) continue;
                              final subId = exp.subcategoryId;
                              String displayName;
                              if (subId != null && subNameMap.containsKey(subId)) {
                                displayName = subNameMap[subId]!;
                              } else if (subId != null && subId.trim().isNotEmpty) {
                                displayName = subId;
                              } else {
                                final catName = categoryMap[exp.categoryId]?.name ??
                                    exp.categoryId.replaceAll('cat_', '').toUpperCase();
                                displayName = '$catName (General)';
                              }
                              map[displayName] = (map[displayName] ?? 0.0) + exp.amount;
                            }
                            entries = map.entries.toList()
                              ..sort((a, b) => b.value.compareTo(a.value));
                          } else {
                            entries = data.categoryBreakdown.entries.map((e) {
                              final name = categoryMap[e.key]?.name ??
                                  e.key.replaceAll('cat_', '').toUpperCase();
                              return MapEntry(name, e.value);
                            }).toList();
                          }

                          return Card(
                            child: Padding(
                              padding: const EdgeInsets.all(16.0),
                              child: entries.isEmpty
                                  ? Text(_showSubcategories
                                      ? 'No subcategory data for this period.'
                                      : 'No category data for this period.')
                                  : Column(
                                      children: entries.map((e) {
                                        final catPercent =
                                            total > 0 ? (e.value / total) * 100 : 0.0;
                                        return Padding(
                                          padding:
                                              const EdgeInsets.symmetric(vertical: 8.0),
                                          child: Column(
                                            children: [
                                              Row(
                                                mainAxisAlignment:
                                                    MainAxisAlignment.spaceBetween,
                                                children: [
                                                  Expanded(
                                                    child: Text(e.key,
                                                        style: const TextStyle(
                                                            fontWeight: FontWeight.bold),
                                                        overflow: TextOverflow.ellipsis),
                                                  ),
                                                  Text(CurrencyFormatters.format(e.value),
                                                      style: const TextStyle(
                                                          fontWeight: FontWeight.bold)),
                                                ],
                                              ),
                                              const SizedBox(height: 4),
                                              LinearProgressIndicator(
                                                value: (catPercent / 100).clamp(0.0, 1.0),
                                                backgroundColor: Colors.grey[200],
                                                color: AppTheme.primaryColor,
                                                borderRadius: BorderRadius.circular(4),
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
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLegend(String label, Color color, double amount) {
    return Column(
      children: [
        Row(
          children: [
            Container(width: 12, height: 12, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
            const SizedBox(width: 6),
            Text(label, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
          ],
        ),
        const SizedBox(height: 4),
        Text(CurrencyFormatters.formatCompact(amount), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
      ],
    );
  }
}
