import 'dart:io';
import 'dart:math';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:myexpence/features/categories/domain/models/category.dart';
import 'package:myexpence/features/expenses/domain/models/expense_classification.dart';

class OcrCategoryMatch {
  final String categoryId;
  final String categoryName;
  final String? subcategoryId;
  final String? subcategoryName;
  final ExpenseClassification classification;

  const OcrCategoryMatch({
    required this.categoryId,
    required this.categoryName,
    this.subcategoryId,
    this.subcategoryName,
    required this.classification,
  });
}

class OcrLineItem {
  final String name;
  final double amount;
  final double quantity;
  final String? categoryId;
  final String? categoryName;
  final String? subcategoryId;
  final String? subcategoryName;
  final ExpenseClassification classification;
  final String? personId;

  const OcrLineItem({
    required this.name,
    required this.amount,
    this.quantity = 1.0,
    this.categoryId,
    this.categoryName,
    this.subcategoryId,
    this.subcategoryName,
    this.classification = ExpenseClassification.required,
    this.personId,
  });

  OcrLineItem copyWith({
    String? name,
    double? amount,
    double? quantity,
    String? categoryId,
    String? categoryName,
    String? subcategoryId,
    String? subcategoryName,
    ExpenseClassification? classification,
    String? personId,
  }) {
    return OcrLineItem(
      name: name ?? this.name,
      amount: amount ?? this.amount,
      quantity: quantity ?? this.quantity,
      categoryId: categoryId ?? this.categoryId,
      categoryName: categoryName ?? this.categoryName,
      subcategoryId: subcategoryId ?? this.subcategoryId,
      subcategoryName: subcategoryName ?? this.subcategoryName,
      classification: classification ?? this.classification,
      personId: personId ?? this.personId,
    );
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        'amount': amount,
        'quantity': quantity,
        'categoryId': categoryId,
        'categoryName': categoryName,
        'subcategoryId': subcategoryId,
        'subcategoryName': subcategoryName,
        'classification': classification.name,
        'personId': personId,
      };

  factory OcrLineItem.fromJson(Map<String, dynamic> json) => OcrLineItem(
        name: json['name'] as String,
        amount: (json['amount'] as num).toDouble(),
        quantity: (json['quantity'] as num?)?.toDouble() ?? 1.0,
        categoryId: json['categoryId'] as String?,
        categoryName: json['categoryName'] as String?,
        subcategoryId: json['subcategoryId'] as String?,
        subcategoryName: json['subcategoryName'] as String?,
        classification: ExpenseClassification.values.firstWhere(
          (e) => e.name == json['classification'],
          orElse: () => ExpenseClassification.required,
        ),
        personId: json['personId'] as String?,
      );
}

class OcrResult {
  final String? merchant;
  final double totalAmount;
  final String dateIso;
  final String? timeString;
  final DateTime? fullDateTime;
  final String suggestedCategoryId;
  final String suggestedCategoryName;
  final String? suggestedSubcategoryId;
  final String? suggestedSubcategoryName;
  final List<OcrLineItem> lineItems;
  final String rawText;
  final double confidence;
  final int pageCount;

  const OcrResult({
    this.merchant,
    required this.totalAmount,
    required this.dateIso,
    this.timeString,
    this.fullDateTime,
    required this.suggestedCategoryId,
    required this.suggestedCategoryName,
    this.suggestedSubcategoryId,
    this.suggestedSubcategoryName,
    required this.lineItems,
    required this.rawText,
    required this.confidence,
    this.pageCount = 1,
  });
}

class UnsupportedFileFormatException implements Exception {
  final String message;
  const UnsupportedFileFormatException(this.message);

  @override
  String toString() => message;
}

class UnreadableReceiptException implements Exception {
  final String message;
  final String reasonCode;
  final String tip;

  const UnreadableReceiptException({
    required this.message,
    required this.reasonCode,
    required this.tip,
  });

  @override
  String toString() => message;
}

class _TaxonomyRule {
  final List<String> keywords;
  final String categoryId;
  final String categoryName;
  final String? subcategoryId;
  final String? subcategoryName;
  final ExpenseClassification classification;

  const _TaxonomyRule({
    required this.keywords,
    required this.categoryId,
    required this.categoryName,
    this.subcategoryId,
    this.subcategoryName,
    required this.classification,
  });
}

class OcrScannerService {
  static const Set<String> supportedExtensions = {
    'jpg',
    'jpeg',
    'png',
    'webp',
    'heic',
    'pdf',
  };

  static const List<String> _nonItemKeywords = [
    'SUBTOTAL',
    'SUB TOTAL',
    'GRAND TOTAL',
    'NET TOTAL',
    'NET AMOUNT',
    'NET VALUE',
    'NET PAYABLE',
    'AMOUNT DUE',
    'BILL AMOUNT',
    'TOTAL',
    'CASH',
    'CHANGE',
    'RETURN',
    'BALANCE',
    'TENDERED',
    'TAX',
    'GST',
    'VAT',
    'DISCOUNT',
    'POS FEE',
    'FBR',
    'INVOICE',
    'RECEIPT',
    'TEL',
    'PHONE',
    'MOBILE',
    'FAX',
    'NTN',
    'STRN',
    'DATE',
    'TIME',
    'THANK',
    'WELCOME',
    'CARD',
    'VISA',
    'MASTERCARD',
    'QTY',
    'PRICE',
    'AMOUNT',
    'RATE',
    'DESCRIPTION',
    'SECTION',
    'PAYMENT',
    'PAID',
    'ADDRESS',
    'CASHIER',
  ];

