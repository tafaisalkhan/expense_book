class AppCurrency {
  final String code;
  final String symbol;
  final String name;
  final String flag;

  const AppCurrency({
    required this.code,
    required this.symbol,
    required this.name,
    required this.flag,
  });

  String get displayName => '$flag  $name ($symbol)';
}

const List<AppCurrency> famousCurrencies = [
  AppCurrency(code: 'PKR', symbol: 'Rs', name: 'Pakistani Rupee', flag: '🇵🇰'),
  AppCurrency(code: 'USD', symbol: '\$', name: 'US Dollar', flag: '🇺🇸'),
  AppCurrency(code: 'EUR', symbol: '€', name: 'Euro', flag: '🇪🇺'),
  AppCurrency(code: 'GBP', symbol: '£', name: 'British Pound', flag: '🇬🇧'),
  AppCurrency(code: 'INR', symbol: '₹', name: 'Indian Rupee', flag: '🇮🇳'),
  AppCurrency(code: 'AED', symbol: 'AED', name: 'UAE Dirham', flag: '🇦🇪'),
  AppCurrency(code: 'SAR', symbol: 'SAR', name: 'Saudi Riyal', flag: '🇸🇦'),
  AppCurrency(code: 'CAD', symbol: 'CA\$', name: 'Canadian Dollar', flag: '🇨🇦'),
  AppCurrency(code: 'AUD', symbol: 'AU\$', name: 'Australian Dollar', flag: '🇦🇺'),
  AppCurrency(code: 'TRY', symbol: '₺', name: 'Turkish Lira', flag: '🇹🇷'),
  AppCurrency(code: 'JPY', symbol: '¥', name: 'Japanese Yen', flag: '🇯🇵'),
  AppCurrency(code: 'CNY', symbol: '¥', name: 'Chinese Yuan', flag: '🇨🇳'),
  AppCurrency(code: 'KWD', symbol: 'KD', name: 'Kuwaiti Dinar', flag: '🇰🇼'),
  AppCurrency(code: 'QAR', symbol: 'QR', name: 'Qatari Riyal', flag: '🇶🇦'),
  AppCurrency(code: 'OMR', symbol: 'OMR', name: 'Omani Rial', flag: '🇴🇲'),
  AppCurrency(code: 'BHD', symbol: 'BD', name: 'Bahraini Dinar', flag: '🇧🇭'),
  AppCurrency(code: 'MYR', symbol: 'RM', name: 'Malaysian Ringgit', flag: '🇲🇾'),
  AppCurrency(code: 'SGD', symbol: 'SG\$', name: 'Singapore Dollar', flag: '🇸🇬'),
];
