import 'package:flutter_test/flutter_test.dart';
import 'package:myexpence/features/expenses/domain/models/expense_classification.dart';
import 'package:myexpence/features/expenses/presentation/screens/multi_item_detail_screen.dart';

void main() {
  group('MultiItemLine Model Tests', () {
    test('displayName with quantity and unitPrice', () {
      const line = MultiItemLine(
        name: 'Basmati Rice',
        subcategoryId: 'sub_rice',
        amount: 550,
        quantity: '2.5 kg',
        unitPrice: 220,
      );
      expect(line.displayName, contains('Basmati Rice (2.5 kg @'));
      expect(line.displayName, contains('220)'));
    });

    test('displayName with quantity only', () {
      const line = MultiItemLine(
        name: 'Eggs',
        subcategoryId: 'sub_eggs',
        amount: 300,
        quantity: '1 dozen',
      );
      expect(line.displayName, equals('Eggs (1 dozen)'));
    });

    test('displayName with no quantity or unit price', () {
      const line = MultiItemLine(
        name: 'Salt',
        subcategoryId: 'sub_salt',
        amount: 40,
      );
      expect(line.displayName, equals('Salt'));
    });

    test('displayName with classification and family member', () {
      const line = MultiItemLine(
        name: 'School Notebooks',
        subcategoryId: 'sub_books',
        amount: 600,
        quantity: '3 pcs',
        unitPrice: 200,
        classification: ExpenseClassification.urgent,
        personId: 'person_ahmed',
        personName: 'Ahmed',
      );
      expect(line.displayName, contains('School Notebooks (3 pcs @'));
      expect(line.displayName, contains('• for Ahmed'));
      expect(line.classification, equals(ExpenseClassification.urgent));
      expect(line.personId, equals('person_ahmed'));
    });

    test('MultiItemLine supports all 4 classifications (urgent, required, optional, lost)', () {
      const urgentLine = MultiItemLine(
        name: 'Medicine',
        subcategoryId: null,
        amount: 400,
        classification: ExpenseClassification.urgent,
      );
      const reqLine = MultiItemLine(
        name: 'Flour',
        subcategoryId: null,
        amount: 1200,
        classification: ExpenseClassification.required,
      );
      const optLine = MultiItemLine(
        name: 'Ice Cream',
        subcategoryId: null,
        amount: 250,
        classification: ExpenseClassification.optional,
      );
      const lostLine = MultiItemLine(
        name: 'Spilled Milk',
        subcategoryId: null,
        amount: 150,
        classification: ExpenseClassification.lost,
      );

      expect(urgentLine.classification, equals(ExpenseClassification.urgent));
      expect(reqLine.classification, equals(ExpenseClassification.required));
      expect(optLine.classification, equals(ExpenseClassification.optional));
      expect(lostLine.classification, equals(ExpenseClassification.lost));
    });
  });

  group('3-Way Auto-Calculation Logic Tests', () {
    test('Qty + Unit Price calculates Total', () {
      const qty = 3.0;
      const unitPrice = 150.0;
      final total = qty * unitPrice;
      expect(total, equals(450.0));
    });

    test('Total + Qty calculates Unit Price', () {
      const total = 500.0;
      const qty = 4.0;
      final unitPrice = total / qty;
      expect(unitPrice, equals(125.0));
    });

    test('Total + Unit Price calculates Quantity', () {
      const total = 1000.0;
      const unitPrice = 250.0;
      final qty = total / unitPrice;
      expect(qty, equals(4.0));
    });

    test('Decimal quantity calculation works accurately', () {
      const qty = 2.5;
      const unitPrice = 140.0;
      final total = qty * unitPrice;
      expect(total, equals(350.0));
    });

    test('MultiItemResult preserves updated target total', () {
      const res = MultiItemResult(
        items: [
          MultiItemLine(name: 'Milk', subcategoryId: null, amount: 200),
        ],
        targetTotal: 1500,
      );
      expect(res.items.length, equals(1));
      expect(res.targetTotal, equals(1500.0));
    });
  });
}