  static const List<_TaxonomyRule> _taxonomyRules = [
    // Utilities & Bills
    _TaxonomyRule(
      keywords: ['ELECTRIC', 'LESCO', 'IESCO', 'KELECTRIC', 'K-ELECTRIC', 'WAPDA', 'MEPCO', 'FESCO', 'KWH'],
      categoryId: 'cat_utilities',
      categoryName: 'Utilities',
      subcategoryId: 'sub_util_elec',
      subcategoryName: 'Electricity',
      classification: ExpenseClassification.required,
    ),
    _TaxonomyRule(
      keywords: ['SNGPL', 'SSGC', 'SUI GAS', 'NATURAL GAS', 'GAS BILL', 'CYLINDER'],
      categoryId: 'cat_utilities',
      categoryName: 'Utilities',
      subcategoryId: 'sub_util_gas',
      subcategoryName: 'Gas',
      classification: ExpenseClassification.required,
    ),
    _TaxonomyRule(
      keywords: ['WASA', 'WATER BILL', 'SEWERAGE'],
      categoryId: 'cat_utilities',
      categoryName: 'Utilities',
      subcategoryId: 'sub_util_water',
      subcategoryName: 'Water',
      classification: ExpenseClassification.required,
    ),
    _TaxonomyRule(
      keywords: ['INTERNET', 'PTCL', 'NAYATEL', 'STORMFIBER', 'WIFI', 'BROADBAND', 'FIBER'],
      categoryId: 'cat_utilities',
      categoryName: 'Utilities',
      subcategoryId: 'sub_util_internet',
      subcategoryName: 'Internet',
      classification: ExpenseClassification.required,
    ),
    _TaxonomyRule(
      keywords: ['JAZZ', 'ZONG', 'TELENOR', 'UFONE', 'MOBILE LOAD', 'SIM', 'RECHARGE'],
      categoryId: 'cat_utilities',
      categoryName: 'Utilities',
      subcategoryId: 'sub_util_mobile',
      subcategoryName: 'Mobile',
      classification: ExpenseClassification.required,
    ),

    // Car & Fuel
    _TaxonomyRule(
      keywords: ['PETROL', 'FUEL', 'DIESEL', 'HI-OCTANE', 'OCTANE', 'SHELL', 'PSO', 'CALTEX', 'PARCO', 'ATTOCK', 'CNG'],
      categoryId: 'cat_car',
      categoryName: 'Car',
      subcategoryId: 'sub_car_fuel',
      subcategoryName: 'Fuel',
      classification: ExpenseClassification.required,
    ),
    _TaxonomyRule(
      keywords: ['TYRE', 'TIRE', 'WHEEL', 'ALIGNMENT'],
      categoryId: 'cat_car',
      categoryName: 'Car',
      subcategoryId: 'sub_car_tyres',
      subcategoryName: 'Tyres',
      classification: ExpenseClassification.required,
    ),
    _TaxonomyRule(
      keywords: ['CAR BATTERY', 'AGS BATTERY', 'EXIDE'],
      categoryId: 'cat_car',
      categoryName: 'Car',
      subcategoryId: 'sub_car_battery',
      subcategoryName: 'Battery',
      classification: ExpenseClassification.required,
    ),
    _TaxonomyRule(
      keywords: ['OIL CHANGE', 'CAR SERVICE', 'TUNING', 'CAR MAINT'],
      categoryId: 'cat_car',
      categoryName: 'Car',
      subcategoryId: 'sub_car_maint',
      subcategoryName: 'Maintenance',
      classification: ExpenseClassification.required,
    ),
    _TaxonomyRule(
      keywords: ['MECHANIC', 'DENTING', 'CAR REPAIR', 'AUTO WORKSHOP'],
      categoryId: 'cat_car',
      categoryName: 'Car',
      subcategoryId: 'sub_car_repair',
      subcategoryName: 'Repair',
      classification: ExpenseClassification.required,
    ),
    _TaxonomyRule(
      keywords: ['TOLL', 'MOTORWAY', 'M-TAG', 'MTAG'],
      categoryId: 'cat_car',
      categoryName: 'Car',
      subcategoryId: 'sub_car_toll',
      subcategoryName: 'Toll',
      classification: ExpenseClassification.required,
    ),
    _TaxonomyRule(
      keywords: ['PARKING'],
      categoryId: 'cat_car',
      categoryName: 'Car',
      subcategoryId: 'sub_car_parking',
      subcategoryName: 'Parking',
      classification: ExpenseClassification.optional,
    ),
    _TaxonomyRule(
      keywords: ['CAR WASH'],
      categoryId: 'cat_car',
      categoryName: 'Car',
      subcategoryId: 'sub_car_cleaning',
      subcategoryName: 'Cleaning',
      classification: ExpenseClassification.optional,
    ),

    // Health & Medical
    _TaxonomyRule(
      keywords: ['MEDICINE', 'PANADOL', 'BRUFEN', 'AUGMENTIN', 'PARACETAMOL', 'TABLET', 'CAPSULE', 'SYRUP', 'PHARMACY', 'MEDICOS', 'CHEMIST', 'ANTIBIOTIC', 'DROPS', 'CREAM', 'INJECTION'],
      categoryId: 'cat_health',
      categoryName: 'Health',
      subcategoryId: 'sub_hlth_med',
      subcategoryName: 'Medicine',
      classification: ExpenseClassification.required,
    ),
    _TaxonomyRule(
      keywords: ['DOCTOR', 'CONSULTATION', 'CLINIC', 'OPD', 'PHYSICIAN'],
      categoryId: 'cat_health',
      categoryName: 'Health',
      subcategoryId: 'sub_hlth_doc',
      subcategoryName: 'Doctor',
      classification: ExpenseClassification.required,
    ),
    _TaxonomyRule(
      keywords: ['HOSPITAL', 'EMERGENCY', 'WARD', 'ADMISSION FEE MED'],
      categoryId: 'cat_health',
      categoryName: 'Health',
      subcategoryId: 'sub_hlth_hosp',
      subcategoryName: 'Hospital',
      classification: ExpenseClassification.urgent,
    ),
    _TaxonomyRule(
      keywords: ['LAB', 'CHUGHTAI', 'DIAGNOSTIC', 'CBC', 'BLOOD TEST', 'X-RAY', 'XRAY', 'MRI', 'ULTRASOUND'],
      categoryId: 'cat_health',
      categoryName: 'Health',
      subcategoryId: 'sub_hlth_lab',
      subcategoryName: 'Laboratory',
      classification: ExpenseClassification.required,
    ),
    _TaxonomyRule(
      keywords: ['DENTAL', 'DENTIST', 'SCALING'],
      categoryId: 'cat_health',
      categoryName: 'Health',
      subcategoryId: 'sub_hlth_dent',
      subcategoryName: 'Dental',
      classification: ExpenseClassification.required,
    ),
    _TaxonomyRule(
      keywords: ['OPTICAL', 'GLASSES', 'LENS', 'OPTICIAN'],
      categoryId: 'cat_health',
      categoryName: 'Health',
      subcategoryId: 'sub_hlth_opt',
      subcategoryName: 'Optical',
      classification: ExpenseClassification.required,
    ),

    // Groceries (specific pantry / dairy / household cleaning items first)
    _TaxonomyRule(
      keywords: ['MILK', 'DOODH', 'OLPERS', 'MILKPAK', 'TARANG'],
      categoryId: 'cat_groceries',
      categoryName: 'Groceries',
      subcategoryId: 'sub_groc_milk',
      subcategoryName: 'Milk',
      classification: ExpenseClassification.required,
    ),
    _TaxonomyRule(
      keywords: ['YOGURT', 'DAHI', 'CURD'],
      categoryId: 'cat_groceries',
      categoryName: 'Groceries',
      subcategoryId: 'sub_groc_yogurt',
      subcategoryName: 'Yogurt',
      classification: ExpenseClassification.required,
    ),
    _TaxonomyRule(
      keywords: ['BREAD', 'DAWN', 'BUN', 'RUSK'],
      categoryId: 'cat_groceries',
      categoryName: 'Groceries',
      subcategoryId: 'sub_groc_bread',
      subcategoryName: 'Bread',
      classification: ExpenseClassification.required,
    ),
    _TaxonomyRule(
      keywords: ['EGG', 'EGGS', 'ANDAY'],
      categoryId: 'cat_groceries',
      categoryName: 'Groceries',
      subcategoryId: 'sub_groc_eggs',
      subcategoryName: 'Eggs',
      classification: ExpenseClassification.required,
    ),
    _TaxonomyRule(
      keywords: ['CHICKEN', 'POULTRY', 'BREAST', 'FILLET'],
      categoryId: 'cat_groceries',
      categoryName: 'Groceries',
      subcategoryId: 'sub_groc_chicken',
      subcategoryName: 'Chicken',
      classification: ExpenseClassification.required,
    ),
    _TaxonomyRule(
      keywords: ['BEEF', 'QEEMA', 'MINCE', 'VEAL'],
      categoryId: 'cat_groceries',
      categoryName: 'Groceries',
      subcategoryId: 'sub_groc_beef',
      subcategoryName: 'Beef',
      classification: ExpenseClassification.required,
    ),
    _TaxonomyRule(
      keywords: ['MUTTON', 'FISH', 'LAMB', 'PRAWN'],
      categoryId: 'cat_groceries',
      categoryName: 'Groceries',
      subcategoryId: 'sub_groc_mutton',
      subcategoryName: 'Mutton & Fish',
      classification: ExpenseClassification.required,
    ),
    _TaxonomyRule(
      keywords: ['RICE', 'BASMATI', 'CHAWAL'],
      categoryId: 'cat_groceries',
      categoryName: 'Groceries',
      subcategoryId: 'sub_groc_rice',
      subcategoryName: 'Rice',
      classification: ExpenseClassification.required,
    ),
    _TaxonomyRule(
      keywords: ['FLOUR', 'ATTA', 'MAIDA', 'CHAKKI'],
      categoryId: 'cat_groceries',
      categoryName: 'Groceries',
      subcategoryId: 'sub_groc_flour',
      subcategoryName: 'Flour',
      classification: ExpenseClassification.required,
    ),
    _TaxonomyRule(
      keywords: ['WHEAT', 'GANDUM'],
      categoryId: 'cat_groceries',
      categoryName: 'Groceries',
      subcategoryId: 'sub_groc_wheat',
      subcategoryName: 'Wheat',
      classification: ExpenseClassification.required,
    ),
    _TaxonomyRule(
      keywords: ['COOKING OIL', 'OLIVE OIL', 'SUNFLOWER OIL', 'CANOLA OIL', 'SOYA OIL', 'DALDA', 'SUFI', 'MEZAN'],
      categoryId: 'cat_groceries',
      categoryName: 'Groceries',
      subcategoryId: 'sub_groc_oil',
      subcategoryName: 'Cooking Oil',
      classification: ExpenseClassification.required,
    ),
    _TaxonomyRule(
      keywords: ['GHEE', 'BANASPATI'],
      categoryId: 'cat_groceries',
      categoryName: 'Groceries',
      subcategoryId: 'sub_groc_ghee',
      subcategoryName: 'Ghee',
      classification: ExpenseClassification.required,
    ),
    _TaxonomyRule(
      keywords: ['BUTTER', 'BLUE BAND', 'MARGARINE'],
      categoryId: 'cat_groceries',
      categoryName: 'Groceries',
      subcategoryId: 'sub_groc_butter',
      subcategoryName: 'Butter',
      classification: ExpenseClassification.required,
    ),
    _TaxonomyRule(
      keywords: ['SUGAR', 'CHEENI'],
      categoryId: 'cat_groceries',
      categoryName: 'Groceries',
      subcategoryId: 'sub_groc_sugar',
      subcategoryName: 'Sugar',
      classification: ExpenseClassification.required,
    ),
    _TaxonomyRule(
      keywords: ['TEA', 'TAPAL', 'LIPTON', 'DANEDAR', 'CHAI', 'GREEN TEA'],
      categoryId: 'cat_groceries',
      categoryName: 'Groceries',
      subcategoryId: 'sub_groc_tea',
      subcategoryName: 'Tea',
      classification: ExpenseClassification.required,
    ),
    _TaxonomyRule(
      keywords: ['SALT', 'NAMAK'],
      categoryId: 'cat_groceries',
      categoryName: 'Groceries',
      subcategoryId: 'sub_groc_salt',
      subcategoryName: 'Salt',
      classification: ExpenseClassification.required,
    ),
    _TaxonomyRule(
      keywords: ['DAL', 'DAAL', 'LENTIL', 'PULSES', 'MASOOR', 'MOONG'],
      categoryId: 'cat_groceries',
      categoryName: 'Groceries',
      subcategoryId: 'sub_groc_dal',
      subcategoryName: 'Dal / Pulses',
      classification: ExpenseClassification.required,
    ),
    _TaxonomyRule(
      keywords: ['SPICE', 'MASALA', 'SHAN', 'NATIONAL', 'CHILLI', 'TURMERIC', 'HALDI'],
      categoryId: 'cat_groceries',
      categoryName: 'Groceries',
      subcategoryId: 'sub_groc_spices',
      subcategoryName: 'Spices',
      classification: ExpenseClassification.required,
    ),
    _TaxonomyRule(
      keywords: ['VEGETABLE', 'SABZI', 'POTATO', 'TOMATO', 'ONION', 'GARLIC', 'GINGER', 'PEAS', 'CARROT'],
      categoryId: 'cat_groceries',
      categoryName: 'Groceries',
      subcategoryId: 'sub_groc_veg',
      subcategoryName: 'Vegetables',
      classification: ExpenseClassification.required,
    ),
    _TaxonomyRule(
      keywords: ['FRUIT', 'APPLE', 'BANANA', 'MANGO', 'ORANGE', 'GRAPES', 'MELON'],
      categoryId: 'cat_groceries',
      categoryName: 'Groceries',
      subcategoryId: 'sub_groc_fruits',
      subcategoryName: 'Fruits',
      classification: ExpenseClassification.required,
    ),
    _TaxonomyRule(
      keywords: ['BISCUIT', 'COOKIE', 'OREO', 'SOOPER'],
      categoryId: 'cat_groceries',
      categoryName: 'Groceries',
      subcategoryId: 'sub_groc_biscuits',
      subcategoryName: 'Biscuits',
      classification: ExpenseClassification.optional,
    ),
    _TaxonomyRule(
      keywords: ['SNACK', 'CHIPS', 'LAYS', 'KURKURE', 'NIMKO'],
      categoryId: 'cat_groceries',
      categoryName: 'Groceries',
      subcategoryId: 'sub_groc_snacks',
      subcategoryName: 'Snacks',
      classification: ExpenseClassification.optional,
    ),
    _TaxonomyRule(
      keywords: ['NOODLE', 'KNORR', 'MAGGI'],
      categoryId: 'cat_groceries',
      categoryName: 'Groceries',
      subcategoryId: 'sub_groc_noodles',
      subcategoryName: 'Noodles',
      classification: ExpenseClassification.optional,
    ),
    _TaxonomyRule(
      keywords: ['MACARONI', 'PASTA', 'SPAGHETTI'],
      categoryId: 'cat_groceries',
      categoryName: 'Groceries',
      subcategoryId: 'sub_groc_macaroni',
      subcategoryName: 'Macaroni',
      classification: ExpenseClassification.optional,
    ),
    _TaxonomyRule(
      keywords: ['KETCHUP', 'MAYO', 'CHILLI GARLIC', 'SAUCE'],
      categoryId: 'cat_groceries',
      categoryName: 'Groceries',
      subcategoryId: 'sub_groc_ketchup',
      subcategoryName: 'Ketchup / Sauces',
      classification: ExpenseClassification.optional,
    ),
    _TaxonomyRule(
      keywords: ['JUICE', 'NESTLE FRUITA', 'SLICE'],
      categoryId: 'cat_groceries',
      categoryName: 'Groceries',
      subcategoryId: 'sub_groc_juice',
      subcategoryName: 'Juice',
      classification: ExpenseClassification.optional,
    ),
    _TaxonomyRule(
      keywords: ['MINERAL WATER', 'PURE LIFE', 'AQUAFINA', 'WATER 1.5L', 'WATER 500ML'],
      categoryId: 'cat_groceries',
      categoryName: 'Groceries',
      subcategoryId: 'sub_groc_water',
      subcategoryName: 'Mineral Water',
      classification: ExpenseClassification.required,
    ),
    _TaxonomyRule(
      keywords: ['SURF', 'DETERGENT', 'ARIEL', 'BONUS', 'WASHING POWDER', 'BRITE'],
      categoryId: 'cat_groceries',
      categoryName: 'Groceries',
      subcategoryId: 'sub_groc_surf',
      subcategoryName: 'Surf / Detergent',
      classification: ExpenseClassification.required,
    ),
    _TaxonomyRule(
      keywords: ['SOAP', 'LIFEBUOY', 'LUX', 'SAFEGUARD', 'DETTOL SOAP'],
      categoryId: 'cat_groceries',
      categoryName: 'Groceries',
      subcategoryId: 'sub_groc_soap',
      subcategoryName: 'Soap',
      classification: ExpenseClassification.required,
    ),
    _TaxonomyRule(
      keywords: ['DISHWASH', 'LEMON MAX', 'VIM'],
      categoryId: 'cat_groceries',
      categoryName: 'Groceries',
      subcategoryId: 'sub_groc_dishwash',
      subcategoryName: 'Dishwash',
      classification: ExpenseClassification.required,
    ),
    _TaxonomyRule(
      keywords: ['SHAMPOO', 'HEAD & SHOULDERS', 'SUNSILK', 'PANTENE'],
      categoryId: 'cat_groceries',
      categoryName: 'Groceries',
      subcategoryId: 'sub_groc_shampoo',
      subcategoryName: 'Shampoo',
      classification: ExpenseClassification.required,
    ),
    _TaxonomyRule(
      keywords: ['TOOTHPASTE', 'COLGATE', 'SENSODYNE', 'PEPSODENT', 'TOOTHBRUSH'],
      categoryId: 'cat_groceries',
      categoryName: 'Groceries',
      subcategoryId: 'sub_groc_toothpaste',
      subcategoryName: 'Toothpaste',
      classification: ExpenseClassification.required,
    ),
    _TaxonomyRule(
      keywords: ['TISSUE', 'ROSE PETAL', 'NAPKIN'],
      categoryId: 'cat_groceries',
      categoryName: 'Groceries',
      subcategoryId: 'sub_groc_tissue',
      subcategoryName: 'Tissue',
      classification: ExpenseClassification.required,
    ),

    // Food & Restaurant
    _TaxonomyRule(
      keywords: ['ROTI', 'NAAN', 'PARATHA', 'TANDOOR'],
      categoryId: 'cat_food',
      categoryName: 'Food',
      subcategoryId: 'sub_food_roti',
      subcategoryName: 'Roti & Naan',
      classification: ExpenseClassification.required,
    ),
    _TaxonomyRule(
      keywords: ['HALEEM'],
      categoryId: 'cat_food',
      categoryName: 'Food',
      subcategoryId: 'sub_food_haleem',
      subcategoryName: 'Haleem',
      classification: ExpenseClassification.required,
    ),
    _TaxonomyRule(
      keywords: ['COFFEE', 'ESPRESSO', 'CAPPUCCINO', 'LATTE'],
      categoryId: 'cat_food',
      categoryName: 'Food',
      subcategoryId: 'sub_food_drinks',
      subcategoryName: 'Tea & Coffee',
      classification: ExpenseClassification.optional,
    ),
    _TaxonomyRule(
      keywords: ['RESTAURANT', 'CAFE', 'BAKERY', 'BURGER', 'PIZZA', 'KFC', 'MCDONALD', 'HARDEES', 'BIRYANI', 'KARAHI', 'TIKKA', 'SHAWARMA', 'FRIES', 'DINING', 'FOODPANDA', 'SANDWICH', 'CAKE', 'PASTRY'],
      categoryId: 'cat_food',
      categoryName: 'Food',
      subcategoryId: 'sub_food_rest',
      subcategoryName: 'Restaurant & Fast Food',
      classification: ExpenseClassification.optional,
    ),

    // Education & Stationery
    _TaxonomyRule(
      keywords: ['TUITION', 'ACADEMY', 'COACHING'],
      categoryId: 'cat_education',
      categoryName: 'Education',
      subcategoryId: 'sub_edu_tuition',
      subcategoryName: 'Tuition',
      classification: ExpenseClassification.required,
    ),
    _TaxonomyRule(
      keywords: ['EXAM FEE', 'EXAMINATION'],
      categoryId: 'cat_education',
      categoryName: 'Education',
      subcategoryId: 'sub_edu_exam',
      subcategoryName: 'Exam Fee',
      classification: ExpenseClassification.required,
    ),
    _TaxonomyRule(
      keywords: ['SCHOOL UNIFORM', 'UNIFORM'],
      categoryId: 'cat_education',
      categoryName: 'Education',
      subcategoryId: 'sub_edu_uniform',
      subcategoryName: 'Uniform',
      classification: ExpenseClassification.required,
    ),
    _TaxonomyRule(
      keywords: ['SCHOOL', 'COLLEGE', 'UNIVERSITY', 'VOUCHER', 'FEE CHALLAN', 'MONTHLY FEE', 'ANNUAL FEE', 'ADMISSION FEE'],
      categoryId: 'cat_education',
      categoryName: 'Education',
      subcategoryId: 'sub_edu_monthly',
      subcategoryName: 'Monthly Fee',
      classification: ExpenseClassification.required,
    ),
    _TaxonomyRule(
      keywords: ['TEXTBOOK', 'BOOKSHOP', 'COURSE BOOK'],
      categoryId: 'cat_education',
      categoryName: 'Education',
      subcategoryId: 'sub_edu_books',
      subcategoryName: 'Books',
      classification: ExpenseClassification.required,
    ),
    _TaxonomyRule(
      keywords: ['NOTEBOOK', 'REGISTER', 'COPIES', 'COPY'],
      categoryId: 'cat_stationery',
      categoryName: 'Stationery',
      subcategoryId: 'sub_stat_copies',
      subcategoryName: 'Copies & Notebooks',
      classification: ExpenseClassification.required,
    ),
    _TaxonomyRule(
      keywords: ['PHOTOSTAT', 'PHOTOCOPY', 'PRINTING', 'LAMINATION'],
      categoryId: 'cat_stationery',
      categoryName: 'Stationery',
      subcategoryId: 'sub_stat_photostat',
      subcategoryName: 'Photostat & Printing',
      classification: ExpenseClassification.required,
    ),
    _TaxonomyRule(
      keywords: ['PENCIL'],
      categoryId: 'cat_stationery',
      categoryName: 'Stationery',
      subcategoryId: 'sub_stat_pencils',
      subcategoryName: 'Pencils',
      classification: ExpenseClassification.required,
    ),
    _TaxonomyRule(
      keywords: ['BALLPOINT', 'MARKER', 'GEL PEN', 'PEN '],
      categoryId: 'cat_stationery',
      categoryName: 'Stationery',
      subcategoryId: 'sub_stat_pens',
      subcategoryName: 'Pens',
      classification: ExpenseClassification.required,
    ),
    _TaxonomyRule(
      keywords: ['ERASER', 'SHARPENER', 'STATIONERY'],
      categoryId: 'cat_stationery',
      categoryName: 'Stationery',
      subcategoryId: 'sub_stat_eraser_sharpener',
      subcategoryName: 'Erasers & Sharpeners',
      classification: ExpenseClassification.required,
    ),

    // Transport
    _TaxonomyRule(
      keywords: ['UBER', 'CAREEM', 'INDRIVE', 'YANGO', 'BYKEA'],
      categoryId: 'cat_transport',
      categoryName: 'Transport',
      subcategoryId: 'sub_trsp_ride',
      subcategoryName: 'Ride Hailing',
      classification: ExpenseClassification.required,
    ),
    _TaxonomyRule(
      keywords: ['TAXI', 'RICKSHAW'],
      categoryId: 'cat_transport',
      categoryName: 'Transport',
      subcategoryId: 'sub_trsp_taxi',
      subcategoryName: 'Taxi',
      classification: ExpenseClassification.required,
    ),
    _TaxonomyRule(
      keywords: ['BUS TICKET', 'DAEWOO', 'METRO BUS', 'TRANS'],
      categoryId: 'cat_transport',
      categoryName: 'Transport',
      subcategoryId: 'sub_trsp_bus',
      subcategoryName: 'Bus',
      classification: ExpenseClassification.required,
    ),
    _TaxonomyRule(
      keywords: ['TRAIN', 'RAILWAY', 'GREEN LINE'],
      categoryId: 'cat_transport',
      categoryName: 'Transport',
      subcategoryId: 'sub_trsp_train',
      subcategoryName: 'Train',
      classification: ExpenseClassification.required,
    ),

    // Clothing & Shopping
    _TaxonomyRule(
      keywords: ['LAUNDRY', 'DRY CLEAN', 'IRONING', 'PRESS'],
      categoryId: 'cat_clothing',
      categoryName: 'Clothing',
      subcategoryId: 'sub_cloth_press',
      subcategoryName: 'Clothing Press & Ironing',
      classification: ExpenseClassification.required,
    ),
    _TaxonomyRule(
      keywords: ['TAILOR', 'STITCHING', 'SILAI'],
      categoryId: 'cat_clothing',
      categoryName: 'Clothing',
      subcategoryId: 'sub_cloth_tailor',
      subcategoryName: 'Tailoring & Stitching',
      classification: ExpenseClassification.required,
    ),
    _TaxonomyRule(
      keywords: ['SHIRT', 'JEANS', 'TROUSER', 'SUIT', 'KURTA', 'KAMEEZ', 'SHALWAR', 'JACKET', 'DUPATTA', 'FASHION', 'GARMENT', 'KHAADI', 'J.', 'SANA SAFINAZ'],
      categoryId: 'cat_clothing',
      categoryName: 'Clothing',
      subcategoryId: 'sub_cloth_purchases',
      subcategoryName: 'Clothing Purchases',
      classification: ExpenseClassification.required,
    ),
    _TaxonomyRule(
      keywords: ['SHOES', 'SNEAKER', 'SANDAL', 'SLIPPER', 'BATA', 'SERVIS', 'STYLO'],
      categoryId: 'cat_shopping',
      categoryName: 'Shopping',
      subcategoryId: 'sub_shop_shoes',
      subcategoryName: 'Shoes',
      classification: ExpenseClassification.required,
    ),
    _TaxonomyRule(
      keywords: ['ELECTRONIC', 'CHARGER', 'CABLE', 'HEADPHONE', 'EARBUD', 'POWER BANK', 'BULB'],
      categoryId: 'cat_shopping',
      categoryName: 'Shopping',
      subcategoryId: 'sub_shop_elec',
      subcategoryName: 'Electronics',
      classification: ExpenseClassification.optional,
    ),
    _TaxonomyRule(
      keywords: ['GIFT', 'BOUQUET', 'FLOWER'],
      categoryId: 'cat_shopping',
      categoryName: 'Shopping',
      subcategoryId: 'sub_shop_gifts',
      subcategoryName: 'Gifts',
      classification: ExpenseClassification.optional,
    ),

    // House, Personal, Charity, Travel
    _TaxonomyRule(
      keywords: ['HOUSE RENT', 'MONTHLY RENT'],
      categoryId: 'cat_house',
      categoryName: 'House',
      subcategoryId: 'sub_house_rent',
      subcategoryName: 'Rent',
      classification: ExpenseClassification.required,
    ),
    _TaxonomyRule(
      keywords: ['FURNITURE', 'SOFA', 'CHAIR', 'TABLE'],
      categoryId: 'cat_house',
      categoryName: 'House',
      subcategoryId: 'sub_house_furniture',
      subcategoryName: 'Furniture',
      classification: ExpenseClassification.optional,
    ),
    _TaxonomyRule(
      keywords: ['APPLIANCE', 'FRIDGE', 'OVEN', 'MIXER'],
      categoryId: 'cat_house',
      categoryName: 'House',
      subcategoryId: 'sub_house_appliances',
      subcategoryName: 'Appliances',
      classification: ExpenseClassification.optional,
    ),
    _TaxonomyRule(
      keywords: ['HAIRCUT', 'BARBER', 'SALON', 'PARLOUR', 'SHAVE'],
      categoryId: 'cat_personal',
      categoryName: 'Personal',
      subcategoryId: 'sub_pers_haircut',
      subcategoryName: 'Haircut',
      classification: ExpenseClassification.required,
    ),
    _TaxonomyRule(
      keywords: ['GYM', 'FITNESS'],
      categoryId: 'cat_personal',
      categoryName: 'Personal',
      subcategoryId: 'sub_pers_fitness',
      subcategoryName: 'Fitness',
      classification: ExpenseClassification.optional,
    ),
    _TaxonomyRule(
      keywords: ['ZAKAT'],
      categoryId: 'cat_charity',
      categoryName: 'Charity',
      subcategoryId: 'sub_chr_zakat',
      subcategoryName: 'Zakat',
      classification: ExpenseClassification.required,
    ),
    _TaxonomyRule(
      keywords: ['SADAQAH', 'SADQA'],
      categoryId: 'cat_charity',
      categoryName: 'Charity',
      subcategoryId: 'sub_chr_sadaqah',
      subcategoryName: 'Sadaqah',
      classification: ExpenseClassification.required,
    ),
    _TaxonomyRule(
      keywords: ['CHARITY', 'DONATION', 'FOUNDATION'],
      categoryId: 'cat_charity',
      categoryName: 'Charity',
      subcategoryId: 'sub_chr_donation',
      subcategoryName: 'Donation',
      classification: ExpenseClassification.required,
    ),
    _TaxonomyRule(
      keywords: ['HOTEL', 'RESORT', 'BOOKING'],
      categoryId: 'cat_travel',
      categoryName: 'Travel',
      subcategoryId: 'sub_trv_hotel',
      subcategoryName: 'Hotel',
      classification: ExpenseClassification.optional,
    ),
    _TaxonomyRule(
      keywords: ['FLIGHT', 'AIRLINE', 'PIA', 'BOARDING'],
      categoryId: 'cat_travel',
      categoryName: 'Travel',
      subcategoryId: 'sub_trv_ticket',
      subcategoryName: 'Ticket',
      classification: ExpenseClassification.optional,
    ),
    _TaxonomyRule(
      keywords: ['VISA FEE', 'EMBASSY'],
      categoryId: 'cat_travel',
      categoryName: 'Travel',
      subcategoryId: 'sub_trv_visa',
      subcategoryName: 'Visa',
      classification: ExpenseClassification.optional,
    ),

    // Broad Mart / Store fallbacks
    _TaxonomyRule(
      keywords: ['MART', 'SUPERMARKET', 'HYPERMARKET', 'METRO', 'CARREFOUR', 'IMTIAZ', 'AL-FATAH', 'AL FATAH', 'GROCERY', 'GENERAL STORE', 'KIRYANA'],
      categoryId: 'cat_groceries',
      categoryName: 'Groceries',
      subcategoryId: 'sub_groc_house',
      subcategoryName: 'Household Grocery',
      classification: ExpenseClassification.required,
    ),
  ];

