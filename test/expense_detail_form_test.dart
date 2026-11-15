import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myexpence/features/categories/domain/models/category.dart';
import 'package:myexpence/features/expenses/presentation/screens/multi_item_detail_screen.dart';
import 'package:myexpence/features/people/presentation/providers/people_providers.dart';

void main() {
  Future<void> showCategory(WidgetTester tester, String categoryId,
      String categoryName, String subcategoryId, String subcategoryName) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final category = Category(
      id: categoryId,
      name: categoryName,
      icon: 'home',
      sortOrder: 1,
      subcategories: [
        Subcategory(
          id: subcategoryId,
          categoryId: categoryId,
          name: subcategoryName,
          sortOrder: 1,
        ),
      ],
    );
    await tester.pumpWidget(ProviderScope(
      overrides: [peopleListProvider.overrideWith((ref) async => [])],
      child: MaterialApp(
        home: MultiItemDetailScreen(
          category: category,
          initial: [
            MultiItemLine(
              name: subcategoryName,
              subcategoryId: subcategoryId,
              amount: 100,
            ),
          ],
        ),
      ),
    ));
    await tester.pump();
  }

  testWidgets('rent asks for amount and optional month without quantity',
      (tester) async {
    await showCategory(tester, 'cat_house', 'House', 'sub_house_rent', 'Rent');
    expect(find.text('Rent Amount'), findsOneWidget);
    expect(find.text('Rent month (optional)'), findsOneWidget);
    expect(find.text('Quantity'), findsNothing);
  });

  testWidgets('food retains optional quantity and unit price', (tester) async {
    await showCategory(
        tester, 'cat_food', 'Food', 'sub_food_roti', 'Roti & Naan');
    expect(find.text('Quantity'), findsOneWidget);
    expect(find.text('Unit Price'), findsOneWidget);
  });

  testWidgets('fuel accepts quantity and unit price', (tester) async {
    await showCategory(tester, 'cat_car', 'Car', 'sub_car_fuel', 'Fuel');
    expect(find.text('Quantity'), findsOneWidget);
    expect(find.text('Unit Price'), findsOneWidget);
  });

  testWidgets('electricity has bill amount and meter readings', (tester) async {
    await showCategory(
        tester, 'cat_utilities', 'Utilities', 'sub_util_elec', 'Electricity');
    expect(find.text('Bill Amount'), findsOneWidget);
    expect(find.text('Previous meter reading (optional)'), findsOneWidget);
    expect(find.text('Current meter reading (optional)'), findsOneWidget);
    expect(find.text('Quantity'), findsNothing);
  });

  testWidgets('maintenance uses a single amount', (tester) async {
    await showCategory(
        tester, 'cat_house', 'House', 'sub_house_maint', 'Maintenance');
    expect(find.text('Amount'), findsOneWidget);
    expect(find.text('Quantity'), findsNothing);
  });

  testWidgets('fuel quantity and unit price survive the item form',
      (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final category = Category(
      id: 'cat_car',
      name: 'Car',
      icon: 'directions_car',
      sortOrder: 1,
      subcategories: [
        Subcategory(
          id: 'sub_car_fuel',
          categoryId: 'cat_car',
          name: 'Fuel',
          sortOrder: 1,
        ),
      ],
    );
    MultiItemResult? result;
    await tester.pumpWidget(ProviderScope(
      overrides: [peopleListProvider.overrideWith((ref) async => [])],
      child: MaterialApp(
        home: Scaffold(
          body: Builder(builder: (context) {
            return TextButton(
              onPressed: () async {
                result = await showMultiItemDetailScreen(context,
                    category: category,
                    initial: const [
                      MultiItemLine(
                        name: 'Fuel',
                        subcategoryId: 'sub_car_fuel',
                        amount: 100,
                      ),
                    ]);
              },
              child: const Text('Open items'),
            );
          }),
        ),
      ),
    ));
    await tester.tap(find.text('Open items'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Quantity'), '2');
    await tester.pump();
    await tester.tap(find.text('Done').first);
    await tester.pumpAndSettle();
    expect(result, isNotNull);
    expect(result!.items.single.quantity, '2');
    expect(result!.items.single.unitPrice, 50);
    expect(result!.items.single.details['quantity'], '2');
    expect(result!.items.single.details['unitPrice'], 50);
  });
}
