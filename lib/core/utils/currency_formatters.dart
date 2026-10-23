import 'package:intl/intl.dart';

class CurrencyFormatters {
  static String defaultCurrency = 'Rs';

  static String format(double amount, {String? currencySymbol}) {
    final symbol = (currencySymbol != null && currencySymbol.isNotEmpty)
        ? currencySymbol
        : defaultCurrency;
    final formatter = NumberFormat('#,##0.00', 'en_US');
    final formattedStr = formatter.format(amount);
    // Remove .00 if whole number for clean UX
    final cleanStr = formattedStr.endsWith('.00')
        ? formattedStr.substring(0, formattedStr.length - 3)
        : formattedStr;
    return '$symbol $cleanStr';
  }

  static String formatCompact(double amount, {String? currencySymbol}) {
    final symbol = (currencySymbol != null && currencySymbol.isNotEmpty)
        ? currencySymbol
        : defaultCurrency;
    if (amount >= 1000000) {
      return '$symbol ${(amount / 1000000).toStringAsFixed(1)}M';
    } else if (amount >= 1000) {
      return '$symbol ${(amount / 1000).toStringAsFixed(1)}K';
    }
    return '$symbol ${amount.toStringAsFixed(0)}';
  }
}