  /// Validates whether the given file path/extension is a supported Image or PDF receipt file.
  static bool isSupportedFileType(String filePath) {
    if (filePath.isEmpty) return false;
    final ext = filePath.split('.').last.toLowerCase();
    if (filePath.startsWith('assets/')) return true;
    return supportedExtensions.contains(ext);
  }

  /// Auto-matches an item name (plus optional merchant/full text) to a real Category & Subcategory.
  static OcrCategoryMatch matchCategoryForItem(
    String itemText, {
    String? merchant,
    List<Category> availableCategories = const [],
  }) {
    final upperItem = ' ${itemText.toUpperCase()} ';

    // 1. Check user's live database categories & subcategories first
    for (final cat in availableCategories) {
      for (final sub in cat.subcategories) {
        final subUpper = sub.name.toUpperCase();
        if (subUpper.length >= 3 &&
            subUpper != 'OTHER' &&
            !subUpper.startsWith('OTHER ') &&
            upperItem.contains(subUpper)) {
          return OcrCategoryMatch(
            categoryId: cat.id,
            categoryName: cat.name,
            subcategoryId: sub.id,
            subcategoryName: sub.name,
            classification: sub.defaultClassification,
          );
        }
      }
    }

    // 2. Check comprehensive built-in taxonomy rules against item text
    for (final rule in _taxonomyRules) {
      if (_matchesAnyKeyword(upperItem, rule.keywords)) {
        return _resolveWithCatalog(rule, availableCategories);
      }
    }

    // 3. Check custom category names on item text
    for (final cat in availableCategories) {
      final catUpper = cat.name.toUpperCase();
      if (catUpper.length >= 3 &&
          catUpper != 'OTHER' &&
          upperItem.contains(catUpper)) {
        return OcrCategoryMatch(
          categoryId: cat.id,
          categoryName: cat.name,
          classification: cat.defaultClassification,
        );
      }
    }

    // 4. Fall back to merchant context if item name itself was generic
    if (merchant != null && merchant.trim().isNotEmpty) {
      final upperMerchant = ' ${merchant.toUpperCase()} ';
      for (final rule in _taxonomyRules) {
        if (_matchesAnyKeyword(upperMerchant, rule.keywords)) {
          return _resolveWithCatalog(rule, availableCategories);
        }
      }
    }

    // Default safe category resolved from live catalog when available
    return _resolveWithCatalog(
      const _TaxonomyRule(
        keywords: [],
        categoryId: 'cat_groceries',
        categoryName: 'Groceries',
        subcategoryId: 'sub_groc_other',
        subcategoryName: 'Other',
        classification: ExpenseClassification.required,
      ),
      availableCategories,
    );
  }

