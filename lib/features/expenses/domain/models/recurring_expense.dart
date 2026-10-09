enum RecurrenceFrequency { daily, everyNDays, monthly }

class RecurringExpense {
  final String uuid;
  final String templateJson;
  final RecurrenceFrequency frequency;
  final int intervalDays;
  final int? dayOfMonth;
  final String nextDueDate;
  final bool isActive;
  final String createdAt;
  final String updatedAt;

  const RecurringExpense({
    required this.uuid,
    required this.templateJson,
    required this.frequency,
    this.intervalDays = 1,
    this.dayOfMonth,
    required this.nextDueDate,
    this.isActive = true,
    required this.createdAt,
    required this.updatedAt,
  });

  Map<String, dynamic> toMap() => {
        'uuid': uuid,
        'templateJson': templateJson,
        'frequency': frequency.name,
        'intervalDays': intervalDays,
        'dayOfMonth': dayOfMonth,
        'nextDueDate': nextDueDate,
        'isActive': isActive ? 1 : 0,
        'createdAt': createdAt,
        'updatedAt': updatedAt,
      };

  factory RecurringExpense.fromMap(Map<String, dynamic> map) =>
      RecurringExpense(
        uuid: map['uuid'] as String,
        templateJson: map['templateJson'] as String,
        frequency: RecurrenceFrequency.values.firstWhere(
          (value) => value.name == map['frequency'],
          orElse: () => RecurrenceFrequency.daily,
        ),
        intervalDays: (map['intervalDays'] as int?) ?? 1,
        dayOfMonth: map['dayOfMonth'] as int?,
        nextDueDate: map['nextDueDate'] as String,
        isActive: (map['isActive'] as int? ?? 1) == 1,
        createdAt: map['createdAt'] as String,
        updatedAt: map['updatedAt'] as String,
      );
}
