import 'package:flutter_test/flutter_test.dart';
import 'package:myexpence/features/categories/domain/models/category.dart';
import 'package:myexpence/features/document_scanner/domain/services/ocr_scanner_service.dart';
import 'package:myexpence/features/expenses/domain/models/expense_classification.dart';

void main() {
  const sampleCatalog = [
    Category(
      id: 'cat_groceries',
      name: 'Groceries',
      icon: 'shopping_cart',
      defaultClassification: ExpenseClassification.required,
      sortOrder: 5,
      subcategories: [
        Subcategory(id: 'sub_groc_milk', categoryId: 'cat_groceries', name: 'Milk', sortOrder: 1),
        Subcategory(id: 'sub_groc_oil', categoryId: 'cat_groceries', name: 'Cooking Oil', sortOrder: 2),
        Subcategory(id: 'sub_groc_veg', categoryId: 'cat_groceries', name: 'Vegetables', sortOrder: 3),
        Subcategory(id: 'sub_groc_other', categoryId: 'cat_groceries', name: 'Other', sortOrder: 4),
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
    Category(
      id: 'cat_stationery',
      name: 'Stationery',
      icon: 'edit_note',
      defaultClassification: ExpenseClassification.required,
      sortOrder: 7,
      subcategories: [
        Subcategory(id: 'sub_stat_copies', categoryId: 'cat_stationery', name: 'Copies & Notebooks', sortOrder: 1),
      ],
    ),
  ];

  test('rejects empty or too-short text as no_text', () {
    expect(
      () => OcrScannerService.parseReceiptText('hi'),
      throwsA(
        isA<UnreadableReceiptException>()
            .having((e) => e.reasonCode, 'reasonCode', 'no_text'),
      ),
    );
  });

  test('rejects blurry symbol-heavy OCR output as blurry_text', () {
    expect(
      () => OcrScannerService.parseReceiptText(
        '@@@ ### !!! ??? ~~~\n*** +++ ^^^ %%% 1\n=== ::: ;;; ---',
      ),
      throwsA(
        isA<UnreadableReceiptException>()
            .having((e) => e.reasonCode, 'reasonCode', 'blurry_text'),
      ),
    );
  });

  test('rejects receipt with text but no readable amounts as no_amounts', () {
    expect(
      () => OcrScannerService.parseReceiptText(
        'METRO SUPERMARKET LAHORE\nFresh Milk Pack\nCooking Oil Bottle\nThank you for visiting',
      ),
      throwsA(
        isA<UnreadableReceiptException>()
            .having((e) => e.reasonCode, 'reasonCode', 'no_amounts'),
      ),
    );
  });

  test('rejects partially cut-off receipt when total amount is missing', () {
    expect(
      () => OcrScannerService.parseReceiptText(
        'AL-FATAH STORE\nCustomer Copy\nGRAND TOTAL:\nThank you',
      ),
      throwsA(
        isA<UnreadableReceiptException>()
            .having((e) => e.reasonCode, 'reasonCode', 'partial_cut_off'),
      ),
    );

    expect(
      () => OcrScannerService.parseReceiptText(
        'AL-FATAH STORE\nFresh Milk Pack Rs\nOlive Oil 1L @\nEggs Dozen x2\nBread Loaf   150\nTOTAL: 2500.00',
      ),
      throwsA(
        isA<UnreadableReceiptException>()
            .having((e) => e.reasonCode, 'reasonCode', 'partial_cut_off'),
      ),
    );
  });

  test('parses decimal and whole-number items and auto-matches real categories & subcategories', () {
    const raw = '''
AL-FATAH SUPERMARKET
Date: 2026-11-23  Time: 15:10
Milk Pack 1L          Rs 320
Panadol Extra         180.00
Super Petrol          3500/-
Electricity Bill LESCO 4200
Spiral Notebook       250
TOTAL: 8450.00
''';
    final result = OcrScannerService.parseReceiptText(
      raw,
      availableCategories: sampleCatalog,
    );

    expect(result.merchant, 'AL-FATAH SUPERMARKET');
    expect(result.totalAmount, 8450.0);
    expect(result.lineItems.length, 5);

    expect(result.lineItems[0].name, 'Milk Pack 1L');
    expect(result.lineItems[0].categoryId, 'cat_groceries');
    expect(result.lineItems[0].subcategoryId, 'sub_groc_milk');

    expect(result.lineItems[1].name, 'Panadol Extra');
    expect(result.lineItems[1].categoryId, 'cat_health');
    expect(result.lineItems[1].subcategoryId, 'sub_hlth_med');

    expect(result.lineItems[2].name, 'Super Petrol');
    expect(result.lineItems[2].categoryId, 'cat_car');
    expect(result.lineItems[2].subcategoryId, 'sub_car_fuel');

    expect(result.lineItems[3].name, 'Electricity Bill LESCO');
    expect(result.lineItems[3].categoryId, 'cat_utilities');
    expect(result.lineItems[3].subcategoryId, 'sub_util_elec');

    expect(result.lineItems[4].name, 'Spiral Notebook');
    expect(result.lineItems[4].categoryId, 'cat_stationery');
    expect(result.lineItems[4].subcategoryId, 'sub_stat_copies');
  });

  test('normalizes quantity line totals so amount * quantity matches printed total', () {
    const raw = '''
METRO CASH & CARRY
Milk Pack 1L x2       450.00
Cooking Oil 5L x1    2200.00
Fresh Vegetables      850.00
TOTAL: 3500.00
''';
    final result = OcrScannerService.parseReceiptText(
      raw,
      availableCategories: sampleCatalog,
    );

    expect(result.totalAmount, 3500.0);
    final sum = result.lineItems.fold(0.0, (s, i) => s + (i.amount * i.quantity));
    expect(sum, closeTo(3500.0, 0.01));
    expect(result.lineItems.first.quantity, 2.0);
    expect(result.lineItems.first.amount, closeTo(225.0, 0.01));
  });
}