  static bool _matchesAnyKeyword(String upperPaddedText, List<String> keywords) {
    for (final kw in keywords) {
      if (kw.endsWith(' ')) {
        if (upperPaddedText.contains(' $kw')) return true;
      } else {
        if (upperPaddedText.contains(kw)) return true;
      }
    }
    return false;
  }

  static OcrCategoryMatch _resolveWithCatalog(
    _TaxonomyRule rule,
    List<Category> availableCategories,
  ) {
    for (final cat in availableCategories) {
      if (cat.id == rule.categoryId) {
        Subcategory? matchedSub;
        if (rule.subcategoryId != null) {
          for (final sub in cat.subcategories) {
            if (sub.id == rule.subcategoryId) {
              matchedSub = sub;
              break;
            }
          }
        }
        return OcrCategoryMatch(
          categoryId: cat.id,
          categoryName: cat.name,
          subcategoryId: matchedSub?.id ?? rule.subcategoryId,
          subcategoryName: matchedSub?.name ?? rule.subcategoryName,
          classification: matchedSub?.defaultClassification ?? rule.classification,
        );
      }
    }
    if (availableCategories.isNotEmpty) {
      final fallback = availableCategories.firstWhere(
        (c) => c.id == 'cat_other',
        orElse: () => availableCategories.first,
      );
      if (rule.categoryId == 'cat_groceries' &&
          rule.subcategoryId == 'sub_groc_other') {
        return OcrCategoryMatch(
          categoryId: fallback.id,
          categoryName: fallback.name,
          classification: fallback.defaultClassification,
        );
      }
    }
    return OcrCategoryMatch(
      categoryId: rule.categoryId,
      categoryName: rule.categoryName,
      subcategoryId: rule.subcategoryId,
      subcategoryName: rule.subcategoryName,
      classification: rule.classification,
    );
  }

