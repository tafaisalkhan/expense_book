import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:myexpence/core/theme/app_theme.dart';
import 'package:myexpence/core/utils/category_icon_helper.dart';
import 'package:myexpence/core/utils/currency_formatters.dart';
import 'package:myexpence/core/utils/date_formatters.dart';
import 'package:myexpence/features/ads/presentation/providers/ad_providers.dart';
import 'package:myexpence/features/categories/domain/models/category.dart';
import 'package:myexpence/features/expenses/domain/models/expense.dart';
import 'package:myexpence/features/expenses/domain/models/expense_classification.dart';

Color _getClassificationColor(ExpenseClassification classification) {
  switch (classification) {
    case ExpenseClassification.urgent:
      return AppTheme.urgentColor;
    case ExpenseClassification.required:
      return AppTheme.requiredColor;
    case ExpenseClassification.optional:
      return AppTheme.optionalColor;
    case ExpenseClassification.lost:
      return AppTheme.lostColor;
  }
}

/// Displays all expenses matching a specific Category or Subcategory
/// in the user's selected period. Tapping any expense opens it in edit mode.
Future<void> showCategoryExpenseDetailSheet({
  required BuildContext context,
  required WidgetRef ref,
  required String title,
  required bool isSubcategory,
  required double totalAmount,
  required List<Expense> expenses,
  required Map<String, Category> categoryMap,
  String? timeframeLabel,
}) async {
  // Sort with latest date first
  final sortedExpenses = List<Expense>.from(expenses)
    ..sort((a, b) => b.expenseDate.compareTo(a.expenseDate));

  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Theme.of(context).scaffoldBackgroundColor,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (ctx) {
      return DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.75,
        maxChildSize: 0.95,
        minChildSize: 0.4,
        builder: (_, scrollController) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    CircleAvatar(
                      backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                      foregroundColor: Theme.of(context).colorScheme.primary,
                      child: Icon(
                        isSubcategory ? Icons.subdirectory_arrow_right : Icons.category,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  isSubcategory ? 'Subcategory' : 'Category',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    color: Theme.of(context).colorScheme.primary,
                                  ),
                                ),
                              ),
                              if (timeframeLabel != null && timeframeLabel.isNotEmpty) ...[
                                const SizedBox(width: 6),
                                Text(
                                  timeframeLabel,
                                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                                ),
                              ],
                            ],
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      visualDensity: VisualDensity.compact,
                      onPressed: () => Navigator.pop(ctx),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.25),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Total Spend',
                            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500),
                          ),
                          Text(
                            '${sortedExpenses.length} transaction${sortedExpenses.length == 1 ? '' : 's'}',
                            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                          ),
                        ],
                      ),
                      Text(
                        '${CurrencyFormatters.defaultCurrency} ${CurrencyFormatters.format(totalAmount)}',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Transactions (tap to edit)',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey.shade700,
                  ),
                ),
                const SizedBox(height: 6),
                Expanded(
                  child: sortedExpenses.isEmpty
                      ? Center(
                          child: Text(
                            'No transactions found for $title in this period.',
                            style: TextStyle(color: Colors.grey.shade600),
                          ),
                        )
                      : ListView.separated(
                          controller: scrollController,
                          itemCount: sortedExpenses.length,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (context, idx) {
                            final exp = sortedExpenses[idx];
                            final category = categoryMap[exp.categoryId];
                            final iconData = CategoryIconHelper.getIconData(category?.icon);
                            final classificationColor = _getClassificationColor(exp.classification);

                            String itemTitle = exp.description?.trim() ?? '';
                            if (itemTitle.isEmpty) {
                              itemTitle = exp.merchant?.trim() ?? '';
                            }
                            if (itemTitle.isEmpty) {
                              itemTitle = category?.name ?? 'Expense';
                            }

                            final dateStr = DateFormatters.formatDateDisplay(
                              DateFormatters.parseDateIso(exp.expenseDate),
                            );

                            return ListTile(
                              contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                              leading: CircleAvatar(
                                backgroundColor: Theme.of(context).colorScheme.secondaryContainer,
                                child: Icon(iconData, size: 20),
                              ),
                              title: Text(
                                itemTitle,
                                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              subtitle: Padding(
                                padding: const EdgeInsets.only(top: 4.0),
                                child: Wrap(
                                  crossAxisAlignment: WrapCrossAlignment.center,
                                  spacing: 6,
                                  runSpacing: 4,
                                  children: [
                                    Text(
                                      dateStr,
                                      style: TextStyle(fontSize: 11, color: Colors.grey.shade700),
                                    ),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                      decoration: BoxDecoration(
                                        color: classificationColor.withValues(alpha: 0.12),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Text(
                                        exp.classification.label,
                                        style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                          color: classificationColor,
                                        ),
                                      ),
                                    ),
                                    if (exp.allocations.isNotEmpty &&
                                        exp.allocations.first.personName.trim().isNotEmpty) ...[
                                      Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(Icons.person, size: 11, color: Colors.grey.shade600),
                                          const SizedBox(width: 2),
                                          Text(
                                            exp.allocations.first.personName.trim(),
                                            style: TextStyle(fontSize: 10, color: Colors.grey.shade600),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    '${CurrencyFormatters.defaultCurrency} ${CurrencyFormatters.format(exp.amount)}',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13,
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  const Icon(Icons.chevron_right, size: 16, color: Colors.grey),
                                ],
                              ),
                              onTap: () {
                                Navigator.pop(ctx);
                                ref.read(adNotifierProvider.notifier).recordNavigation(context);
                                context.push('/add', extra: exp);
                              },
                            );
                          },
                        ),
                ),
              ],
            ),
          );
        },
      );
    },
  );
}

