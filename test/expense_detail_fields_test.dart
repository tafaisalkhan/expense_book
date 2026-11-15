import 'package:flutter_test/flutter_test.dart';
import 'package:myexpence/features/expenses/domain/models/expense_detail_fields.dart';

void main() {
  test('all built-in categories have an appropriate optional field layout', () {
    const categories = [
      'cat_car',
      'cat_education',
      'cat_house',
      'cat_utilities',
      'cat_groceries',
      'cat_food',
      'cat_stationery',
      'cat_clothing',
      'cat_health',
      'cat_transport',
      'cat_shopping',
      'cat_entertainment',
      'cat_personal',
      'cat_charity',
      'cat_travel',
      'cat_other',
    ];
    for (final category in categories) {
      final fields = expenseDetailFields(category, null);
      if (category == 'cat_food' || category == 'cat_groceries') {
        expect(fields, isEmpty);
      } else {
        expect(fields, isNotEmpty, reason: category);
      }
    }
  });

  test('rent, repairs, tests, and exam fees show their specific fields', () {
    List<String> keys(String category, String subcategory) =>
        expenseDetailFields(category, subcategory).map((f) => f.key).toList();

    expect(keys('cat_house', 'sub_house_rent'), contains('landlord'));
    expect(keys('cat_house', 'sub_house_repair'), contains('laborCost'));
    expect(keys('cat_car', 'sub_car_repair'), contains('partsCost'));
    expect(expenseDetailFields('cat_health', 'sub_hlth_test').last.label,
        'Test name');
    expect(expenseDetailFields('cat_education', 'sub_edu_exam').last.label,
        'Exam name');
  });

  test('quantity applies to goods and fuel, not fees or services', () {
    const withQuantity = [
      ('cat_groceries', 'sub_groc_rice'),
      ('cat_food', 'sub_food_roti'),
      ('cat_car', 'sub_car_fuel'),
      ('cat_car', 'sub_car_tyres'),
      ('cat_transport', 'sub_trsp_fuel'),
      ('cat_house', 'sub_house_furniture'),
      ('cat_education', 'sub_edu_books'),
      ('cat_clothing', 'sub_cloth_purchases'),
      ('cat_health', 'sub_hlth_med'),
      ('cat_stationery', 'sub_stat_pens'),
      ('cat_shopping', 'sub_shop_elec'),
    ];
    const withoutQuantity = [
      ('cat_house', 'sub_house_rent'),
      ('cat_house', 'sub_house_maint'),
      ('cat_house', 'sub_house_repair'),
      ('cat_car', 'sub_car_maint'),
      ('cat_car', 'sub_car_repair'),
      ('cat_utilities', 'sub_util_elec'),
      ('cat_education', 'sub_edu_monthly'),
      ('cat_health', 'sub_hlth_doc'),
      ('cat_transport', 'sub_trsp_taxi'),
    ];
    for (final (category, subcategory) in withQuantity) {
      expect(expenseUsesQuantity(category, subcategory), isTrue,
          reason: subcategory);
    }
    for (final (category, subcategory) in withoutQuantity) {
      expect(expenseUsesQuantity(category, subcategory), isFalse,
          reason: subcategory);
    }
  });

  test('metered utilities accept independent numeric readings', () {
    for (final subcategory in [
      'sub_util_elec',
      'sub_util_gas',
      'sub_util_water'
    ]) {
      final keys = expenseDetailFields('cat_utilities', subcategory)
          .map((field) => field.key);
      expect(keys, containsAll(['previousReading', 'currentReading']));
      expect(
        expenseDetailsValidationError('cat_utilities', subcategory,
            {'previousReading': '200', 'currentReading': '150'}),
        isNull,
      );
    }
    expect(
      expenseDetailFields('cat_utilities', 'sub_util_internet')
          .map((field) => field.key),
      isNot(contains('currentReading')),
    );
    expect(
      expenseDetailsValidationError('cat_utilities', 'sub_util_elec',
          {'previousReading': '150', 'currentReading': '200'}),
      isNull,
    );
    expect(
      expenseDetailsValidationError('cat_utilities', 'sub_util_elec',
          {'currentReading': 'not a number'}),
      isNotNull,
    );
  });
}
