enum ExpenseClassification {
  urgent('URGENT', 'Urgent', 'Time-sensitive expenses that need immediate attention'),
  required('REQUIRED', 'Required', 'Commitments and necessary expenses'),
  optional('OPTIONAL', 'Optional',
      'Discretionary expenses and potential savings areas'),
  lost('LOST', 'Lost', 'Unaccounted, misplaced, or lost funds');

  final String code;
  final String label;
  final String description;

  const ExpenseClassification(this.code, this.label, this.description);

  static ExpenseClassification fromCode(String code) {
    if (code == 'NEED') return ExpenseClassification.required;
    return ExpenseClassification.values.firstWhere(
      (e) => e.code == code,
      orElse: () => ExpenseClassification.required,
    );
  }
}
