import 'package:myexpence/core/database/app_database.dart';
import 'package:myexpence/features/categories/domain/models/category.dart';
import 'package:myexpence/features/categories/domain/repositories/category_repository.dart';

class SqliteCategoryRepository implements ICategoryRepository {
  final AppDatabase appDatabase;

  SqliteCategoryRepository(this.appDatabase);

  @override
  Future<List<Category>> getCategories({bool activeOnly = true}) async {
    final db = await appDatabase.database;
    final catMaps = await db.query(
      'categories',
      where: activeOnly ? 'isActive = 1' : null,
      orderBy: 'sortOrder ASC',
    );

    final List<Category> categories = [];
    for (final map in catMaps) {
      final catId = map['id'] as String;
      final subMaps = await db.query(
        'subcategories',
        where: activeOnly ? 'categoryId = ? AND isActive = 1' : 'categoryId = ?',
        whereArgs: [catId],
        orderBy: 'sortOrder ASC',
      );

      final subs = subMaps.map((s) => Subcategory.fromMap(s)).toList();
      categories.add(Category.fromMap(map, subcategories: subs));
    }
    return categories;
  }

  @override
  Future<Category?> getCategoryById(String id) async {
    final db = await appDatabase.database;
    final maps = await db.query(
      'categories',
      where: 'id = ?',
      whereArgs: [id],
    );
    if (maps.isEmpty) return null;

    final subMaps = await db.query(
      'subcategories',
      where: 'categoryId = ? AND isActive = 1',
      whereArgs: [id],
      orderBy: 'sortOrder ASC',
    );
    final subs = subMaps.map((s) => Subcategory.fromMap(s)).toList();
    return Category.fromMap(maps.first, subcategories: subs);
  }

  @override
  Future<List<Subcategory>> getSubcategories(String categoryId, {bool activeOnly = true}) async {
    final db = await appDatabase.database;
    final subMaps = await db.query(
      'subcategories',
      where: activeOnly ? 'categoryId = ? AND isActive = 1' : 'categoryId = ?',
      whereArgs: [categoryId],
      orderBy: 'sortOrder ASC',
    );
    return subMaps.map((s) => Subcategory.fromMap(s)).toList();
  }

  @override
  Future<void> addCategory(Category category) async {
    final db = await appDatabase.database;
    await db.insert('categories', category.toMap());
  }

  @override
  Future<void> updateCategory(Category category) async {
    final db = await appDatabase.database;
    await db.update(
      'categories',
      category.toMap(),
      where: 'id = ? OR uuid = ?',
      whereArgs: [category.id, category.uuid ?? category.id],
    );
  }

  @override
  Future<void> addSubcategory(Subcategory subcategory) async {
    final db = await appDatabase.database;
    await db.insert('subcategories', subcategory.toMap());
  }

  @override
  Future<void> updateSubcategory(Subcategory subcategory) async {
    final db = await appDatabase.database;
    await db.update(
      'subcategories',
      subcategory.toMap(),
      where: 'id = ? OR uuid = ?',
      whereArgs: [subcategory.id, subcategory.uuid ?? subcategory.id],
    );
  }

  @override
  Future<int> getExpenseCountForSubcategory(String subcategoryId) async {
    final db = await appDatabase.database;
    final res = await db.rawQuery(
      'SELECT COUNT(*) as count FROM expenses WHERE (subcategoryId = ? OR subcategoryId = (SELECT id FROM subcategories WHERE uuid = ?)) AND isDeleted = 0',
      [subcategoryId, subcategoryId],
    );
    if (res.isEmpty) return 0;
    return (res.first['count'] as num?)?.toInt() ?? 0;
  }

  @override
  Future<bool> deleteSubcategory(String subcategoryId) async {
    final db = await appDatabase.database;
    final count = await getExpenseCountForSubcategory(subcategoryId);
    if (count > 0) {
      return false; // Has expenses linked, deletion blocked!
    }
    await db.delete(
      'subcategories',
      where: 'id = ? OR uuid = ?',
      whereArgs: [subcategoryId, subcategoryId],
    );
    return true;
  }
}
