import 'package:flutter/material.dart';
import 'package:myexpence/features/categories/domain/models/category.dart';
import 'package:myexpence/features/expenses/presentation/screens/multi_item_detail_screen.dart';

export 'package:myexpence/features/expenses/presentation/screens/multi_item_detail_screen.dart'
    show
        MultiItemLine,
        MultiItemResult,
        MultiItemDetailScreen,
        showMultiItemDetailScreen,
        isGroceryOnlyCategory,
        isFoodCategory,
        isMultiItemCategory,
        isGroceryCategory;

/// Shows the dedicated screen where the user selects sub-items of [category]
/// with 3-way auto calculation (Quantity × Unit Price = Total) and persistent
/// target tracking.
Future<MultiItemResult?> showMultiItemPickerSheet(
  BuildContext context, {
  required Category category,
  List<MultiItemLine> initial = const [],
  double? targetTotal,
}) {
  return showMultiItemDetailScreen(
    context,
    category: category,
    initial: initial,
    targetTotal: targetTotal,
  );
}
