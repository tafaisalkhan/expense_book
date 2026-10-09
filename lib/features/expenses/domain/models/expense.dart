import 'package:myexpence/features/expenses/domain/models/expense_classification.dart';
import 'package:myexpence/features/expenses/domain/models/payment_method.dart';
import 'dart:convert';
import 'package:myexpence/features/expenses/domain/models/expense_allocation.dart';

class Expense {
  final int? id;
  final String uuid;
  final double amount;
  final String currency;
  final String categoryId;
  final String? subcategoryId;
  final String? personId; // null = Household
  final ExpenseClassification classification;
  final String expenseDate; // YYYY-MM-DD (Mandatory separate transaction date)
  final String? expenseTime; // HH:mm
  final String createdAt; // ISO 8601 record creation time
  final String updatedAt; // ISO 8601 modification time
  final String? merchant;
  final String? description;
  final PaymentMethod paymentMethod;
  final String? locationId;
  final String? receiptId;
  final String? recurringOccurrenceId;
  final String? notes;
  final ExpenseStatus status;
  final bool isDeleted;
  final List<ExpenseAllocation> allocations;

  const Expense({
    this.id,
    required this.uuid,
    required this.amount,
    this.currency = 'Rs',
    required this.categoryId,
    this.subcategoryId,
    this.personId,
    required this.classification,
    required this.expenseDate,
    this.expenseTime,
    required this.createdAt,
    required this.updatedAt,
    this.merchant,
    this.description,
    this.paymentMethod = PaymentMethod.cash,
    this.locationId,
    this.receiptId,
    this.recurringOccurrenceId,
    this.notes,
    this.status = ExpenseStatus.paid,
    this.isDeleted = false,
    this.allocations = const [],
  });

  Expense copyWith({
    int? id,
    String? uuid,
    double? amount,
    String? currency,
    String? categoryId,
    String? subcategoryId,
    String? personId,
    ExpenseClassification? classification,
    String? expenseDate,
    String? expenseTime,
    String? createdAt,
    String? updatedAt,
    String? merchant,
    String? description,
    PaymentMethod? paymentMethod,
    String? locationId,
    String? receiptId,
    String? recurringOccurrenceId,
    String? notes,
    ExpenseStatus? status,
    bool? isDeleted,
    List<ExpenseAllocation>? allocations,
  }) {
    return Expense(
      id: id ?? this.id,
      uuid: uuid ?? this.uuid,
      amount: amount ?? this.amount,
      currency: currency ?? this.currency,
      categoryId: categoryId ?? this.categoryId,
      subcategoryId: subcategoryId ?? this.subcategoryId,
      personId: personId ?? this.personId,
      classification: classification ?? this.classification,
      expenseDate: expenseDate ?? this.expenseDate,
      expenseTime: expenseTime ?? this.expenseTime,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      merchant: merchant ?? this.merchant,
      description: description ?? this.description,
      paymentMethod: paymentMethod ?? this.paymentMethod,
      locationId: locationId ?? this.locationId,
      receiptId: receiptId ?? this.receiptId,
      recurringOccurrenceId:
          recurringOccurrenceId ?? this.recurringOccurrenceId,
      notes: notes ?? this.notes,
      status: status ?? this.status,
      isDeleted: isDeleted ?? this.isDeleted,
      allocations: allocations ?? this.allocations,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'uuid': uuid,
      'amount': amount,
      'currency': currency,
      'categoryId': categoryId,
      'subcategoryId': subcategoryId,
      'personId': personId,
      'classification': classification.code,
      'expenseDate': expenseDate,
      'expenseTime': expenseTime,
      'createdAt': createdAt,
      'updatedAt': updatedAt,
      'merchant': merchant,
      'description': description,
      'paymentMethod': paymentMethod.code,
      'locationId': locationId,
      'receiptId': receiptId,
      'recurringOccurrenceId': recurringOccurrenceId,
      'notes': notes,
      'status': status.code,
      'isDeleted': isDeleted ? 1 : 0,
      'allocationsJson': jsonEncode(allocations.map((a) => a.toMap()).toList()),
    };
  }

  factory Expense.fromMap(Map<String, dynamic> map) {
    return Expense(
      id: map['id'] as int?,
      uuid: map['uuid'] as String,
      amount: (map['amount'] as num).toDouble(),
      currency: (map['currency'] as String?) ?? 'Rs',
      categoryId: map['categoryId'] as String,
      subcategoryId: map['subcategoryId'] as String?,
      personId: map['personId'] as String?,
      classification:
          ExpenseClassification.fromCode(map['classification'] as String),
      expenseDate: map['expenseDate'] as String,
      expenseTime: map['expenseTime'] as String?,
      createdAt: map['createdAt'] as String,
      updatedAt: map['updatedAt'] as String,
      merchant: map['merchant'] as String?,
      description: map['description'] as String?,
      paymentMethod:
          PaymentMethod.fromCode((map['paymentMethod'] as String?) ?? 'Cash'),
      locationId: map['locationId'] as String?,
      receiptId: map['receiptId'] as String?,
      recurringOccurrenceId: map['recurringOccurrenceId'] as String?,
      notes: map['notes'] as String?,
      status: ExpenseStatus.fromCode((map['status'] as String?) ?? 'PAID'),
      isDeleted: (map['isDeleted'] as int) == 1,
      allocations: _allocationsFromJson(map['allocationsJson'] as String?),
    );
  }

  static List<ExpenseAllocation> _allocationsFromJson(String? value) {
    if (value == null || value.isEmpty) return const [];
    try {
      return (jsonDecode(value) as List)
          .map((item) =>
              ExpenseAllocation.fromMap(Map<String, dynamic>.from(item as Map)))
          .toList();
    } catch (_) {
      return const [];
    }
  }
}
