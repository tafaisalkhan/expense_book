import 'package:myexpence/features/categories/domain/models/category.dart';
import 'package:myexpence/features/document_scanner/domain/services/ocr_scanner_service.dart';

class UnreadableVoiceException implements Exception {
  final String message;
  const UnreadableVoiceException(this.message);

  @override
  String toString() => message;
}

/// Offline, zero-API natural speech parser that converts spoken expense phrases
/// (e.g. "Milk 320, Panadol 180, Petrol 3500" or "Spent 500 on chicken and 250 on bread")
/// into categorized [OcrLineItem] entries mapped to their respective Category & Subcategory.
class VoiceExpenseParser {
  static const Map<String, int> _smallNumbers = {
    'zero': 0,
    'one': 1,
    'two': 2,
    'three': 3,
    'four': 4,
    'five': 5,
    'six': 6,
    'seven': 7,
    'eight': 8,
    'nine': 9,
    'ten': 10,
    'eleven': 11,
    'twelve': 12,
    'thirteen': 13,
    'fourteen': 14,
    'fifteen': 15,
    'sixteen': 16,
    'seventeen': 17,
    'eighteen': 18,
    'nineteen': 19,
    'twenty': 20,
    'thirty': 30,
    'forty': 40,
    'fifty': 50,
    'sixty': 60,
    'seventy': 70,
    'eighty': 80,
    'ninety': 90,
  };

  static const Set<String> _fillerWords = {
    'i',
    'we',
    'spent',
    'spend',
    'paid',
    'pay',
    'bought',
    'buy',
    'purchased',
    'purchase',
    'add',
    'added',
    'expense',
    'expenses',
    'for',
    'on',
    'of',
    'to',
    'the',
    'a',
    'an',
    'my',
    'today',
    'yesterday',
    'rupees',
    'rupee',
    'rs',
    'pkr',
    'dollars',
    'dollar',
    'usd',
    'ka',
    'ki',
    'ke',
    'mein',
    'par',
    'pe',
  };

  static List<OcrLineItem> parse(
    String transcript, {
    List<Category> availableCategories = const [],
  }) {
    final cleaned = transcript.trim();
    if (cleaned.length < 3) {
      throw const UnreadableVoiceException(
        'Could not hear clearly. Try saying e.g. "Milk 320 and Petrol 2000".',
      );
    }

    final normalized = _replaceSpokenNumberWords(cleaned);
    final clauses = normalized
        .split(RegExp(r'[,;\n]+|\b(?:and|plus|then|also|aur)\b',
            caseSensitive: false))
        .map((c) => c.trim())
        .where((c) => c.isNotEmpty)
        .toList();

    final items = <OcrLineItem>[];
    final amountRegExp = RegExp(
      r'(?:RS\.?|PKR|\$|USD)?\s*([0-9,]+(?:\.[0-9]{1,2})?)\s*(?:/-)?',
      caseSensitive: false,
    );

    for (final clause in clauses) {
      final matches = amountRegExp.allMatches(clause).toList();
      if (matches.isEmpty) continue;

      // Pick the strongest positive numeric amount in the clause
      double? amount;
      RegExpMatch? chosenMatch;
      for (final m in matches) {
        final rawNum = m.group(1)?.replaceAll(',', '');
        final val = rawNum != null ? double.tryParse(rawNum) : null;
        if (val != null && val > 0 && val <= 9999999) {
          amount = val;
          chosenMatch = m;
          break;
        }
      }
      if (amount == null || chosenMatch == null) continue;

      final withoutNumber =
          '${clause.substring(0, chosenMatch.start)} ${clause.substring(chosenMatch.end)}'
              .replaceAll(RegExp(r'[^a-zA-Z0-9\s\-&]'), ' ')
              .trim();

      final words = withoutNumber
          .split(RegExp(r'\s+'))
          .where((w) => w.isNotEmpty && !_fillerWords.contains(w.toLowerCase()))
          .toList();

      if (words.isEmpty) continue;
      final itemName = _titleCase(words.join(' '));
      if (!RegExp(r'[a-zA-Z]{2,}').hasMatch(itemName)) continue;

      final match = OcrScannerService.matchCategoryForItem(
        itemName,
        availableCategories: availableCategories,
      );

      items.add(OcrLineItem(
        name: itemName,
        amount: amount,
        quantity: 1.0,
        categoryId: match.categoryId,
        categoryName: match.categoryName,
        subcategoryId: match.subcategoryId,
        subcategoryName: match.subcategoryName,
        classification: match.classification,
      ));
    }

    if (items.isEmpty) {
      throw const UnreadableVoiceException(
        'Could not detect an expense item and amount. Try saying e.g. "Milk 320, Panadol 180, Petrol 3500".',
      );
    }

    return items;
  }

  /// Converts English spoken number phrases (e.g. "two hundred fifty", "five thousand")
  /// into digits so offline regex parsing handles both digits and spoken words cleanly.
  static String _replaceSpokenNumberWords(String input) {
    final tokens = input.split(RegExp(r'\s+'));
    final out = <String>[];
    int i = 0;

    while (i < tokens.length) {
      final raw = tokens[i];
      final clean = raw.toLowerCase().replaceAll(RegExp(r'[^a-z]'), '');
      if (_smallNumbers.containsKey(clean) ||
          clean == 'hundred' ||
          clean == 'thousand') {
        int total = 0;
        int current = 0;
        int j = i;
        bool consumed = false;

        while (j < tokens.length) {
          final tClean =
              tokens[j].toLowerCase().replaceAll(RegExp(r'[^a-z]'), '');
          if (_smallNumbers.containsKey(tClean)) {
            current += _smallNumbers[tClean]!;
            consumed = true;
            j++;
          } else if (tClean == 'hundred') {
            current = (current == 0 ? 1 : current) * 100;
            consumed = true;
            j++;
          } else if (tClean == 'thousand') {
            total += (current == 0 ? 1 : current) * 1000;
            current = 0;
            consumed = true;
            j++;
          } else {
            break;
          }
        }

        if (consumed) {
          final trailingPunct =
              RegExp(r'[,;.!?]+$').firstMatch(tokens[j - 1])?.group(0) ?? '';
          out.add('${total + current}$trailingPunct');
          i = j;
          continue;
        }
      }
      out.add(raw);
      i++;
    }

    return out.join(' ');
  }

  static String _titleCase(String text) {
    return text
        .split(' ')
        .where((w) => w.isNotEmpty)
        .map((w) => w.length == 1
            ? w.toUpperCase()
            : '${w[0].toUpperCase()}${w.substring(1)}')
        .join(' ');
  }
}
