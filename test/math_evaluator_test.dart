import 'package:flutter_test/flutter_test.dart';
import 'package:myexpence/core/utils/math_evaluator.dart';

void main() {
  group('MathEvaluator Tests', () {
    test('Evaluates plain numbers', () {
      expect(MathEvaluator.tryEvaluate('500'), equals(500.0));
      expect(MathEvaluator.tryEvaluate('125.50'), equals(125.50));
    });

    test('Evaluates addition: 800+100', () {
      expect(MathEvaluator.tryEvaluate('800+100'), equals(900.0));
      expect(MathEvaluator.tryEvaluate('800 + 100'), equals(900.0));
    });

    test('Evaluates chained additions: 500+250+50', () {
      expect(MathEvaluator.tryEvaluate('500+250+50'), equals(800.0));
    });

    test('Evaluates subtraction: 1000-250', () {
      expect(MathEvaluator.tryEvaluate('1000-250'), equals(750.0));
    });

    test('Evaluates multiplication: 25*4', () {
      expect(MathEvaluator.tryEvaluate('25*4'), equals(100.0));
    });

    test('Evaluates division: 1500/3', () {
      expect(MathEvaluator.tryEvaluate('1500/3'), equals(500.0));
    });

    test('Respects operator precedence: 100 + 50 * 2 = 200', () {
      expect(MathEvaluator.tryEvaluate('100 + 50 * 2'), equals(200.0));
    });

    test('Returns null on incomplete input while typing', () {
      expect(MathEvaluator.tryEvaluate('800+'), isNull);
      expect(MathEvaluator.tryEvaluate(''), isNull);
      expect(MathEvaluator.tryEvaluate('abc'), isNull);
    });

    test('Formats cleanly', () {
      expect(MathEvaluator.format(900.0), equals('900'));
      expect(MathEvaluator.format(900.5), equals('900.5'));
      expect(MathEvaluator.format(900.25), equals('900.25'));
    });
  });
}
