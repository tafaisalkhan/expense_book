import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:myexpence/core/theme/app_theme.dart';
import 'package:myexpence/features/categories/domain/models/category.dart';
import 'package:myexpence/features/categories/presentation/providers/category_providers.dart';
import 'package:myexpence/features/expenses/domain/models/expense_classification.dart';
import 'package:uuid/uuid.dart';

class CategoryScreen extends ConsumerWidget {
  const CategoryScreen({super.key});

  void _showAddCategoryDialog(BuildContext context, WidgetRef ref) {
    final nameController = TextEditingController();
    ExpenseClassification selectedClassification = ExpenseClassification.required;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Add Custom Category'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: nameController,
                decoration: const InputDecoration(
                  labelText: 'Category Name *',
                  hintText: 'e.g. Investment, Subscriptions, Pets',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              const Text('Default Classification', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
              const SizedBox(height: 6),
              SegmentedButton<ExpenseClassification>(
                segments: const [
                  ButtonSegment(value: ExpenseClassification.required, label: Text('Required')),
                  ButtonSegment(value: ExpenseClassification.optional, label: Text('Optional')),
                ],
                selected: {selectedClassification},
                onSelectionChanged: (set) => setState(() => selectedClassification = set.first),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () async {
                final name = nameController.text.trim();
                if (name.isEmpty) return;

                final catId = 'cat_${name.toLowerCase().replaceAll(' ', '_')}';
                final newCat = Category(
                  id: catId,
                  uuid: const Uuid().v4(),
                  name: name,
                  icon: 'category',
                  defaultClassification: selectedClassification,
                  isSystem: false,
                  sortOrder: 99,
                );

                await ref.read(categoryNotifierProvider.notifier).addCategory(newCat);
                if (ctx.mounted) Navigator.pop(ctx);
              },
              child: const Text('Add Category'),
            ),
          ],
        ),
      ),
    );
  }

  void _showAddSubcategoryDialog(BuildContext context, WidgetRef ref, Category category) {
    final nameController = TextEditingController();
    ExpenseClassification selectedClassification = category.defaultClassification;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text('Add Subcategory to ${category.name}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: nameController,
                decoration: const InputDecoration(
                  labelText: 'Subcategory Name *',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              const Text('Default Classification', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
              const SizedBox(height: 6),
              SegmentedButton<ExpenseClassification>(
                segments: const [
                  ButtonSegment(value: ExpenseClassification.required, label: Text('Required')),
                  ButtonSegment(value: ExpenseClassification.optional, label: Text('Optional')),
                ],
                selected: {selectedClassification},
                onSelectionChanged: (set) => setState(() => selectedClassification = set.first),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () async {
                final name = nameController.text.trim();
                if (name.isEmpty) return;

                final subId = 'sub_${category.id}_${name.toLowerCase().replaceAll(' ', '_')}';
                final newSub = Subcategory(
                  id: subId,
                  uuid: const Uuid().v4(),
                  categoryId: category.id,
                  name: name,
                  defaultClassification: selectedClassification,
                  sortOrder: 99,
                );

                await ref.read(categoryNotifierProvider.notifier).addSubcategory(newSub);
                if (ctx.mounted) Navigator.pop(ctx);
              },
              child: const Text('Add Subcategory'),
            ),
          ],
        ),
      ),
    );
  }

  void _showEditCategoryDialog(BuildContext context, WidgetRef ref, Category category) {
    final nameController = TextEditingController(text: category.name);
    ExpenseClassification selectedClassification = category.defaultClassification;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text('Edit Category "${category.name}"'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: nameController,
                decoration: const InputDecoration(
                  labelText: 'Category Name *',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              const Text('Default Classification', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
              const SizedBox(height: 6),
              SegmentedButton<ExpenseClassification>(
                segments: const [
                  ButtonSegment(value: ExpenseClassification.required, label: Text('Required')),
                  ButtonSegment(value: ExpenseClassification.optional, label: Text('Optional')),
                ],
                selected: {selectedClassification},
                onSelectionChanged: (set) => setState(() => selectedClassification = set.first),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () async {
                final name = nameController.text.trim();
                if (name.isEmpty) return;

                final updatedCat = category.copyWith(
                  name: name,
                  defaultClassification: selectedClassification,
                );

                await ref.read(categoryNotifierProvider.notifier).updateCategory(updatedCat);
                if (ctx.mounted) Navigator.pop(ctx);
              },
              child: const Text('Save Changes'),
            ),
          ],
        ),
      ),
    );
  }

  void _showEditSubcategoryDialog(BuildContext context, WidgetRef ref, Subcategory sub) {
    final nameController = TextEditingController(text: sub.name);
    ExpenseClassification selectedClassification = sub.defaultClassification;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text('Edit Subcategory "${sub.name}"'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: nameController,
                decoration: const InputDecoration(
                  labelText: 'Subcategory Name *',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              const Text('Default Classification', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
              const SizedBox(height: 6),
              SegmentedButton<ExpenseClassification>(
                segments: const [
                  ButtonSegment(value: ExpenseClassification.required, label: Text('Required')),
                  ButtonSegment(value: ExpenseClassification.optional, label: Text('Optional')),
                ],
                selected: {selectedClassification},
                onSelectionChanged: (set) => setState(() => selectedClassification = set.first),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () async {
                final name = nameController.text.trim();
                if (name.isEmpty) return;

                final updatedSub = sub.copyWith(
                  name: name,
                  defaultClassification: selectedClassification,
                );

                await ref.read(categoryNotifierProvider.notifier).updateSubcategory(updatedSub);
                if (ctx.mounted) Navigator.pop(ctx);
              },
              child: const Text('Save Changes'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmDeleteSubcategory(BuildContext context, WidgetRef ref, Subcategory sub) async {
    final expenseCount = await ref.read(categoryNotifierProvider.notifier).getExpenseCountForSubcategory(sub.id);

    if (!context.mounted) return;

    if (expenseCount > 0) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('🚫 Cannot Delete Subcategory'),
          content: Text(
            'Subcategory "${sub.name}" cannot be deleted because $expenseCount expense(s) are logged under it in your records.',
          ),
          actions: [
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      return;
    }

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Subcategory?'),
        content: Text('Are you sure you want to delete "${sub.name}"?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            onPressed: () async {
              final deleted = await ref.read(categoryNotifierProvider.notifier).deleteSubcategory(sub.id);
              if (ctx.mounted) Navigator.pop(ctx);
              if (context.mounted) {
                if (deleted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Deleted subcategory "${sub.name}".')),
                  );
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('🚫 Cannot delete "${sub.name}": Expenses are logged under this subcategory.')),
                  );
                }
              }
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final categoriesAsync = ref.watch(categoriesListProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Categories & Subcategories'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: 'Add Category',
            onPressed: () => _showAddCategoryDialog(context, ref),
          ),
        ],
      ),
      body: categoriesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(child: Text('Error loading categories: $err')),
        data: (categories) {
          return ListView.builder(
            padding: const EdgeInsets.only(left: 16, right: 16, top: 16, bottom: 90),
            itemCount: categories.length,
            itemBuilder: (context, index) {
              final cat = categories[index];
              return Card(
                margin: const EdgeInsets.only(bottom: 12),
                child: ExpansionTile(
                  leading: CircleAvatar(
                    backgroundColor: AppTheme.primaryColor.withValues(alpha: 0.12),
                    child: Icon(
                      _getIconData(cat.icon),
                      color: AppTheme.primaryColor,
                    ),
                  ),
                  title: Row(
                    children: [
                      Expanded(
                        child: Text(cat.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                      ),
                      IconButton(
                        icon: const Icon(Icons.edit_outlined, size: 18, color: Colors.blueGrey),
                        tooltip: 'Edit Category',
                        onPressed: () => _showEditCategoryDialog(context, ref, cat),
                      ),
                    ],
                  ),
                  subtitle: Text(
                    'Default: ${cat.defaultClassification.label} • ${cat.subcategories.length} subcategories',
                    style: const TextStyle(fontSize: 12),
                  ),
                  children: [
                    ...cat.subcategories.map((sub) {
                      return ListTile(
                        contentPadding: const EdgeInsets.only(left: 72, right: 16),
                        title: Text(sub.name, style: const TextStyle(fontSize: 14)),
                        subtitle: Text(
                          sub.defaultClassification.label,
                          style: const TextStyle(fontSize: 11, color: Colors.grey),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.edit_outlined, size: 18, color: Colors.blueGrey),
                              tooltip: 'Edit Subcategory',
                              onPressed: () => _showEditSubcategoryDialog(context, ref, sub),
                            ),
                            IconButton(
                              icon: Icon(Icons.delete_outline, size: 18, color: Colors.red.shade400),
                              tooltip: 'Delete Subcategory',
                              onPressed: () => _confirmDeleteSubcategory(context, ref, sub),
                            ),
                          ],
                        ),
                      );
                    }),
                    Padding(
                      padding: const EdgeInsets.only(left: 72, right: 16, bottom: 8),
                      child: TextButton.icon(
                        icon: const Icon(Icons.add, size: 18),
                        label: const Text('Add Subcategory', style: TextStyle(fontSize: 13)),
                        onPressed: () => _showAddSubcategoryDialog(context, ref, cat),
                      ),
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

  IconData _getIconData(String iconName) {
    switch (iconName) {
      case 'directions_car':
        return Icons.directions_car;
      case 'school':
        return Icons.school;
      case 'home':
        return Icons.home;
      case 'bolt':
        return Icons.bolt;
      case 'shopping_cart':
        return Icons.shopping_cart;
      case 'restaurant':
        return Icons.restaurant;
      case 'medical_services':
        return Icons.medical_services;
      case 'commute':
        return Icons.commute;
      case 'shopping_bag':
        return Icons.shopping_bag;
      case 'movie':
        return Icons.movie;
      case 'person':
        return Icons.person;
      case 'volunteer_activism':
        return Icons.volunteer_activism;
      case 'flight':
        return Icons.flight;
      default:
        return Icons.category;
    }
  }
}
