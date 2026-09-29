import 'package:myexpence/features/expenses/domain/models/expense_classification.dart';

class SmsParseResult {
  final double amount;
  final String? merchant;
  final String suggestedCategoryId;
  final ExpenseClassification classification;
  final DateTime detectedDate;
  final String rawSms;
  final String? sender;
  final bool isKnownSender;
  final String? senderValidationMessage;

  const SmsParseResult({
    required this.amount,
    this.merchant,
    required this.suggestedCategoryId,
    required this.classification,
    required this.detectedDate,
    required this.rawSms,
    this.sender,
    this.isKnownSender = true,
    this.senderValidationMessage,
  });
}

class SmsParserService {
  /// Default whitelisted bank sender IDs and numeric shortcodes (including 9220, 8257, 8558, 8222, 8008, 8228, 4250, 3737, etc.)
  static const List<String> defaultAllowedSenders = [
    '9220',
    '8257',
    '8558',
    '8222',
    '8008',
    '8228',
    '8444',
    '4250',
    '3737',
    'MeezanBank',
    'Meezan',
    'MezanBank',
    'HBL',
    'UBL',
    'MCB',
    'BAHL',
    'BankAlfalah',
    'Alfalah',
    'AskariBank',
    'StandardChartered',
    'SCB',
    'FaysalBank',
    'AlliedBank',
    'ABL',
    'BOP',
    'BankOfPunjab',
    'JSBank',
    'BankIslami',
    'AlBaraka',
    'HabibMetro',
    'SilkBank',
    'SummitBank',
    'JazzCash',
    'Easypaisa',
    'SadaPay',
    'NayaPay',
  ];

  /// Checks if a given sender ID or phone number is in built-in default bank list OR user custom whitelist.
  static bool isAllowedSender(String? sender, {List<String>? customAllowedSenders}) {
    if (sender == null || sender.trim().isEmpty) return false;
    final cleanSender = sender.trim().toLowerCase();

    // 1. Check built-in default bank senders & shortcodes
    final isDefault = defaultAllowedSenders.any((s) {
      final cleanAllowed = s.trim().toLowerCase();
      return cleanSender == cleanAllowed ||
             cleanSender.contains(cleanAllowed) ||
             cleanAllowed.contains(cleanSender);
    });
    if (isDefault) return true;

    // 2. Check user's custom whitelisted senders
    if (customAllowedSenders != null && customAllowedSenders.isNotEmpty) {
      return customAllowedSenders.any((s) {
        final cleanAllowed = s.trim().toLowerCase();
        return cleanSender == cleanAllowed ||
               cleanSender.contains(cleanAllowed) ||
               cleanAllowed.contains(cleanSender);
      });
    }

    return false;
  }

  /// Extracts sender ID from SMS headers if embedded in raw text (e.g., "From: MeezanBank").
  static String? extractSenderFromText(String smsContent) {
    final senderRegex = RegExp(r'(?:from|sender|orig|src):\s*([A-Za-z0-9_\-\+]{3,20})', caseSensitive: false);
    final match = senderRegex.firstMatch(smsContent);
    return match?.group(1);
  }

  /// Parses raw SMS text shared by the user with dynamic amount & location detection.
  static SmsParseResult parseSmsText(String smsContent, {String? sender, List<String>? customAllowedSenders}) {
    final cleanSms = smsContent.trim();
    final detectedSender = sender ?? extractSenderFromText(cleanSms);
    final isWhitelisted = isAllowedSender(detectedSender, customAllowedSenders: customAllowedSenders);

    final amount = _extractAmount(cleanSms);
    final merchant = _extractMerchant(cleanSms);
    final categoryId = _detectCategory(cleanSms, merchant);
    final classification = _detectClassification(cleanSms, categoryId);
    final date = _extractDate(cleanSms);

    String? validationMsg;
    if (detectedSender != null && detectedSender.isNotEmpty) {
      if (isWhitelisted) {
        validationMsg = 'Verified Bank/Vendor Sender: $detectedSender';
      } else {
        validationMsg = 'Warning: Unverified Sender ($detectedSender). Double-check expense details.';
      }
    }

    return SmsParseResult(
      amount: amount,
      merchant: merchant,
      suggestedCategoryId: categoryId,
      classification: classification,
      detectedDate: date,
      rawSms: cleanSms,
      sender: detectedSender,
      isKnownSender: isWhitelisted,
      senderValidationMessage: validationMsg,
    );
  }

