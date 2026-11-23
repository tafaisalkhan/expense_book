import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:myexpence/features/backup/feature_quota_service.dart';
import 'package:myexpence/features/categories/domain/models/category.dart';
import 'package:myexpence/features/document_scanner/domain/services/voice_expense_parser.dart';
import 'package:myexpence/features/expenses/domain/models/expense_classification.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const sampleCatalog = [
    Category(
      id: 'cat_groceries',
      name: 'Groceries',
      icon: 'shopping_cart',
      defaultClassification: ExpenseClassification.required,
      sortOrder: 5,
      subcategories: [
        Subcategory(id: 'sub_groc_milk', categoryId: 'cat_groceries', name: 'Milk', sortOrder: 1),
        Subcategory(id: 'sub_groc_chicken', categoryId: 'cat_groceries', name: 'Chicken', sortOrder: 2),
        Subcategory(id: 'sub_groc_bread', categoryId: 'cat_groceries', name: 'Bread', sortOrder: 3),
      ],
    ),
    Category(
      id: 'cat_health',
      name: 'Health',
      icon: 'medical_services',
      defaultClassification: ExpenseClassification.required,
      sortOrder: 9,
      subcategories: [
        Subcategory(id: 'sub_hlth_med', categoryId: 'cat_health', name: 'Medicine', sortOrder: 1),
      ],
    ),
    Category(
      id: 'cat_car',
      name: 'Car',
      icon: 'directions_car',
      defaultClassification: ExpenseClassification.required,
      sortOrder: 1,
      subcategories: [
        Subcategory(id: 'sub_car_fuel', categoryId: 'cat_car', name: 'Fuel', sortOrder: 1),
      ],
    ),
    Category(
      id: 'cat_utilities',
      name: 'Utilities',
      icon: 'bolt',
      defaultClassification: ExpenseClassification.required,
      sortOrder: 4,
      subcategories: [
        Subcategory(id: 'sub_util_elec', categoryId: 'cat_utilities', name: 'Electricity', sortOrder: 1),
      ],
    ),
  ];

  test('parses multi-item spoken phrases into exact categories & subcategories', () {
    final items = VoiceExpenseParser.parse(
      'Milk 320, Panadol 180 and Petrol 3500',
      availableCategories: sampleCatalog,
    );
    expect(items.length, 3);
    expect(items[0].name, 'Milk');
    expect(items[0].amount, 320.0);
    expect(items[0].categoryId, 'cat_groceries');
    expect(items[0].subcategoryId, 'sub_groc_milk');

    expect(items[1].name, 'Panadol');
    expect(items[1].amount, 180.0);
    expect(items[1].categoryId, 'cat_health');
    expect(items[1].subcategoryId, 'sub_hlth_med');

    expect(items[2].name, 'Petrol');
    expect(items[2].amount, 3500.0);
    expect(items[2].categoryId, 'cat_car');
    expect(items[2].subcategoryId, 'sub_car_fuel');
  });

  test('parses natural sentences and spoken number words offline', () {
    final items = VoiceExpenseParser.parse(
      'Spent five hundred on chicken and two hundred fifty on bread',
      availableCategories: sampleCatalog,
    );
    expect(items.length, 2);
    expect(items[0].name, 'Chicken');
    expect(items[0].amount, 500.0);
    expect(items[0].subcategoryId, 'sub_groc_chicken');

    expect(items[1].name, 'Bread');
    expect(items[1].amount, 250.0);
    expect(items[1].subcategoryId, 'sub_groc_bread');
  });

  test('rejects spoken phrases with no valid amount or item', () {
    expect(
      () => VoiceExpenseParser.parse('hello testing mic'),
      throwsA(isA<UnreadableVoiceException>()),
    );
  });

  test('FeatureQuotaService enforces free (1 OCR, 1x10s voice) vs subscribed (unlimited OCR, 10x10s voice)', () async {
    SharedPreferences.setMockInitialValues({});
    final day = DateTime(2026, 11, 23);

    expect(FeatureQuotaService.maxVoiceSeconds, 10);

    // Free user: 1 OCR image/day
    expect(await FeatureQuotaService.canUseOcr(isSubscribed: false, now: day), true);
    expect(await FeatureQuotaService.remainingOcrToday(isSubscribed: false, now: day), 1);
    await FeatureQuotaService.recordOcrUsage(now: day);
    expect(await FeatureQuotaService.canUseOcr(isSubscribed: false, now: day), false);
    expect(await FeatureQuotaService.remainingOcrToday(isSubscribed: false, now: day), 0);

    // Subscribed user: unlimited OCR images
    expect(await FeatureQuotaService.canUseOcr(isSubscribed: true, now: day), true);
    expect(await FeatureQuotaService.remainingOcrToday(isSubscribed: true, now: day), isNull);

    // Free user: 1 voice/day
    expect(await FeatureQuotaService.canUseVoice(isSubscribed: false, now: day), true);
    await FeatureQuotaService.recordVoiceUsage(now: day);
    expect(await FeatureQuotaService.canUseVoice(isSubscribed: false, now: day), false);

    // Subscribed user: 10 voice/day (1 already used above -> 9 more allowed, then blocked)
    expect(await FeatureQuotaService.remainingVoiceToday(isSubscribed: true, now: day), 9);
    for (int i = 0; i < 9; i++) {
      expect(await FeatureQuotaService.canUseVoice(isSubscribed: true, now: day), true);
      await FeatureQuotaService.recordVoiceUsage(now: day);
    }
    expect(await FeatureQuotaService.remainingVoiceToday(isSubscribed: true, now: day), 0);
    expect(await FeatureQuotaService.canUseVoice(isSubscribed: true, now: day), false);
  });
}