  /// Analyzes a list of receipt photos or multi-page sections (for long receipts).
  static Future<OcrResult> scanMultipleReceipts(
    List<String> imagePaths, {
    List<Category> availableCategories = const [],
  }) async {
    if (imagePaths.isEmpty) {
      throw const UnreadableReceiptException(
        message: 'No receipt image selected.',
        reasonCode: 'no_text',
        tip: 'Capture a clear receipt photo with your camera or pick an image from your gallery.',
      );
    }
    if (imagePaths.length == 1) {
      return scanReceipt(
        imagePaths.first,
        availableCategories: availableCategories,
      );
    }

    final combinedTexts = <String>[];
    for (int i = 0; i < imagePaths.length; i++) {
      final rawSectionText = await _extractRawText(imagePaths[i]);
      final contentCheck = rawSectionText.replaceAll(RegExp(r'\s+'), '');
      if (contentCheck.length < 5) {
        throw UnreadableReceiptException(
          message: 'Section ${i + 1} has no clearly visible text.',
          reasonCode: 'no_text',
          tip: 'Retake section ${i + 1} in bright lighting with sharp focus on the text.',
        );
      }
      combinedTexts.add('--- RECEIPT SECTION ${i + 1} ---');
      combinedTexts.add(rawSectionText);
    }

    final fullText = combinedTexts.join('\n');
    final ocrResult = parseReceiptText(
      fullText,
      imagePath: imagePaths.first,
      availableCategories: availableCategories,
    );

    double itemsSum = 0.0;
    for (final item in ocrResult.lineItems) {
      itemsSum += item.amount * item.quantity;
    }

    final finalTotal =
        (ocrResult.totalAmount > itemsSum && ocrResult.totalAmount > 0)
            ? ocrResult.totalAmount
            : (itemsSum > 0 ? itemsSum : ocrResult.totalAmount);

    return OcrResult(
      merchant: ocrResult.merchant,
      totalAmount: finalTotal,
      dateIso: ocrResult.dateIso,
      timeString: ocrResult.timeString,
      fullDateTime: ocrResult.fullDateTime,
      suggestedCategoryId: ocrResult.suggestedCategoryId,
      suggestedCategoryName: ocrResult.suggestedCategoryName,
      suggestedSubcategoryId: ocrResult.suggestedSubcategoryId,
      suggestedSubcategoryName: ocrResult.suggestedSubcategoryName,
      lineItems: ocrResult.lineItems,
      rawText: fullText,
      confidence: ocrResult.confidence,
      pageCount: imagePaths.length,
    );
  }

