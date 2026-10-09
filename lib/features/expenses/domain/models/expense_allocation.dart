class ExpenseAllocation {
  final String personId;
  final String personName;
  final double percentage;
  final double amount;

  const ExpenseAllocation({
    required this.personId,
    required this.personName,
    required this.percentage,
    required this.amount,
  });

  Map<String, dynamic> toMap() => {
        'personId': personId,
        'personName': personName,
        'percentage': percentage,
        'amount': amount,
      };

  factory ExpenseAllocation.fromMap(Map<String, dynamic> map) =>
      ExpenseAllocation(
        personId: map['personId'] as String,
        personName: (map['personName'] as String?) ?? '',
        percentage: (map['percentage'] as num).toDouble(),
        amount: (map['amount'] as num).toDouble(),
      );
}
