import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:myexpence/core/providers/core_providers.dart';
import 'package:myexpence/features/categories/domain/models/category.dart';

final categoriesListProvider = FutureProvider<List<Category>>((ref) async {
  final repo = ref.watch(categoryRepositoryProvider);
  return await repo.getCategories(activeOnly: true);
});

class CategoryNotifier extends StateNotifier<AsyncValue<void>> {
  final Ref ref;

  CategoryNotifier(this.ref) : super(const AsyncValue.data(null));

  Future<void> addCategory(Category category) async {
    state = const AsyncValue.loading();
    try {
      final repo = ref.read(categoryRepositoryProvider);
      await repo.addCategory(category);
      ref.invalidate(categoriesListProvider);
      state = const AsyncValue.data(null);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  Future<void> updateCategory(Category category) async {
    state = const AsyncValue.loading();
    try {
      final repo = ref.read(categoryRepositoryProvider);
      await repo.updateCategory(category);
      ref.invalidate(categoriesListProvider);
      state = const AsyncValue.data(null);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  Future<void> addSubcategory(Subcategory subcategory) async {
    state = const AsyncValue.loading();
    try {
      final repo = ref.read(categoryRepositoryProvider);
      await repo.addSubcategory(subcategory);
      ref.invalidate(categoriesListProvider);
      state = const AsyncValue.data(null);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  Future<void> updateSubcategory(Subcategory subcategory) async {
    state = const AsyncValue.loading();
    try {
      final repo = ref.read(categoryRepositoryProvider);
      await repo.updateSubcategory(subcategory);
      ref.invalidate(categoriesListProvider);
      state = const AsyncValue.data(null);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  Future<int> getExpenseCountForSubcategory(String subcategoryId) async {
    final repo = ref.read(categoryRepositoryProvider);
    return await repo.getExpenseCountForSubcategory(subcategoryId);
  }

  Future<bool> deleteSubcategory(String subcategoryId) async {
    state = const AsyncValue.loading();
    try {
      final repo = ref.read(categoryRepositoryProvider);
      final deleted = await repo.deleteSubcategory(subcategoryId);
      ref.invalidate(categoriesListProvider);
      state = const AsyncValue.data(null);
      return deleted;
    } catch (e, st) {
      state = AsyncValue.error(e, st);
      return false;
    }
  }
}

final categoryNotifierProvider = StateNotifierProvider<CategoryNotifier, AsyncValue<void>>((ref) {
  return CategoryNotifier(ref);
});
