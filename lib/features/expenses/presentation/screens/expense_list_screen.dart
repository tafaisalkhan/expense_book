import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:myexpence/core/theme/app_theme.dart';
import 'package:myexpence/core/utils/currency_formatters.dart';
import 'package:myexpence/core/utils/date_formatters.dart';
import 'package:myexpence/core/utils/category_icon_helper.dart';
import 'package:myexpence/features/categories/presentation/providers/category_providers.dart';
import 'package:myexpence/features/expenses/domain/models/expense_classification.dart';
import 'package:myexpence/features/expenses/presentation/providers/expense_providers.dart';

class ExpenseListScreen extends ConsumerStatefulWidget {
  const ExpenseListScreen({super.key});

  @override
  ConsumerState<ExpenseListScreen> createState() => _ExpenseListScreenState();
}

class _ExpenseListScreenState extends ConsumerState<ExpenseListScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  ExpenseClassification? _selectedClassification;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final recentExpensesAsync = ref.watch(recentExpensesProvider);
    final categoriesList = ref.watch(categoriesListProvider).valueOrNull ?? [];
    final categoryMap = {for (var c in categoriesList) c.id: c};

    return Scaffold(
      appBar: AppBar(
        title: const Text('Expense History'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () => context.push('/add'),
          ),
        ],
      ),
      body: Column(
        children: [
          // Search & Filter Bar
          Padding(
            padding: const EdgeInsets.all(12.0),
            child: Column(
              children: [
                TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: 'Search merchant, description, amount...',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: _searchQuery.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear),
                            onPressed: () {
                              _searchController.clear();
                              setState(() => _searchQuery = '');
                            },
                          )
                        : null,
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                  ),
                  onChanged: (val) {
                    setState(() => _searchQuery = val.trim().toLowerCase());
                  },
                ),
                const SizedBox(height: 8),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      FilterChip(
                        label: const Text('All'),
                        selected: _selectedClassification == null,
                        onSelected: (_) =>
                            setState(() => _selectedClassification = null),
                      ),
                      const SizedBox(width: 8),
                      FilterChip(
                        label: const Text('Urgent'),
                        selected: _selectedClassification ==
                            ExpenseClassification.urgent,
                        onSelected: (_) => setState(() =>
                            _selectedClassification =
                                ExpenseClassification.urgent),
                      ),
                      const SizedBox(width: 8),
                      FilterChip(
                        label: const Text('Required'),
                        selected: _selectedClassification ==
                            ExpenseClassification.required,
                        onSelected: (_) => setState(() =>
                            _selectedClassification =
                                ExpenseClassification.required),
                      ),
                      const SizedBox(width: 8),
                      FilterChip(
                        label: const Text('Optional'),
                        selected: _selectedClassification ==
                            ExpenseClassification.optional,
                        onSelected: (_) => setState(() =>
                            _selectedClassification =
                                ExpenseClassification.optional),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // List View
          Expanded(
            child: recentExpensesAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (err, _) =>
                  Center(child: Text('Error loading expenses: $err')),
              data: (expenses) {
                var filtered = expenses;

                if (_selectedClassification != null) {
                  filtered = filtered
                      .where((e) => e.classification == _selectedClassification)
                      .toList();
                }

                if (_searchQuery.isNotEmpty) {
                  filtered = filtered.where((e) {
                    final m = e.merchant?.toLowerCase() ?? '';
                    final d = e.description?.toLowerCase() ?? '';
                    final c = e.categoryId.toLowerCase();
                    final a = e.amount.toString();
                    return m.contains(_searchQuery) ||
                        d.contains(_searchQuery) ||
                        c.contains(_searchQuery) ||
                        a.contains(_searchQuery);
                  }).toList();
                }

                if (filtered.isEmpty) {
                  return const Center(
                      child: Text('No matching expenses found.'));
                }

                return ListView.separated(
                  itemCount: filtered.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final item = filtered[index];
                    final cat = categoryMap[item.categoryId];
                    final iconName = cat?.icon ?? item.categoryId;
                    final catName = cat?.name ?? item.categoryId;

                    String? subCatName;
                    if (item.subcategoryId != null &&
                        item.subcategoryId!.isNotEmpty &&
                        cat != null) {
                      for (final s in cat.subcategories) {
                        if (s.id == item.subcategoryId ||
                            s.uuid == item.subcategoryId) {
                          subCatName = s.name;
                          break;
                        }
                      }
                    }
                    final fullCategoryDisplay =
                        (subCatName != null && subCatName.isNotEmpty)
                            ? '$catName › $subCatName'
                            : catName;

                    return ListTile(
                      onTap: () => context.push('/add', extra: item),
                      leading: CategoryIconHelper.buildCategoryAvatar(
                        iconName: iconName,
                        categoryId: item.categoryId,
                      ),
                      title: Text(
                        item.merchant?.isNotEmpty == true
                            ? item.merchant!
                            : fullCategoryDisplay,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      subtitle: Text(
                        '${item.merchant?.isNotEmpty == true ? '$fullCategoryDisplay • ' : ''}${DateFormatters.formatDateDisplay(DateFormatters.parseDateIso(item.expenseDate))} • ${item.paymentMethod.label}',
                        style: TextStyle(fontSize: 12, color: Colors.grey[700]),
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                CurrencyFormatters.format(item.amount),
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold, fontSize: 15),
                              ),
                              Text(
                                item.classification.label,
                                style: TextStyle(
                                  fontSize: 11,
                                  color: _getClassificationColor(
                                      item.classification),
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                          PopupMenuButton<String>(
                            icon: const Icon(Icons.more_vert,
                                size: 20, color: Colors.grey),
                            onSelected: (action) async {
                              if (action == 'edit') {
                                context.push('/add', extra: item);
                              } else if (action == 'delete') {
                                final confirm = await showDialog<bool>(
                                  context: context,
                                  builder: (ctx) => AlertDialog(
                                    title: const Text('Delete Expense'),
                                    content: Text(
                                      'Are you sure you want to delete this expense of ${CurrencyFormatters.format(item.amount)}?',
                                    ),
                                    actions: [
                                      TextButton(
                                        onPressed: () =>
                                            Navigator.pop(ctx, false),
                                        child: const Text('Cancel'),
                                      ),
                                      ElevatedButton(
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: Colors.red,
                                          foregroundColor: Colors.white,
                                        ),
                                        onPressed: () =>
                                            Navigator.pop(ctx, true),
                                        child: const Text('Delete'),
                                      ),
                                    ],
                                  ),
                                );

                                if (confirm == true) {
                                  await ref
                                      .read(expenseNotifierProvider.notifier)
                                      .deleteExpense(item.uuid);
                                }
                              }
                            },
                            itemBuilder: (context) => [
                              const PopupMenuItem(
                                value: 'edit',
                                child: Row(
                                  children: [
                                    Icon(Icons.edit_outlined,
                                        size: 18, color: Colors.blue),
                                    SizedBox(width: 10),
                                    Text('Edit Expense'),
                                  ],
                                ),
                              ),
                              const PopupMenuItem(
                                value: 'delete',
                                child: Row(
                                  children: [
                                    Icon(Icons.delete_outline,
                                        size: 18, color: Colors.red),
                                    SizedBox(width: 10),
                                    Text('Delete Expense',
                                        style: TextStyle(color: Colors.red)),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Color _getClassificationColor(ExpenseClassification classification) {
    switch (classification) {
      case ExpenseClassification.urgent:
        return AppTheme.urgentColor;
      case ExpenseClassification.required:
        return AppTheme.requiredColor;
      case ExpenseClassification.optional:
        return AppTheme.optionalColor;
    }
  }
}