  /// Analyzes a single receipt image or PDF document and throws [UnreadableReceiptException]
  /// when text, prices, or parts of the receipt are unreadable or cut off.
  static Future<OcrResult> scanReceipt(
    String imagePath, {
    String? customTextContent,
    List<Category> availableCategories = const [],
  }) async {
    if (customTextContent != null) {
      return parseReceiptText(
        customTextContent,
        imagePath: imagePath,
        availableCategories: availableCategories,
      );
    }

    if (imagePath.isEmpty) {
      throw const UnreadableReceiptException(
        message: 'No receipt image selected.',
        reasonCode: 'no_text',
        tip: 'Take a clear photo of the receipt or choose an image from your gallery.',
      );
    }

    if (!isSupportedFileType(imagePath)) {
      final ext = imagePath.contains('.') ? '.${imagePath.split('.').last}' : '';
      throw UnsupportedFileFormatException(
        'Unsupported file format ($ext). Only Image files (JPG/PNG/WEBP/HEIC) and PDF documents are supported.',
      );
    }

    final text = imagePath.startsWith('assets/')
        ? _generateSampleTextForPath(imagePath)
        : await _extractRawText(imagePath);

    return parseReceiptText(
      text,
      imagePath: imagePath,
      availableCategories: availableCategories,
    );
  }

  static Future<String> _extractRawText(String imagePath) async {
    if (imagePath.startsWith('assets/')) {
      return _generateSampleTextForPath(imagePath);
    }
    if (!isSupportedFileType(imagePath)) {
      final ext = imagePath.contains('.') ? '.${imagePath.split('.').last}' : '';
      throw UnsupportedFileFormatException(
        'Unsupported file format ($ext). Only Image files (JPG/PNG/WEBP/HEIC) and PDF documents are supported.',
      );
    }

    final file = File(imagePath);
    if (!file.existsSync()) {
      throw const UnreadableReceiptException(
        message: 'The selected image file could not be found.',
        reasonCode: 'no_text',
        tip: 'Please retake the photo or select another receipt image.',
      );
    }

    final ext = imagePath.split('.').last.toLowerCase();
    if (ext == 'pdf') {
      try {
        final bytes = await file.readAsBytes();
        final extracted = _extractPrintableStrings(bytes);
        if (extracted.trim().length < 12) {
          throw const UnreadableReceiptException(
            message: 'Text could not be extracted clearly from this PDF.',
            reasonCode: 'no_text',
            tip: 'Take a photo or screenshot of the receipt and scan it as an image instead.',
          );
        }
        return extracted;
      } catch (e) {
        if (e is UnreadableReceiptException) rethrow;
        throw const UnreadableReceiptException(
          message: 'Could not read text from this PDF document.',
          reasonCode: 'no_text',
          tip: 'Take a clear photo of the receipt and try again.',
        );
      }
    }

    if (file.lengthSync() < 1024) {
      throw const UnreadableReceiptException(
        message: 'This image is too small or empty to read clearly.',
        reasonCode: 'no_text',
        tip: 'Hold your camera closer so the receipt text fills the frame, then retake.',
      );
    }

    TextRecognizer? textRecognizer;
    try {
      final inputImage = InputImage.fromFilePath(imagePath);
      textRecognizer = TextRecognizer(script: TextRecognitionScript.latin);
      final recognizedText = await textRecognizer.processImage(inputImage);
      var reconstructed = _reconstructSpatialLines(recognizedText);
      if (reconstructed.trim().isEmpty) {
        reconstructed = recognizedText.text;
      }
      if (reconstructed.trim().isEmpty) {
        throw const UnreadableReceiptException(
          message: 'No readable text was found on this image.',
          reasonCode: 'no_text',
          tip: 'Place the receipt on a flat surface in bright lighting and retake the photo.',
        );
      }
      return reconstructed;
    } catch (e) {
      if (e is UnreadableReceiptException) rethrow;
      throw const UnreadableReceiptException(
        message: 'Text is not clearly visible on this receipt image.',
        reasonCode: 'no_text',
        tip: 'Check focus and lighting, then retake the photo.',
      );
    } finally {
      await textRecognizer?.close();
    }
  }

  /// Groups OCR lines into horizontal receipt rows using a height-adaptive Y tolerance.
  static String _reconstructSpatialLines(RecognizedText recognizedText) {
    final allLines = <TextLine>[];
    for (final block in recognizedText.blocks) {
      allLines.addAll(block.lines);
    }

    if (allLines.isEmpty) return recognizedText.text;

    double totalHeight = 0.0;
    for (final line in allLines) {
      totalHeight += line.boundingBox.height;
    }
    final avgHeight = totalHeight / allLines.length;
    final double yTolerance = (avgHeight * 0.55).clamp(12.0, 45.0);

    allLines.sort((a, b) => a.boundingBox.top.compareTo(b.boundingBox.top));

    final groupedRows = <List<TextLine>>[];
    for (final line in allLines) {
      bool addedToGroup = false;
      for (final row in groupedRows) {
        final rowAvgTop =
            row.fold(0.0, (sum, l) => sum + l.boundingBox.top) / row.length;
        if ((line.boundingBox.top - rowAvgTop).abs() <= yTolerance) {
          row.add(line);
          addedToGroup = true;
          break;
        }
      }
      if (!addedToGroup) {
        groupedRows.add([line]);
      }
    }

    final buffer = StringBuffer();
    for (final row in groupedRows) {
      row.sort((a, b) => a.boundingBox.left.compareTo(b.boundingBox.left));
      final lineText = row.map((l) => l.text.trim()).join(' ');
      if (lineText.isNotEmpty) {
        buffer.writeln(lineText);
      }
    }

    return buffer.toString();
  }

  static String _extractPrintableStrings(List<int> bytes) {
    final buffer = StringBuffer();
    final currentWord = StringBuffer();

    for (final byte in bytes) {
      if ((byte >= 32 && byte <= 126) || byte == 10 || byte == 13) {
        currentWord.writeCharCode(byte);
      } else {
        if (currentWord.length >= 3) {
          final word = currentWord.toString().trim();
          if (word.isNotEmpty && word.contains(RegExp(r'[a-zA-Z0-9]'))) {
            buffer.writeln(word);
          }
        }
        currentWord.clear();
      }
    }
    if (currentWord.length >= 3) {
      final word = currentWord.toString().trim();
      if (word.isNotEmpty && word.contains(RegExp(r'[a-zA-Z0-9]'))) {
        buffer.writeln(word);
      }
    }
    return buffer.toString();
  }

