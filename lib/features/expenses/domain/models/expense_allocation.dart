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

  static List<ExpenseAllocation>? resolve(
    List<ExpenseAllocation> shares,
    double totalAmount, {
    required bool byPercentage,
  }) {
    if (shares.isEmpty) return const [];
    if (totalAmount <= 0 || !totalAmount.isFinite) return null;
    final sum = shares.fold<double>(
      0,
      (total, share) => total +
          (byPercentage ? share.percentage : share.amount),
    );
    if ((sum - (byPercentage ? 100 : totalAmount)).abs() > 0.01) {
      return null;
    }
    if (!byPercentage) return shares;

    final result = <ExpenseAllocation>[];
    var assigned = 0.0;
    for (var index = 0; index < shares.length; index++) {
      final share = shares[index];
      final amount = index == shares.length - 1
          ? totalAmount - assigned
          : (totalAmount * share.percentage).round() / 100;
      assigned += amount;
      result.add(ExpenseAllocation(
        personId: share.personId,
        personName: share.personName,
        percentage: share.percentage,
        amount: amount,
      ));
    }
    return result;
  }

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
