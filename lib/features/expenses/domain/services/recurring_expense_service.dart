import 'dart:convert';

import 'package:myexpence/core/database/app_database.dart';
import 'package:myexpence/features/expenses/domain/models/expense.dart';
import 'package:myexpence/features/expenses/domain/models/recurring_expense.dart';
import 'package:uuid/uuid.dart';
import 'package:sqflite/sqflite.dart';

class RecurringExpenseService {
  final AppDatabase appDatabase;
  const RecurringExpenseService(this.appDatabase);

  Future<void> saveSchedule({
    required Expense template,
    required RecurrenceFrequency frequency,
    required int intervalDays,
    String? existingScheduleId,
  }) async {
    final db = await appDatabase.database;
    final now = DateTime.now();
    final scheduleId = existingScheduleId ?? const Uuid().v4();
    final firstDue =
        _firstDueDate(template.expenseDate, frequency, intervalDays);
    final schedule = RecurringExpense(
      uuid: scheduleId,
      templateJson:
          jsonEncode(template.copyWith(id: null).toMap()..remove('id')),
      frequency: frequency,
      intervalDays: intervalDays.clamp(1, 365),
      dayOfMonth: frequency == RecurrenceFrequency.monthly
          ? DateTime.parse(template.expenseDate).day
          : null,
      nextDueDate: _isoDate(firstDue),
      createdAt: now.toIso8601String(),
      updatedAt: now.toIso8601String(),
    );
    await db.insert('recurring_expenses', schedule.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> disableSchedule(String scheduleId) async {
    final db = await appDatabase.database;
    await db.update(
      'recurring_expenses',
      {'isActive': 0, 'updatedAt': DateTime.now().toIso8601String()},
      where: 'uuid = ?',
      whereArgs: [scheduleId],
    );
  }

  /// Creates all due occurrences as pending. The deterministic occurrence ID
  /// and unique database index make this safe to call on every app resume.
  Future<int> generateDueExpenses({DateTime? through}) async {
    final db = await appDatabase.database;
    final end = DateTime(
        through?.year ?? DateTime.now().year,
        through?.month ?? DateTime.now().month,
        through?.day ?? DateTime.now().day);
    final rows = await db.query('recurring_expenses', where: 'isActive = 1');
    var created = 0;

    for (final row in rows) {
      final schedule = RecurringExpense.fromMap(row);
      var due = DateTime.parse(schedule.nextDueDate);
      while (!due.isAfter(end)) {
        final templateMap =
            Map<String, dynamic>.from(jsonDecode(schedule.templateJson) as Map);
        templateMap.remove('id');
        templateMap['uuid'] = const Uuid().v4();
        templateMap['expenseDate'] = _isoDate(due);
        templateMap['createdAt'] = DateTime.now().toIso8601String();
        templateMap['updatedAt'] = DateTime.now().toIso8601String();
        templateMap['status'] = 'PENDING';
        templateMap['isDeleted'] = 0;
        templateMap['recurringOccurrenceId'] =
            '${schedule.uuid}:${_isoDate(due)}';
        try {
          final insertedId = await db.insert('expenses', templateMap,
              conflictAlgorithm: ConflictAlgorithm.ignore);
          if (insertedId != 0) created++;
        } catch (_) {}
        due = _nextDate(due, schedule);
      }
      await db.update(
        'recurring_expenses',
        {
          'nextDueDate': _isoDate(due),
          'updatedAt': DateTime.now().toIso8601String()
        },
        where: 'uuid = ?',
        whereArgs: [schedule.uuid],
      );
    }
    return created;
  }

  static DateTime _firstDueDate(
      String selectedDate, RecurrenceFrequency frequency, int interval) {
    final date = DateTime.parse(selectedDate);
    final today = DateTime.now();
    final normalizedToday = DateTime(today.year, today.month, today.day);
    if (date.isAfter(normalizedToday)) return date;
    if (frequency == RecurrenceFrequency.monthly) {
      return _safeMonthDate(
          normalizedToday.year, normalizedToday.month + 1, date.day);
    }
    return date.add(Duration(
        days: frequency == RecurrenceFrequency.daily
            ? 1
            : interval.clamp(1, 365)));
  }

  static DateTime _nextDate(DateTime date, RecurringExpense schedule) {
    if (schedule.frequency == RecurrenceFrequency.monthly) {
      return _safeMonthDate(
          date.year, date.month + 1, schedule.dayOfMonth ?? date.day);
    }
    return date.add(Duration(
        days: schedule.frequency == RecurrenceFrequency.daily
            ? 1
            : schedule.intervalDays));
  }

  static DateTime _safeMonthDate(int year, int month, int day) {
    final first = DateTime(year, month, 1);
    final lastDay = DateTime(first.year, first.month + 1, 0).day;
    return DateTime(first.year, first.month, day.clamp(1, lastDay));
  }

  static String _isoDate(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
}
