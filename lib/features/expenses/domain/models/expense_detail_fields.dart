/// Optional fields shown for each existing expense category.
class ExpenseDetailField {
  final String key;
  final String label;
  final bool isNumber;

  const ExpenseDetailField(this.key, this.label, {this.isNumber = false});
}

/// Quantity and a unit price describe goods bought by count, weight, or volume.
/// Fees, services, and bills are entered as a single amount.
bool expenseUsesQuantity(String categoryId, String? subcategoryId) {
  final sub = subcategoryId ?? '';
  switch (categoryId) {
    case 'cat_groceries':
    case 'cat_food':
    case 'cat_stationery':
    case 'cat_shopping':
      return true;
    case 'cat_car':
      return const {'sub_car_fuel', 'sub_car_tyres', 'sub_car_battery'}
          .contains(sub);
    case 'cat_transport':
      return sub == 'sub_trsp_fuel';
    case 'cat_house':
      return const {'sub_house_furniture', 'sub_house_appliances'}
          .contains(sub);
    case 'cat_education':
      return const {'sub_edu_books', 'sub_edu_uniform'}.contains(sub);
    case 'cat_clothing':
      return sub == 'sub_cloth_purchases';
    case 'cat_health':
      return sub == 'sub_hlth_med';
    case 'cat_personal':
      return sub == 'sub_pers_clothing';
    default:
      return false;
  }
}

String? expenseDetailsValidationError(
    String categoryId, String? subcategoryId, Map<String, dynamic> details) {
  for (final field in expenseDetailFields(categoryId, subcategoryId)) {
    if (!field.isNumber) continue;
    final value = details[field.key]?.toString().trim() ?? '';
    if (value.isEmpty) continue;
    final parsed = double.tryParse(value);
    if (parsed == null || !parsed.isFinite || parsed < 0) {
      return '${field.label} must be a valid, non-negative number';
    }
  }
  return null;
}

List<ExpenseDetailField> expenseDetailFields(
    String categoryId, String? subcategoryId) {
  final sub = subcategoryId ?? '';
  switch (categoryId) {
    case 'cat_car':
      if (sub == 'sub_car_repair') {
        return const [
          ExpenseDetailField('vehicle', 'Vehicle'),
          ExpenseDetailField('partsCost', 'Parts cost', isNumber: true),
          ExpenseDetailField('laborCost', 'Labor cost', isNumber: true),
        ];
      }
      if (sub == 'sub_car_insurance' || sub == 'sub_car_reg') {
        return const [
          ExpenseDetailField('vehicle', 'Vehicle'),
          ExpenseDetailField('period', 'Coverage or registration period'),
          ExpenseDetailField('reference', 'Policy or registration number'),
        ];
      }
      return const [
        ExpenseDetailField('vehicle', 'Vehicle'),
        ExpenseDetailField('provider', 'Service or fuel station'),
      ];
    case 'cat_education':
      final fields = <ExpenseDetailField>[
        const ExpenseDetailField('student', 'Student'),
        const ExpenseDetailField('school', 'School or institution'),
      ];
      if (sub == 'sub_edu_exam') {
        fields.add(const ExpenseDetailField('exam', 'Exam name'));
      } else if (sub == 'sub_edu_monthly' ||
          sub == 'sub_edu_annual' ||
          sub == 'sub_edu_tuition' ||
          sub == 'sub_edu_transport') {
        fields.add(const ExpenseDetailField('period', 'Fee month or term'));
      } else {
        fields
            .add(const ExpenseDetailField('itemOrService', 'Item or activity'));
      }
      return fields;
    case 'cat_house':
      if (sub == 'sub_house_rent') {
        return const [
          ExpenseDetailField('period', 'Rent month'),
          ExpenseDetailField('landlord', 'Landlord'),
        ];
      }
      if (sub == 'sub_house_repair') {
        return const [
          ExpenseDetailField('partsCost', 'Parts cost', isNumber: true),
          ExpenseDetailField('laborCost', 'Labor cost', isNumber: true),
        ];
      }
      return const [ExpenseDetailField('itemOrService', 'Item or service')];
    case 'cat_utilities':
      return [
        ExpenseDetailField('period', 'Billing month'),
        ExpenseDetailField('reference', 'Account or bill number'),
        ExpenseDetailField('dueDate', 'Due date'),
        if (const {'sub_util_elec', 'sub_util_gas', 'sub_util_water'}
            .contains(sub)) ...const [
          ExpenseDetailField('previousReading', 'Previous meter reading',
              isNumber: true),
          ExpenseDetailField('currentReading', 'Current meter reading',
              isNumber: true),
        ],
      ];
    case 'cat_groceries':
    case 'cat_food':
      return const [];
    case 'cat_stationery':
      return const [ExpenseDetailField('itemOrService', 'Item or service')];
    case 'cat_clothing':
      return const [ExpenseDetailField('itemOrService', 'Garment or service')];
    case 'cat_health':
      return [
        const ExpenseDetailField('patient', 'Patient'),
        const ExpenseDetailField('provider', 'Doctor or clinic'),
        ExpenseDetailField(
            'serviceName',
            sub == 'sub_hlth_test' || sub == 'sub_hlth_lab'
                ? 'Test name'
                : sub == 'sub_hlth_med'
                    ? 'Medicine name'
                    : 'Visit or treatment'),
      ];
    case 'cat_transport':
      return const [
        ExpenseDetailField('from', 'From'),
        ExpenseDetailField('to', 'To'),
        ExpenseDetailField('route', 'Operator or route'),
      ];
    case 'cat_shopping':
      return [
        const ExpenseDetailField('itemOrService', 'Item name'),
        if (sub == 'sub_shop_elec')
          const ExpenseDetailField('warranty', 'Warranty information'),
      ];
    case 'cat_entertainment':
      return sub == 'sub_ent_subs'
          ? const [ExpenseDetailField('period', 'Subscription period')]
          : const [ExpenseDetailField('event', 'Event or activity name')];
    case 'cat_personal':
      return const [ExpenseDetailField('itemOrService', 'Service name')];
    case 'cat_charity':
      return const [
        ExpenseDetailField('recipient', 'Recipient'),
        ExpenseDetailField('purpose', 'Purpose'),
      ];
    case 'cat_travel':
      return const [
        ExpenseDetailField('destination', 'Destination'),
        ExpenseDetailField('tripDate', 'Trip date'),
        ExpenseDetailField('reference', 'Booking reference'),
      ];
    default:
      return const [ExpenseDetailField('itemOrService', 'Description')];
  }
}

String expenseDetailsSummary(
    String categoryId, String? subcategoryId, Map<String, dynamic> details) {
  return expenseDetailFields(categoryId, subcategoryId)
      .where(
          (field) => (details[field.key]?.toString().trim() ?? '').isNotEmpty)
      .map((field) => '${field.label}: ${details[field.key]}')
      .join(' • ');
}
