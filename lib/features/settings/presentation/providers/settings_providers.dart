import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:myexpence/core/utils/currency_formatters.dart';
import 'package:myexpence/features/settings/domain/models/app_currency.dart';

const String _prefKeyCurrencySymbol = 'app_currency_symbol';
const String _prefKeyCurrencyCode = 'app_currency_code';

class CurrencyState {
  final String code;
  final String symbol;

  const CurrencyState({
    required this.code,
    required this.symbol,
  });

  AppCurrency? get matchingPreset {
    try {
      return famousCurrencies.firstWhere((c) => c.code == code || c.symbol == symbol);
    } catch (_) {
      return null;
    }
  }
}

class CurrencyNotifier extends StateNotifier<CurrencyState> {
  CurrencyNotifier() : super(const CurrencyState(code: 'PKR', symbol: 'Rs')) {
    _loadCurrency();
  }

  Future<void> _loadCurrency() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final symbol = prefs.getString(_prefKeyCurrencySymbol) ?? 'Rs';
      final code = prefs.getString(_prefKeyCurrencyCode) ?? 'PKR';
      CurrencyFormatters.defaultCurrency = symbol;
      state = CurrencyState(code: code, symbol: symbol);
    } catch (_) {}
  }

  Future<void> setCurrency(AppCurrency currency) async {
    await setCustomCurrency(code: currency.code, symbol: currency.symbol);
  }

  Future<void> setCustomCurrency({required String code, required String symbol}) async {
    final cleanSymbol = symbol.trim().isEmpty ? 'Rs' : symbol.trim();
    final cleanCode = code.trim().isEmpty ? cleanSymbol : code.trim().toUpperCase();

    CurrencyFormatters.defaultCurrency = cleanSymbol;
    state = CurrencyState(code: cleanCode, symbol: cleanSymbol);

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefKeyCurrencySymbol, cleanSymbol);
      await prefs.setString(_prefKeyCurrencyCode, cleanCode);
    } catch (_) {}
  }
}

final currencyNotifierProvider = StateNotifierProvider<CurrencyNotifier, CurrencyState>((ref) {
  return CurrencyNotifier();
});