/// Displays the full breakdown of ALL categories or subcategories for the selected period.
/// Tapping on any item opens the detail expense sheet for that specific item.
Future<void> showAllBreakdownSheet({
  required BuildContext context,
  required WidgetRef ref,
  required bool isSubcategory,
  required List<MapEntry<String, double>> entries,
  required double totalAmount,
  required List<Expense> allPeriodExpenses,
  required Map<String, Category> categoryMap,
  required Map<String, String> subNameMap,
  String? timeframeLabel,
}) async {
  final safeTotal = totalAmount > 0 ? totalAmount : 1.0;

  final colors = [
    const Color(0xFF6C5CE7),
    const Color(0xFF00B894),
    const Color(0xFFFF7675),
    const Color(0xFF00CEC9),
    const Color(0xFFFDCB6E),
    const Color(0xFFE17055),
    const Color(0xFFA29BFE),
    const Color(0xFFE84393),
    const Color(0xFF0984E3),
    const Color(0xFF2D3436),
  ];

  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Theme.of(context).scaffoldBackgroundColor,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (ctx) {
      return DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.8,
        maxChildSize: 0.95,
        minChildSize: 0.45,
        builder: (_, scrollController) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    CircleAvatar(
                      backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                      foregroundColor: Theme.of(context).colorScheme.primary,
                      child: Icon(isSubcategory ? Icons.view_list : Icons.pie_chart, size: 20),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            isSubcategory ? 'All Subcategories' : 'All Categories',
                            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                          ),
                          Row(
                            children: [
                              Text(
                                '${entries.length} items',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: Theme.of(context).colorScheme.primary,
                                ),
                              ),
                              if (timeframeLabel != null && timeframeLabel.isNotEmpty) ...[
                                const SizedBox(width: 6),
                                Text(
                                  '• $timeframeLabel',
                                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                                ),
                              ],
                            ],
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      visualDensity: VisualDensity.compact,
                      onPressed: () => Navigator.pop(ctx),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.25),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Total Period Spending',
                          style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                      Text(
                        '${CurrencyFormatters.defaultCurrency} ${CurrencyFormatters.format(totalAmount)}',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Ranked by Spending (tap to view individual expenses)',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey.shade700,
                  ),
                ),
                const SizedBox(height: 6),
                Expanded(
                  child: entries.isEmpty
                      ? Center(
                          child: Text(
                            'No spending data in this period.',
                            style: TextStyle(color: Colors.grey.shade600),
                          ),
                        )
                      : ListView.separated(
                          controller: scrollController,
                          itemCount: entries.length,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (context, idx) {
                            final entry = entries[idx];
                            final displayName = isSubcategory
                                ? entry.key
                                : (categoryMap[entry.key]?.name ?? entry.key);
                            final amt = entry.value;
                            final pct = (amt / safeTotal) * 100;
                            final color = colors[idx % colors.length];

                            return InkWell(
                              borderRadius: BorderRadius.circular(8),
                              onTap: () {
                                // Filter matching expenses for this entry
                                final List<Expense> matching;
                                if (isSubcategory) {
                                  matching = allPeriodExpenses.where((exp) {
                                    if (exp.isDeleted || exp.status == ExpenseStatus.cancelled) {
                                      return false;
                                    }
                                    final subId = exp.subcategoryId;
                                    String name;
                                    if (subId != null && subNameMap.containsKey(subId)) {
                                      name = subNameMap[subId]!;
                                    } else if (subId != null && subId.trim().isNotEmpty) {
                                      name = subId;
                                    } else {
                                      final catName = categoryMap[exp.categoryId]?.name ?? exp.categoryId;
                                      name = '$catName (General)';
                                    }
                                    return name == entry.key;
                                  }).toList();
                                } else {
                                  matching = allPeriodExpenses.where((exp) {
                                    if (exp.isDeleted || exp.status == ExpenseStatus.cancelled) {
                                      return false;
                                    }
                                    if (exp.categoryId == entry.key) return true;
                                    final catName = categoryMap[exp.categoryId]?.name;
                                    return catName == entry.key;
                                  }).toList();
                                }

                                Navigator.pop(ctx);
                                showCategoryExpenseDetailSheet(
                                  context: context,
                                  ref: ref,
                                  title: displayName,
                                  isSubcategory: isSubcategory,
                                  totalAmount: amt,
                                  expenses: matching,
                                  categoryMap: categoryMap,
                                  timeframeLabel: timeframeLabel,
                                );
                              },
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Container(
                                          width: 22,
                                          height: 22,
                                          alignment: Alignment.center,
                                          decoration: BoxDecoration(
                                            color: color.withValues(alpha: 0.15),
                                            shape: BoxShape.circle,
                                          ),
                                          child: Text(
                                            '${idx + 1}',
                                            style: TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.bold,
                                              color: color,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 10),
                                        Expanded(
                                          child: Text(
                                            displayName,
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w600,
                                              fontSize: 14,
                                            ),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                        Column(
                                          crossAxisAlignment: CrossAxisAlignment.end,
                                          children: [
                                            Text(
                                              '${CurrencyFormatters.defaultCurrency} ${CurrencyFormatters.format(amt)}',
                                              style: const TextStyle(
                                                fontWeight: FontWeight.bold,
                                                fontSize: 13,
                                              ),
                                            ),
                                            Text(
                                              '${pct.toStringAsFixed(1)}%',
                                              style: TextStyle(
                                                fontSize: 11,
                                                color: Colors.grey.shade600,
                                                fontWeight: FontWeight.w500,
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(width: 4),
                                        const Icon(Icons.chevron_right, size: 16, color: Colors.grey),
                                      ],
                                    ),
                                    const SizedBox(height: 6),
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(3),
                                      child: LinearProgressIndicator(
                                        value: (pct / 100).clamp(0.0, 1.0),
                                        backgroundColor: Colors.grey.shade200,
                                        valueColor: AlwaysStoppedAnimation<Color>(color),
                                        minHeight: 5,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
          );
        },
      );
    },
  );
}