  static double _extractAmount(String sms) {
    // Dynamic patterns for all global transaction currencies & words (Rs, PKR, USD, $, EUR, INR, debited, paid, charged, spent, txn, amount)
    final amountRegexes = [
      RegExp(r'(?:debited|spent|paid|charged|txn|amount|vdr|price|cost|bal|transfer|transferred)(?:\s+by|\s+for|\s+of|\s+at)?\s*[:=]?\s*(?:Rs\.?|PKR|INR|\$|USD|EUR|GBP)?\s*([0-9,]+(?:\.[0-9]{1,2})?)', caseSensitive: false),
      RegExp(r'(?:Rs\.?|PKR|INR|\$|USD|EUR|GBP)\s*([0-9,]+(?:\.[0-9]{1,2})?)', caseSensitive: false),
      RegExp(r'([0-9,]+(?:\.[0-9]{1,2})?)\s*(?:Rs\.?|PKR|INR|\$|USD|EUR|GBP)', caseSensitive: false),
      RegExp(r'\b([0-9]{1,6}\.[0-9]{2})\b'), // Generic decimal amounts like 3500.00
    ];

    for (final regex in amountRegexes) {
      final match = regex.firstMatch(sms);
      if (match != null && match.group(1) != null) {
        final amountStr = match.group(1)!.replaceAll(',', '');
        final parsed = double.tryParse(amountStr);
        if (parsed != null && parsed > 0) {
          return parsed;
        }
      }
    }

    return 0.0;
  }

  static String? _extractMerchant(String sms) {
    // Dynamic patterns for location / merchant extraction: "at <Location>", "in <Location>", "to <Location>", "from <Location>", "POS <Location>", "ATM <Location>", "vdr <Vendor>", "info: <Vendor>"
    final merchantRegexes = [
      RegExp(r'(?:at|to|from|in|vdr|vendor|pos|atm|store|shop|pump|branch|info:)\s+([A-Za-z0-9\s&\-\.]{3,30}?)(?:\s+on|\s+for|\s+ref|\s+avail|\s+via|\.|$|,)', caseSensitive: false),
      RegExp(r'(?:POS|ATM|BRANCH)\s+([A-Za-z0-9\s&\-\.]{3,30}?)(?:\s+on|\s+avail|\.|$|,)', caseSensitive: false),
    ];

    for (final regex in merchantRegexes) {
      final match = regex.firstMatch(sms);
      if (match != null && match.group(1) != null) {
        final vendor = match.group(1)!.trim();
        if (vendor.isNotEmpty && !vendor.toLowerCase().contains('account') && !vendor.toLowerCase().contains('avail')) {
          return vendor;
        }
      }
    }

    return null;
  }

  static String _detectCategory(String sms, String? merchant) {
    final combined = '${sms.toLowerCase()} ${(merchant ?? '').toLowerCase()}';

    if (combined.contains('petrol') || combined.contains('fuel') || combined.contains('shell') || combined.contains('total') || combined.contains('parco') || combined.contains('attock') || combined.contains('pso') || combined.contains('byco') || combined.contains('pump')) {
      return 'cat_transport';
    }
    if (combined.contains('mart') || combined.contains('supermarket') || combined.contains('grocery') || combined.contains('metro') || combined.contains('carrefour') || combined.contains('store') || combined.contains('chase') || combined.contains('imtiaz') || combined.contains('alfatah') || combined.contains('savemart')) {
      return 'cat_groceries';
    }
    if (combined.contains('hospital') || combined.contains('clinic') || combined.contains('pharma') || combined.contains('medical') || combined.contains('doctor') || combined.contains('lab')) {
      return 'cat_health';
    }
    if (combined.contains('food') || combined.contains('restaurant') || combined.contains('cafe') || combined.contains('kfc') || combined.contains('mcd') || combined.contains('pizza') || combined.contains('dining')) {
      return 'cat_food';
    }
    if (combined.contains('bill') || combined.contains('electricity') || combined.contains('k-electric') || combined.contains('wapda') || combined.contains('utility') || combined.contains('internet')) {
      return 'cat_utilities';
    }

    return 'cat_shopping';
  }

  static ExpenseClassification _detectClassification(String sms, String categoryId) {
    if (categoryId == 'cat_groceries' || categoryId == 'cat_utilities' || categoryId == 'cat_health') {
      return ExpenseClassification.required;
    }
    return ExpenseClassification.optional;
  }

  static DateTime _extractDate(String sms) {
    final dateRegex = RegExp(r'(\d{1,2})[-/]([A-Za-z0-9]{2,3})[-/](\d{2,4})');
    final match = dateRegex.firstMatch(sms);

    if (match != null) {
      final day = int.tryParse(match.group(1) ?? '') ?? DateTime.now().day;
      final yearStr = match.group(3) ?? '';
      var year = int.tryParse(yearStr) ?? DateTime.now().year;
      if (year < 100) year += 2000;

      return DateTime(year, DateTime.now().month, day);
    }

    return DateTime.now();
  }
}
