import 'package:myexpence/features/expenses/domain/models/expense_classification.dart';

class Subcategory {
  final String id;
  final String? uuid;
  final String categoryId;
  final String name;
  final ExpenseClassification defaultClassification;
  final bool isActive;
  final int sortOrder;

  const Subcategory({
    required this.id,
    this.uuid,
    required this.categoryId,
    required this.name,
    this.defaultClassification = ExpenseClassification.required,
    this.isActive = true,
    required this.sortOrder,
  });

  Subcategory copyWith({
    String? id,
    String? uuid,
    String? categoryId,
    String? name,
    ExpenseClassification? defaultClassification,
    bool? isActive,
    int? sortOrder,
  }) {
    return Subcategory(
      id: id ?? this.id,
      uuid: uuid ?? this.uuid,
      categoryId: categoryId ?? this.categoryId,
      name: name ?? this.name,
      defaultClassification: defaultClassification ?? this.defaultClassification,
      isActive: isActive ?? this.isActive,
      sortOrder: sortOrder ?? this.sortOrder,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'uuid': uuid ?? id,
      'categoryId': categoryId,
      'name': name,
      'defaultClassification': defaultClassification.code,
      'isActive': isActive ? 1 : 0,
      'sortOrder': sortOrder,
    };
  }

  factory Subcategory.fromMap(Map<String, dynamic> map) {
    return Subcategory(
      id: map['id'] as String,
      uuid: map['uuid'] as String?,
      categoryId: map['categoryId'] as String,
      name: map['name'] as String,
      defaultClassification: ExpenseClassification.fromCode(map['defaultClassification'] as String),
      isActive: (map['isActive'] as int) == 1,
      sortOrder: map['sortOrder'] as int,
    );
  }
}

class Category {
  final String id;
  final String? uuid;
  final String name;
  final String icon;
  final ExpenseClassification defaultClassification;
  final bool isSystem;
  final bool isActive;
  final int sortOrder;
  final List<Subcategory> subcategories;

  const Category({
    required this.id,
    this.uuid,
    required this.name,
    required this.icon,
    this.defaultClassification = ExpenseClassification.required,
    this.isSystem = true,
    this.isActive = true,
    required this.sortOrder,
    this.subcategories = const [],
  });

  Category copyWith({
    String? id,
    String? uuid,
    String? name,
    String? icon,
    ExpenseClassification? defaultClassification,
    bool? isSystem,
    bool? isActive,
    int? sortOrder,
    List<Subcategory>? subcategories,
  }) {
    return Category(
      id: id ?? this.id,
      uuid: uuid ?? this.uuid,
      name: name ?? this.name,
      icon: icon ?? this.icon,
      defaultClassification: defaultClassification ?? this.defaultClassification,
      isSystem: isSystem ?? this.isSystem,
      isActive: isActive ?? this.isActive,
      sortOrder: sortOrder ?? this.sortOrder,
      subcategories: subcategories ?? this.subcategories,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'uuid': uuid ?? id,
      'name': name,
      'icon': icon,
      'defaultClassification': defaultClassification.code,
      'isSystem': isSystem ? 1 : 0,
      'isActive': isActive ? 1 : 0,
      'sortOrder': sortOrder,
    };
  }

  factory Category.fromMap(Map<String, dynamic> map, {List<Subcategory> subcategories = const []}) {
    return Category(
      id: map['id'] as String,
      uuid: map['uuid'] as String?,
      name: map['name'] as String,
      icon: map['icon'] as String,
      defaultClassification: ExpenseClassification.fromCode(map['defaultClassification'] as String),
      isSystem: (map['isSystem'] as int) == 1,
      isActive: (map['isActive'] as int) == 1,
      sortOrder: map['sortOrder'] as int,
      subcategories: subcategories,
    );
  }
}
