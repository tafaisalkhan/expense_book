import 'package:flutter_test/flutter_test.dart';
import 'package:myexpence/features/categories/domain/models/category.dart';
import 'package:myexpence/features/expenses/domain/models/expense.dart';
import 'package:myexpence/features/expenses/domain/models/expense_allocation.dart';
import 'package:myexpence/features/expenses/domain/models/expense_classification.dart';
import 'package:myexpence/features/expenses/domain/models/payment_method.dart';
import 'package:myexpence/features/expenses/presentation/screens/multi_item_detail_screen.dart';

void main() {
  group('Category and Subcategory Breakdown Filtering Tests', () {
    final catFood = Category(
      id: 'cat_food',
      name: 'Food & Dining',
      icon: 'restaurant',
      sortOrder: 1,
      defaultClassification: ExpenseClassification.required,
      subcategories: [
        Subcategory(
          id: 'sub_groceries',
          categoryId: 'cat_food',
          name: 'Groceries',
          defaultClassification: ExpenseClassification.required,
          sortOrder: 1,
        ),
        Subcategory(
          id: 'sub_dining',
          categoryId: 'cat_food',
          name: 'Dining Out',
          defaultClassification: ExpenseClassification.optional,
          sortOrder: 2,
        ),
      ],
    );

    final catTransport = Category(
      id: 'cat_transport',
      name: 'Transportation',
      icon: 'directions_car',
      sortOrder: 2,
      defaultClassification: ExpenseClassification.required,
      subcategories: [
        Subcategory(
          id: 'sub_fuel',
          categoryId: 'cat_transport',
          name: 'Fuel / Petrol',
          defaultClassification: ExpenseClassification.urgent,
          sortOrder: 1,
        ),
      ],
    );

    final categoryMap = {
      catFood.id: catFood,
      catTransport.id: catTransport,
    };

    final subNameMap = <String, String>{
      'sub_groceries': 'Groceries',
      'sub_dining': 'Dining Out',
      'sub_fuel': 'Fuel / Petrol',
    };

    final expenses = [
      Expense(
        uuid: 'e1',
        amount: 1500.0,
        categoryId: 'cat_food',
        subcategoryId: 'sub_groceries',
        classification: ExpenseClassification.required,
        expenseDate: '2026-10-20',
        createdAt: '2026-10-20T10:00:00Z',
        updatedAt: '2026-10-20T10:00:00Z',
        paymentMethod: PaymentMethod.cash,
        currency: 'Rs',
      ),
      Expense(
        uuid: 'e2',
        amount: 800.0,
        categoryId: 'cat_food',
        subcategoryId: 'sub_dining',
        classification: ExpenseClassification.optional,
        expenseDate: '2026-10-21',
        createdAt: '2026-10-21T10:00:00Z',
        updatedAt: '2026-10-21T10:00:00Z',
        paymentMethod: PaymentMethod.debitCard,
        currency: 'Rs',
      ),
      Expense(
        uuid: 'e3',
        amount: 2500.0,
        categoryId: 'cat_transport',
        subcategoryId: 'sub_fuel',
        classification: ExpenseClassification.urgent,
        personId: 'p_ahmed',
        allocations: const [
          ExpenseAllocation(
            personId: 'p_ahmed',
            personName: 'Ahmed',
            percentage: 100,
            amount: 2500.0,
          ),
        ],
        expenseDate: '2026-10-22',
        createdAt: '2026-10-22T10:00:00Z',
        updatedAt: '2026-10-22T10:00:00Z',
        paymentMethod: PaymentMethod.cash,
        currency: 'Rs',
      ),
      Expense(
        uuid: 'e4_deleted',
        amount: 999.0,
        categoryId: 'cat_food',
        subcategoryId: 'sub_groceries',
        classification: ExpenseClassification.required,
        isDeleted: true,
        expenseDate: '2026-10-23',
        createdAt: '2026-10-23T10:00:00Z',
        updatedAt: '2026-10-23T10:00:00Z',
        paymentMethod: PaymentMethod.cash,
        currency: 'Rs',
      ),
    ];

    test('Filters category expenses excluding deleted transactions', () {
      final foodExpenses = expenses.where((exp) {
        if (exp.isDeleted || exp.status == ExpenseStatus.cancelled) return false;
        return exp.categoryId == 'cat_food';
      }).toList();

      expect(foodExpenses.length, 2);
      expect(foodExpenses.map((e) => e.uuid), containsAll(['e1', 'e2']));
      expect(foodExpenses.any((e) => e.uuid == 'e4_deleted'), isFalse);
    });

    test('Filters subcategory expenses accurately by mapped name', () {
      final groceriesExpenses = expenses.where((exp) {
        if (exp.isDeleted || exp.status == ExpenseStatus.cancelled) return false;
        final subId = exp.subcategoryId;
        String name;
        if (subId != null && subNameMap.containsKey(subId)) {
          name = subNameMap[subId]!;
        } else {
          final catName = categoryMap[exp.categoryId]?.name ?? exp.categoryId;
          name = '$catName (General)';
        }
        return name == 'Groceries';
      }).toList();

      expect(groceriesExpenses.length, 1);
      expect(groceriesExpenses.first.uuid, 'e1');
      expect(groceriesExpenses.first.amount, 1500.0);
    });

    test('Preserves subcategory-level classification and family member', () {
      final fuelExp = expenses.firstWhere((e) => e.uuid == 'e3');
      expect(fuelExp.classification, ExpenseClassification.urgent);
      expect(fuelExp.personId, 'p_ahmed');
      expect(fuelExp.allocations.first.personName, 'Ahmed');

      // Convert to MultiItemLine (as done in edit mode)
      final line = MultiItemLine(
        name: subNameMap[fuelExp.subcategoryId!]!,
        subcategoryId: fuelExp.subcategoryId,
        amount: fuelExp.amount,
        classification: fuelExp.classification,
        personId: fuelExp.personId,
        personName: fuelExp.allocations.first.personName,
      );

      expect(line.name, 'Fuel / Petrol');
      expect(line.classification, ExpenseClassification.urgent);
      expect(line.personId, 'p_ahmed');
      expect(line.personName, 'Ahmed');
      expect(line.displayName, contains('Fuel / Petrol • for Ahmed'));
    });

    test('Computes and filters family member spending reports accurately', () {
      final personNameMap = {'p_ahmed': 'Ahmed', 'p_fatima': 'Fatima'};
      final familySpendingMap = <String, double>{};

      for (final exp in expenses) {
        if (exp.isDeleted || exp.status == ExpenseStatus.cancelled) continue;
        if (exp.allocations.isNotEmpty) {
          for (final alloc in exp.allocations) {
            final pName = personNameMap[alloc.personId] ?? alloc.personName;
            final name = pName.trim().isNotEmpty ? pName : 'Household (General)';
            familySpendingMap[name] = (familySpendingMap[name] ?? 0.0) + alloc.amount;
          }
        } else if (exp.personId != null &&
            exp.personId!.isNotEmpty &&
            exp.personId != 'household') {
          final name = personNameMap[exp.personId!] ?? 'Family Member';
          familySpendingMap[name] = (familySpendingMap[name] ?? 0.0) + exp.amount;
        } else {
          familySpendingMap['Household (General)'] =
              (familySpendingMap['Household (General)'] ?? 0.0) + exp.amount;
        }
      }

      // e1 (1500) -> Household, e2 (800) -> Household, e3 (2500) -> Ahmed
      expect(familySpendingMap['Ahmed'], 2500.0);
      expect(familySpendingMap['Household (General)'], 2300.0);

      // Filter matching expenses for Ahmed
      final ahmedExpenses = expenses.where((exp) {
        if (exp.isDeleted || exp.status == ExpenseStatus.cancelled) return false;
        return exp.personId == 'p_ahmed' ||
            exp.allocations.any((a) => a.personId == 'p_ahmed');
      }).toList();

      expect(ahmedExpenses.length, 1);
      expect(ahmedExpenses.first.uuid, 'e3');
      expect(ahmedExpenses.first.amount, 2500.0);
    });
  });
}