  /// Validates text clarity and parses merchant, total, date/time, and categorized line items.
  static OcrResult parseReceiptText(
    String text, {
    String? imagePath,
    List<Category> availableCategories = const [],
  }) {
    final rawLines = text
        .split(RegExp(r'\r?\n'))
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();

    final contentLines = rawLines
        .where((l) => !RegExp(r'^---\s*RECEIPT SECTION').hasMatch(l))
        .toList();

    final contentJoined = contentLines.join(' ');
    final alnumCount = RegExp(r'[a-zA-Z0-9]').allMatches(contentJoined).length;
    final nonWhitespaceCount =
        contentJoined.replaceAll(RegExp(r'\s+'), '').length;
    final meaningfulWords =
        RegExp(r'[a-zA-Z0-9]{2,}').allMatches(contentJoined).length;

    if (nonWhitespaceCount < 12 || contentLines.length < 2) {
      throw const UnreadableReceiptException(
        message: 'Text is not clearly visible on this receipt image.',
        reasonCode: 'no_text',
        tip: 'Place the receipt flat in bright lighting and retake the photo.',
      );
    }

    final clarityRatio = alnumCount / max(1, nonWhitespaceCount);
    if (clarityRatio < 0.50 || alnumCount < 12 || meaningfulWords < 3) {
      throw const UnreadableReceiptException(
        message: 'The receipt text looks blurry or unreadable.',
        reasonCode: 'blurry_text',
        tip: 'Hold your phone steady, tap to focus on the text, and retake the photo.',
      );
    }

    // 1. Detect Merchant Name
    String? merchant;
    final merchantKeywords = [
      'MART',
      'SUPERMARKET',
      'HYPERMARKET',
      'MALL',
      'PETROL',
      'SHELL',
      'CALTEX',
      'PSO',
      'PARCO',
      'HOSPITAL',
      'CLINIC',
      'PHARMACY',
      'MEDICOS',
      'CAFE',
      'BAKERY',
      'STORE',
      'METRO',
      'CARREFOUR',
      'IMTIAZ',
      'AL-FATAH',
      'RESTAU',
      'GROCERY',
      'SCHOOL',
      'BOOKSHOP',
    ];

    for (final line in contentLines.take(8)) {
      final upper = line.toUpperCase();
      if (merchantKeywords.any((k) => upper.contains(k)) ||
          (line.length >= 3 &&
              line.length <= 42 &&
              RegExp(r'[a-zA-Z]{2,}').hasMatch(line) &&
              !RegExp(r'^\d+$').hasMatch(line) &&
              !upper.contains('DATE') &&
              !upper.contains('TIME') &&
              !upper.contains('INVOICE') &&
              !upper.contains('TEL'))) {
        merchant = line;
        break;
      }
    }
    merchant ??= contentLines.first;

    // 2. Detect Total Amount & Track Labeled Total Visibility
    final totalLabelRegExp = RegExp(
      r'\b(GRAND\s*TOTAL|NET\s*TOTAL|NET\s*VALUE|NET\s*AMOUNT|NET\s*PAYABLE|AMOUNT\s*DUE|TOTAL\s*AMOUNT|TOTAL\s*PAYABLE|BILL\s*AMOUNT|TOTAL)\b',
      caseSensitive: false,
    );
    final totalWithValueRegExp = RegExp(
      r'(?:GRAND\s*TOTAL|NET\s*TOTAL|NET\s*VALUE|NET\s*AMOUNT|NET\s*PAYABLE|AMOUNT\s*DUE|TOTAL\s*AMOUNT|TOTAL\s*PAYABLE|BILL\s*AMOUNT|TOTAL)\s*[:=]?\s*(?:RS\.?|PKR|\$|USD|EUR|GBP)?\s*([0-9,]+(?:\.[0-9]{1,2})?)(?:\s*/-)?',
      caseSensitive: false,
    );
    final currencyValueRegExp = RegExp(
      r'(?:RS\.?|PKR|\$|USD|EUR|GBP)\s*[:=]?\s*([0-9,]+(?:\.[0-9]{1,2})?)',
      caseSensitive: false,
    );

    double totalAmount = 0.0;
    bool hasTotalLabelLine = false;
    bool hasParsedLabeledTotal = false;

    for (int i = contentLines.length - 1; i >= 0; i--) {
      final line = contentLines[i];
      final upper = line.toUpperCase();
      if (upper.contains('TOTAL ITEMS') ||
          upper.contains('TOTAL QTY') ||
          upper.contains('SUBTOTAL') ||
          upper.contains('SUB TOTAL')) {
        continue;
      }
      if (totalLabelRegExp.hasMatch(line)) {
        hasTotalLabelLine = true;
        final match = totalWithValueRegExp.firstMatch(line);
        if (match != null) {
          final parsed =
              double.tryParse(match.group(1)?.replaceAll(',', '') ?? '');
          if (parsed != null && parsed > 0) {
            totalAmount = parsed;
            hasParsedLabeledTotal = true;
            break;
          }
        }
        // Check adjacent next line in case ML Kit split the label and amount vertically
        if (i + 1 < contentLines.length) {
          final nextNum = RegExp(
                  r'^(?:RS\.?|PKR|\$|USD)?\s*([0-9,]+(?:\.[0-9]{1,2})?)\s*(?:/-)?$',
                  caseSensitive: false)
              .firstMatch(contentLines[i + 1]);
          if (nextNum != null) {
            final parsed =
                double.tryParse(nextNum.group(1)?.replaceAll(',', '') ?? '');
            if (parsed != null && parsed > 0) {
              totalAmount = parsed;
              hasParsedLabeledTotal = true;
              break;
            }
          }
        }
      }
    }

    if (totalAmount == 0.0) {
      for (final line in contentLines.reversed) {
        final match = currencyValueRegExp.firstMatch(line);
        if (match != null) {
          final val = double.tryParse(match.group(1)!.replaceAll(',', ''));
          if (val != null && val > totalAmount && val <= 9999999) {
            totalAmount = val;
          }
        }
      }
    }

    if (totalAmount == 0.0) {
      final anyDecimal = RegExp(r'([0-9,]+\.[0-9]{2})');
      for (final line in contentLines) {
        final match = anyDecimal.firstMatch(line);
        if (match != null) {
          final val = double.tryParse(match.group(1)!.replaceAll(',', ''));
          if (val != null && val > totalAmount && val <= 9999999) {
            totalAmount = val;
          }
        }
      }
    }

    // 3. Detect Date & Time
    final dateRegExp =
        RegExp(r'(\d{4}[/-]\d{2}[/-]\d{2}|\d{1,2}[/-]\d{1,2}[/-]\d{2,4})');
    final timeRegExp = RegExp(
        r'\b([01]?\d|2[0-3]):([0-5]\d)(?::([0-5]\d))?\s*(AM|PM|am|pm)?\b');

    String dateIso = DateTime.now().toIso8601String().split('T').first;
    String? timeString;
    int parsedYear = DateTime.now().year;
    int parsedMonth = DateTime.now().month;
    int parsedDay = DateTime.now().day;
    int parsedHour = DateTime.now().hour;
    int parsedMinute = DateTime.now().minute;
    bool hasParsedDate = false;
    bool hasParsedTime = false;

    for (final line in contentLines) {
      if (!hasParsedDate) {
        final dateMatch = dateRegExp.firstMatch(line);
        if (dateMatch != null) {
          final rawDateStr = dateMatch.group(1)!;
          try {
            final parts = rawDateStr.split(RegExp(r'[/-]'));
            if (parts.length == 3) {
              if (parts[0].length == 4) {
                parsedYear = int.parse(parts[0]);
                parsedMonth = int.parse(parts[1]);
                parsedDay = int.parse(parts[2]);
              } else {
                final val1 = int.parse(parts[0]);
                final val2 = int.parse(parts[1]);
                var yr = int.parse(parts[2]);
                if (yr < 100) yr += 2000;
                parsedYear = yr;
                if (val1 > 12) {
                  parsedDay = val1;
                  parsedMonth = val2;
                } else {
                  parsedMonth = val1;
                  parsedDay = val2;
                }
              }
              if (parsedMonth >= 1 &&
                  parsedMonth <= 12 &&
                  parsedDay >= 1 &&
                  parsedDay <= 31) {
                dateIso =
                    '$parsedYear-${parsedMonth.toString().padLeft(2, '0')}-${parsedDay.toString().padLeft(2, '0')}';
                hasParsedDate = true;
              }
            }
          } catch (_) {}
        }
      }

      if (!hasParsedTime) {
        final timeMatch = timeRegExp.firstMatch(line);
        if (timeMatch != null) {
          var hr = int.tryParse(timeMatch.group(1) ?? '') ?? 0;
          final min = int.tryParse(timeMatch.group(2) ?? '') ?? 0;
          final ampm = timeMatch.group(4)?.toUpperCase();

          if (ampm == 'PM' && hr < 12) hr += 12;
          if (ampm == 'AM' && hr == 12) hr = 0;

          parsedHour = hr;
          parsedMinute = min;
          timeString =
              '${hr.toString().padLeft(2, '0')}:${min.toString().padLeft(2, '0')}';
          hasParsedTime = true;
        }
      }
    }

    final fullDateTime = DateTime(
        parsedYear, parsedMonth, parsedDay, parsedHour, parsedMinute);

    // 4. Parse Line Items (Decimals + Whole-Number Currencies + Quantities)
    final parsedItems = <OcrLineItem>[];
    int missingPriceMiddleLines = 0;

    final leadingQtyRegExp = RegExp(
      r'^\s*(\d+(?:\.\d+)?)\s*[xX*]\s+(.+?)\s+(?:RS\.?|PKR|\$|USD|EUR|GBP)?\s*([0-9,]+(?:\.[0-9]{1,2})?)\s*(?:/-)?\s*$',
      caseSensitive: false,
    );
    final trailingQtyRegExp = RegExp(
      r'^(.+?)\s+[xX*]\s*(\d+(?:\.\d+)?)\s+(?:RS\.?|PKR|\$|USD|EUR|GBP)?\s*([0-9,]+(?:\.[0-9]{1,2})?)\s*(?:/-)?\s*$',
      caseSensitive: false,
    );
    final atPriceRegExp = RegExp(
      r'^(.+?)\s+(\d+(?:\.\d+)?)\s*[a-zA-Z]{0,3}\s*@\s*(?:RS\.?|PKR|\$|USD)?\s*([0-9,]+(?:\.[0-9]{1,2})?)(?:\s+(?:RS\.?|PKR|\$|USD)?\s*([0-9,]+(?:\.[0-9]{1,2})?))?\s*(?:/-)?\s*$',
      caseSensitive: false,
    );
    final generalItemRegExp = RegExp(
      r'^(.+?)\s+(?:(?:RS\.?|PKR|\$|USD|EUR|GBP)\s*([0-9,]+(?:\.[0-9]{1,2})?)\s*(?:/-)?|([0-9,]+\.[0-9]{2})\s*(?:/-)?|([0-9,]+)\s*/-|([1-9][0-9,]{0,5}))\s*$',
      caseSensitive: false,
    );

    for (int i = 0; i < contentLines.length; i++) {
      final line = contentLines[i];
      final upper = line.toUpperCase();
      if (_isNonItemLine(upper)) continue;

      String? itemName;
      double? amt;
      double qty = 1.0;

      final leadMatch = leadingQtyRegExp.firstMatch(line);
      if (leadMatch != null) {
        qty = double.tryParse(leadMatch.group(1)!) ?? 1.0;
        itemName = leadMatch.group(2)!.trim();
        amt = double.tryParse(leadMatch.group(3)!.replaceAll(',', ''));
      } else {
        final trailMatch = trailingQtyRegExp.firstMatch(line);
        if (trailMatch != null) {
          itemName = trailMatch.group(1)!.trim();
          qty = double.tryParse(trailMatch.group(2)!) ?? 1.0;
          amt = double.tryParse(trailMatch.group(3)!.replaceAll(',', ''));
        } else {
          final atMatch = atPriceRegExp.firstMatch(line);
          if (atMatch != null) {
            itemName = atMatch.group(1)!.trim();
            final unitQty = double.tryParse(atMatch.group(2)!) ?? 1.0;
            final unitPrice =
                double.tryParse(atMatch.group(3)!.replaceAll(',', ''));
            final lineTotal = atMatch.group(4) != null
                ? double.tryParse(atMatch.group(4)!.replaceAll(',', ''))
                : null;
            if (lineTotal != null && lineTotal > 0) {
              qty = unitQty;
              amt = lineTotal / max(1.0, unitQty);
            } else if (unitPrice != null && unitPrice > 0) {
              qty = unitQty;
              amt = unitPrice;
            }
          } else {
            final genMatch = generalItemRegExp.firstMatch(line);
            if (genMatch != null) {
              itemName = genMatch.group(1)!.trim();
              final amtStr = (genMatch.group(2) ??
                      genMatch.group(3) ??
                      genMatch.group(4) ??
                      genMatch.group(5))
                  ?.replaceAll(',', '');
              amt = amtStr != null ? double.tryParse(amtStr) : null;
            }
          }
        }
      }

      if (itemName != null &&
          amt != null &&
          amt > 0 &&
          amt <= 9999999 &&
          RegExp(r'[a-zA-Z]{2,}').hasMatch(itemName) &&
          itemName.length >= 2 &&
          !dateRegExp.hasMatch(line)) {
        parsedItems.add(OcrLineItem(
          name: itemName,
          amount: amt,
          quantity: qty > 0 ? qty : 1.0,
        ));
      } else if (i >= 1 && i < contentLines.length - 1) {
        final looksPriceHintMissing = RegExp(
              r'(\bRS\b|\bPKR\b|\$|/-|@|\bx\d+\b)',
              caseSensitive: false,
            ).hasMatch(line) ||
            (RegExp(r'^[a-zA-Z][a-zA-Z0-9\s\-&]{3,}$').hasMatch(line) &&
                !upper.contains(merchant.toUpperCase()));
        if (looksPriceHintMissing) {
          missingPriceMiddleLines++;
        }
      }
    }

    // Normalize line totals vs unit prices when quantity > 1
    var items = parsedItems;
    if (totalAmount > 0 && items.any((item) => item.quantity > 1.0)) {
      final sumWithQty =
          items.fold(0.0, (s, item) => s + (item.amount * item.quantity));
      final sumRaw = items.fold(0.0, (s, item) => s + item.amount);
      if ((sumRaw - totalAmount).abs() <= max(5.0, totalAmount * 0.25) &&
          (sumWithQty - totalAmount).abs() >
              (sumRaw - totalAmount).abs() * 1.5) {
        items = items
            .map((item) => item.quantity > 1.0
                ? item.copyWith(amount: item.amount / item.quantity)
                : item)
            .toList();
      }
    }

    // 5. Reject Cut-Off / No-Amount Receipts Before Categorizing
    if (hasTotalLabelLine && !hasParsedLabeledTotal && items.isEmpty) {
      throw const UnreadableReceiptException(
        message: 'The total amount appears cut off or unreadable.',
        reasonCode: 'partial_cut_off',
        tip: 'Zoom out slightly so the entire width and bottom of the receipt are visible, then retake.',
      );
    }

    if (totalAmount <= 0 && items.isEmpty) {
      throw const UnreadableReceiptException(
        message: 'Prices and total amount are not visible on this image.',
        reasonCode: 'no_amounts',
        tip: 'Make sure item prices and the total amount are clearly visible inside the frame and retake.',
      );
    }

    final double itemsSum =
        items.fold(0.0, (sum, item) => sum + (item.amount * item.quantity));

    if (hasParsedLabeledTotal &&
        totalAmount > 0 &&
        items.isNotEmpty &&
        itemsSum < totalAmount * 0.45 &&
        missingPriceMiddleLines >= 2) {
      throw const UnreadableReceiptException(
        message: 'Some receipt items or prices are not fully visible.',
        reasonCode: 'partial_cut_off',
        tip: 'Ensure the full receipt from top to bottom and left to right is visible, or scan it in clear sections.',
      );
    }

    if (totalAmount <= 0 && itemsSum > 0) {
      totalAmount = itemsSum;
    }

    if (items.isEmpty && totalAmount > 0) {
      items = [OcrLineItem(name: merchant, amount: totalAmount, quantity: 1.0)];
    }

    // 6. Auto-Match Receipt & Every Individual Line Item to Real Categories & Subcategories
    final receiptMatch = matchCategoryForItem(
      '$merchant\n$contentJoined',
      merchant: merchant,
      availableCategories: availableCategories,
    );

    final categorizedItems = items.map((item) {
      final match = matchCategoryForItem(
        item.name,
        merchant: merchant,
        availableCategories: availableCategories,
      );
      return item.copyWith(
        categoryId: match.categoryId,
        categoryName: match.categoryName,
        subcategoryId: match.subcategoryId,
        subcategoryName: match.subcategoryName,
        classification: match.classification,
      );
    }).toList();

    final primaryItemMatch = categorizedItems.isNotEmpty
        ? categorizedItems.first
        : null;

    return OcrResult(
      merchant: merchant,
      totalAmount: totalAmount,
      dateIso: dateIso,
      timeString: timeString,
      fullDateTime: fullDateTime,
      suggestedCategoryId:
          primaryItemMatch?.categoryId ?? receiptMatch.categoryId,
      suggestedCategoryName:
          primaryItemMatch?.categoryName ?? receiptMatch.categoryName,
      suggestedSubcategoryId:
          primaryItemMatch?.subcategoryId ?? receiptMatch.subcategoryId,
      suggestedSubcategoryName:
          primaryItemMatch?.subcategoryName ?? receiptMatch.subcategoryName,
      lineItems: categorizedItems,
      rawText: text,
      confidence: min(0.98, 0.72 + (clarityRatio * 0.26)),
    );
  }

