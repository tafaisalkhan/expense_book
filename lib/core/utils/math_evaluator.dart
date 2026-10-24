/// Utility to safely evaluate simple arithmetic expressions like
/// "800+100", "500 + 200 - 50", "25*4", "100/2".
class MathEvaluator {
  /// Evaluates an arithmetic expression string.
  /// Returns `null` if the input is invalid, incomplete, or causes division by zero.
  static double? tryEvaluate(String? input) {
    if (input == null) return null;
    final cleaned = input.replaceAll(' ', '').trim();
    if (cleaned.isEmpty) return null;

    // Direct plain number check
    final direct = double.tryParse(cleaned);
    if (direct != null) return direct;

    // Must only contain digits, decimal points, and +, -, *, /
    final validChars = RegExp(r'^[0-9\.\+\-\*\/]+$');
    if (!validChars.hasMatch(cleaned)) return null;

    // Should not end with an operator (e.g. "800+")
    final lastChar = cleaned[cleaned.length - 1];
    if (lastChar == '+' || lastChar == '-' || lastChar == '*' || lastChar == '/') {
      return null;
    }

    try {
      return _evalSimple(cleaned);
    } catch (_) {
      return null;
    }
  }

  static double _evalSimple(String expression) {
    final tokens = <dynamic>[];
    final buffer = StringBuffer();

    for (int i = 0; i < expression.length; i++) {
      final ch = expression[i];
      if (ch == '+' || ch == '-' || ch == '*' || ch == '/') {
        // Leading negative or negative right after an operator (e.g., "5*-2")
        final isUnaryMinus = ch == '-' &&
            (i == 0 ||
                expression[i - 1] == '+' ||
                expression[i - 1] == '-' ||
                expression[i - 1] == '*' ||
                expression[i - 1] == '/');
        if (isUnaryMinus) {
          buffer.write(ch);
          continue;
        }

        if (buffer.isNotEmpty) {
          tokens.add(double.parse(buffer.toString()));
          buffer.clear();
        }
        tokens.add(ch);
      } else {
        buffer.write(ch);
      }
    }

    if (buffer.isNotEmpty) {
      tokens.add(double.parse(buffer.toString()));
    }

    if (tokens.isEmpty) throw const FormatException('Empty expression');

    // First pass: Multiplication and Division (*, /)
    final addSubTokens = <dynamic>[];
    int idx = 0;
    while (idx < tokens.length) {
      final token = tokens[idx];
      if (token == '*' || token == '/') {
        if (addSubTokens.isEmpty || idx + 1 >= tokens.length) {
          throw const FormatException('Invalid operator position');
        }
        final prev = addSubTokens.removeLast() as double;
        final next = tokens[++idx] as double;
        if (token == '*') {
          addSubTokens.add(prev * next);
        } else {
          if (next == 0) throw const IntegerDivisionByZeroException();
          addSubTokens.add(prev / next);
        }
      } else {
        addSubTokens.add(token);
      }
      idx++;
    }

    if (addSubTokens.isEmpty || addSubTokens.first is! double) {
      throw const FormatException('Invalid expression structure');
    }

    // Second pass: Addition and Subtraction (+, -)
    double result = addSubTokens.first as double;
    idx = 1;
    while (idx < addSubTokens.length) {
      final op = addSubTokens[idx++] as String;
      if (idx >= addSubTokens.length) throw const FormatException('Trailing operator');
      final val = addSubTokens[idx++] as double;
      if (op == '+') {
        result += val;
      } else if (op == '-') {
        result -= val;
      }
    }

    return result;
  }

  /// Formats a calculated number cleanly without unnecessary trailing decimals.
  static String format(double value) {
    if (value == value.roundToDouble()) {
      return value.toStringAsFixed(0);
    }
    final s = value.toStringAsFixed(2);
    if (s.endsWith('.00')) return s.substring(0, s.length - 3);
    if (s.endsWith('0')) return s.substring(0, s.length - 1);
    return s;
  }

  /// Checks if an input string contains any math operator.
  static bool hasOperator(String input) {
    return input.contains('+') ||
        input.contains('-') ||
        input.contains('*') ||
        input.contains('/');
  }
}
