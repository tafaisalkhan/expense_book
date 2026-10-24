import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:myexpence/core/theme/app_theme.dart';
import 'package:myexpence/features/ads/presentation/providers/ad_providers.dart';
import 'package:myexpence/core/utils/currency_formatters.dart';
import 'package:myexpence/core/utils/date_formatters.dart';
import 'package:myexpence/core/utils/category_icon_helper.dart';
import 'package:myexpence/features/categories/presentation/providers/category_providers.dart';
import 'package:myexpence/features/expenses/domain/models/expense_classification.dart';
import 'package:myexpence/features/expenses/presentation/providers/expense_providers.dart';
import 'package:myexpence/features/expenses/presentation/widgets/voice_note_player_bottom_sheet.dart';
import 'package:myexpence/features/settings/presentation/providers/settings_providers.dart';

class ExpenseListScreen extends ConsumerStatefulWidget {
  final String? initialDate;

  const ExpenseListScreen({super.key, this.initialDate});

  @override
  ConsumerState<ExpenseListScreen> createState() => _ExpenseListScreenState();
}

class _ExpenseListScreenState extends ConsumerState<ExpenseListScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  ExpenseClassification? _selectedClassification;
  String? _selectedDate;
  String? _selectedCategoryId;

  @override
  void initState() {
    super.initState();
    _selectedDate = widget.initialDate;
  }

  @override
  void didUpdateWidget(covariant ExpenseListScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialDate != oldWidget.initialDate) {
      setState(() {
        _selectedDate = widget.initialDate;
      });
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _pickDate(BuildContext context) async {
    final initial = _selectedDate != null
        ? DateFormatters.parseDateIso(_selectedDate!)
        : DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) {
      setState(() {
        _selectedDate = DateFormatters.formatDateIso(picked);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(currencyNotifierProvider);
    final allExpensesAsync = ref.watch(allExpensesProvider);
    final categoriesList = ref.watch(categoriesListProvider).valueOrNull ?? [];
    final categoryMap = {for (var c in categoriesList) c.id: c};

    return Scaffold(
      appBar: AppBar(
        title: Text(_selectedDate != null
            ? 'Expenses (${DateFormatters.formatDateShort(DateFormatters.parseDateIso(_selectedDate!))})'
            : 'Expense History'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () {
              ref.read(adNotifierProvider.notifier).recordNavigation(context);
              context.push('/add');
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // Search & Filter Bar
          Padding(
            padding: const EdgeInsets.fromLTRB(12.0, 12.0, 12.0, 6.0),
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

                // Date & Category Filters Row
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      // Date Filter Chip
                      if (_selectedDate != null)
                        Padding(
                          padding: const EdgeInsets.only(right: 6.0),
                          child: InputChip(
                            avatar: const Icon(Icons.calendar_today,
                                size: 14, color: Colors.white),
                            label: Text(
                              'Day: ${DateFormatters.formatDateDisplay(DateFormatters.parseDateIso(_selectedDate!))}',
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                  fontSize: 12),
                            ),
                            backgroundColor: AppTheme.primaryColor,
                            deleteIconColor: Colors.white,
                            onDeleted: () =>
                                setState(() => _selectedDate = null),
                            onPressed: () => _pickDate(context),
                          ),
                        )
                      else
                        Padding(
                          padding: const EdgeInsets.only(right: 6.0),
                          child: ActionChip(
                            avatar: const Icon(Icons.calendar_month, size: 16),
                            label: const Text('Filter Day',
                                style: TextStyle(fontSize: 12)),
                            onPressed: () => _pickDate(context),
                          ),
                        ),

                      // Category Filter Dropdown/Chip
                      if (categoriesList.isNotEmpty) ...[
                        FilterChip(
                          label: Text(_selectedCategoryId == null
                              ? 'Category: All'
                              : 'Category: ${categoryMap[_selectedCategoryId]?.name ?? _selectedCategoryId}'),
                          selected: _selectedCategoryId != null,
                          onSelected: (_) async {
                            final selected =
                                await showModalBottomSheet<String?>(
                              context: context,
                              builder: (ctx) => SafeArea(
                                child: ListView(
                                  shrinkWrap: true,
                                  children: [
                                    ListTile(
                                      title: const Text('All Categories',
                                          style: TextStyle(
                                              fontWeight: FontWeight.bold)),
                                      selected: _selectedCategoryId == null,
                                      trailing: _selectedCategoryId == null
                                          ? const Icon(Icons.check,
                                              color: AppTheme.primaryColor)
                                          : null,
                                      onTap: () => Navigator.pop(ctx, ''),
                                    ),
                                    const Divider(),
                                    ...categoriesList.map((c) => ListTile(
                                          leading:
                                              CategoryIconHelper.buildCategoryAvatar(
                                            iconName: c.icon,
                                            categoryId: c.id,
                                            size: 20,
                                          ),
                                          title: Text(c.name),
                                          selected:
                                              _selectedCategoryId == c.id,
                                          trailing: _selectedCategoryId == c.id
                                              ? const Icon(Icons.check,
                                                  color: AppTheme.primaryColor)
                                              : null,
                                          onTap: () =>
                                              Navigator.pop(ctx, c.id),
                                        )),
                                  ],
                                ),
                              ),
                            );
                            if (selected != null) {
                              setState(() {
                                _selectedCategoryId =
                                    selected.isEmpty ? null : selected;
                              });
                            }
                          },
                        ),
                        const SizedBox(width: 6),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 6),

                // Expense Type (Classification) Filter Chips
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      FilterChip(
                        label: const Text('All Types'),
                        selected: _selectedClassification == null,
                        onSelected: (_) =>
                            setState(() => _selectedClassification = null),
                      ),
                      const SizedBox(width: 6),
                      FilterChip(
                        label: const Text('Urgent'),
                        selected: _selectedClassification ==
                            ExpenseClassification.urgent,
                        onSelected: (_) => setState(() =>
                            _selectedClassification =
                                ExpenseClassification.urgent),
                      ),
                      const SizedBox(width: 6),
                      FilterChip(
                        label: const Text('Required'),
                        selected: _selectedClassification ==
                            ExpenseClassification.required,
                        onSelected: (_) => setState(() =>
                            _selectedClassification =
                                ExpenseClassification.required),
                      ),
                      const SizedBox(width: 6),
                      FilterChip(
                        label: const Text('Optional'),
                        selected: _selectedClassification ==
                            ExpenseClassification.optional,
                        onSelected: (_) => setState(() =>
                            _selectedClassification =
                                ExpenseClassification.optional),
                      ),
                      const SizedBox(width: 6),
                      FilterChip(
                        label: const Text('Lost'),
                        selected: _selectedClassification ==
                            ExpenseClassification.lost,
                        onSelected: (_) => setState(() =>
                            _selectedClassification =
                                ExpenseClassification.lost),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Summary Info Bar
          allExpensesAsync.maybeWhen(
            data: (expenses) {
              var count = expenses;
              if (_selectedDate != null) {
                count = count
                    .where((e) => e.expenseDate == _selectedDate)
                    .toList();
              }
              if (_selectedClassification != null) {
                count = count
                    .where((e) => e.classification == _selectedClassification)
                    .toList();
              }
              if (_selectedCategoryId != null) {
                count = count
                    .where((e) => e.categoryId == _selectedCategoryId)
                    .toList();
              }
              if (_searchQuery.isNotEmpty) {
                count = count.where((e) {
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
              final totalSpent =
                  count.fold<double>(0.0, (sum, e) => sum + e.amount);

              return Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                color: Theme.of(context)
                    .colorScheme
                    .surfaceContainerHighest
                    .withValues(alpha: 0.35),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '${count.length} expense${count.length == 1 ? '' : 's'} found',
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Colors.grey[700]),
                    ),
                    Text(
                      'Total: ${CurrencyFormatters.format(totalSpent)}',
                      style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.primaryColor),
                    ),
                  ],
                ),
              );
            },
            orElse: () => const SizedBox.shrink(),
          ),

          // List View
          Expanded(
            child: allExpensesAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (err, _) =>
                  Center(child: Text('Error loading expenses: $err')),
              data: (expenses) {
                var filtered = expenses;

                if (_selectedDate != null) {
                  filtered = filtered
                      .where((e) => e.expenseDate == _selectedDate)
                      .toList();
                }

                if (_selectedClassification != null) {
                  filtered = filtered
                      .where((e) => e.classification == _selectedClassification)
                      .toList();
                }

                if (_selectedCategoryId != null) {
                  filtered = filtered
                      .where((e) => e.categoryId == _selectedCategoryId)
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
                  if (_selectedDate != null) {
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.event_busy,
                              size: 44, color: Colors.grey[400]),
                          const SizedBox(height: 10),
                          Text(
                            'No expenses found on ${DateFormatters.formatDateDisplay(DateFormatters.parseDateIso(_selectedDate!))}.',
                            style: const TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 14),
                          ),
                          const SizedBox(height: 10),
                          OutlinedButton.icon(
                            onPressed: () =>
                                setState(() => _selectedDate = null),
                            icon: const Icon(Icons.clear, size: 16),
                            label: const Text('Show All Dates'),
                          ),
                        ],
                      ),
                    );
                  }
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
                      onTap: () {
                        ref.read(adNotifierProvider.notifier).recordNavigation(context);
                        context.push('/add', extra: item);
                      },
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
                      subtitle: Row(
                        children: [
                          Expanded(
                            child: Text(
                              '${item.merchant?.isNotEmpty == true ? '$fullCategoryDisplay • ' : ''}${DateFormatters.formatDateDisplay(DateFormatters.parseDateIso(item.expenseDate))} • ${item.paymentMethod.label}',
                              style: TextStyle(fontSize: 12, color: Colors.grey[700]),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (item.hasVoiceNote) ...[
                            const SizedBox(width: 4),
                            const Icon(Icons.mic, size: 14, color: AppTheme.primaryColor),
                          ],
                        ],
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (item.hasVoiceNote)
                            IconButton(
                              icon: const Icon(Icons.volume_up_outlined,
                                  size: 20, color: AppTheme.primaryColor),
                              tooltip: 'Listen to Voice Note',
                              onPressed: () =>
                                  showVoiceNoteBottomSheet(context, ref, item),
                            ),
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
                              if (action == 'voice') {
                                showVoiceNoteBottomSheet(context, ref, item);
                              } else if (action == 'edit') {
                                ref.read(adNotifierProvider.notifier).recordNavigation(context);
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
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text('Expense deleted successfully'),
                                        backgroundColor: Colors.red,
                                        duration: Duration(seconds: 2),
                                      ),
                                    );
                                  }
                                }
                              }
                            },
                            itemBuilder: (context) => [
                              if (item.hasVoiceNote)
                                const PopupMenuItem(
                                  value: 'voice',
                                  child: Row(
                                    children: [
                                      Icon(Icons.volume_up,
                                          size: 18, color: AppTheme.primaryColor),
                                      SizedBox(width: 10),
                                      Text('Play Voice Note'),
                                    ],
                                  ),
                                ),
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
      case ExpenseClassification.lost:
        return AppTheme.lostColor;
    }
  }
}