  static bool _isNonItemLine(String upperLine) {
    for (final kw in _nonItemKeywords) {
      if (upperLine.contains(kw)) return true;
    }
    return false;
  }

  static String _generateSampleTextForPath(String path) {
    final todayIso = DateTime.now().toIso8601String().split('T').first;
    final lower = path.toLowerCase();
    if (lower.contains('petrol') || lower.contains('fuel')) {
      return '''
SHELL PETROL PUMP
Station #45, Main Blvd
Date: $todayIso  Time: 14:30
Super Fuel 25L @ 280.00
TOTAL: 7000.00
Payment: Cash
Thank you for visiting Shell!
''';
    } else if (lower.contains('hospital') || lower.contains('medical')) {
      return '''
CITY GENERAL HOSPITAL & PHARMACY
OPD Receipt & Consultation Fee
Date: $todayIso  Time: 11:15 AM
Doctor Consultation  1500.00
Medicines x1          850.00
GRAND TOTAL: 2350.00
Payment: Card
''';
    } else if (lower.contains('mall') || lower.contains('shop')) {
      return '''
CENTRAL SHOPPING MALL
Fashion Retail Outlet
Date: $todayIso  Time: 18:45
Casual Shirt x1      2500.00
Denim Jeans x1       3800.00
NET TOTAL: 6300.00
''';
    } else {
      return '''
METRO CASH & CARRY
Invoice #984512
Date: $todayIso  Time: 16:20:10
Milk Pack 1L x2       450.00
Cooking Oil 5L x1    2200.00
Fresh Vegetables     850.00
TOTAL: 3500.00
Thank you for shopping!
''';
    }
  }
}
