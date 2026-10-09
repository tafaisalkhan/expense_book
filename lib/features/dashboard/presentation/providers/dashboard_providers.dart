import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:myexpence/core/providers/core_providers.dart';
import 'package:myexpence/core/utils/date_formatters.dart';
import 'package:myexpence/features/expenses/domain/models/expense.dart';
import 'package:myexpence/features/expenses/domain/models/expense_classification.dart';

enum DashboardTimeframe { day, week, month, year }

class TrendPoint {
  final double x;
  final String label;
  final double amount;
  final DateTime date;

  const TrendPoint({
    required this.x,
    required this.label,
    required this.amount,
    required this.date,
  });
}

class DashboardData {
  final DashboardTimeframe selectedTimeframe;
  final double periodTotal;
  final double previousPeriodTotal;
  final double averagePerDay;
  final List<TrendPoint> trendPoints;
  final Map<String, double> categoryBreakdown;
  final Map<ExpenseClassification, double> classificationBreakdown;
  final Map<String, double> personBreakdown;
  final String topCategoryName;
  final double topCategoryAmount;
  final String highestSpendDayLabel;
  final double highestSpendDayAmount;
  final double todayTotal;
  final double yesterdayTotal;
  final double monthTotal;
  final bool isZeroSpendConfirmedToday;
  final List<Expense> periodExpenses;

  const DashboardData({
    required this.selectedTimeframe,
    required this.periodTotal,
    required this.previousPeriodTotal,
    required this.averagePerDay,
    required this.trendPoints,
    required this.categoryBreakdown,
    required this.classificationBreakdown,
    required this.personBreakdown,
    required this.topCategoryName,
    required this.topCategoryAmount,
    required this.highestSpendDayLabel,
    required this.highestSpendDayAmount,
    required this.todayTotal,
    required this.yesterdayTotal,
    required this.monthTotal,
    required this.isZeroSpendConfirmedToday,
    required this.periodExpenses,
  });
}

final dashboardTimeframeProvider =
    StateProvider<DashboardTimeframe>((ref) => DashboardTimeframe.month);

final dashboardDataProvider = FutureProvider<DashboardData>((ref) async {
  final repo = ref.watch(expenseRepositoryProvider);
  final timeframe = ref.watch(dashboardTimeframeProvider);

  final now = DateTime.now();
  final todayIso = DateFormatters.todayIso();
  final yesterdayIso = DateFormatters.yesterdayIso();

  // 1. Compute Start & End dates for selected timeframe & previous period
  DateTime startDate;
  DateTime endDate;
  DateTime prevStartDate;
  DateTime prevEndDate;

  switch (timeframe) {
    case DashboardTimeframe.day:
      startDate = DateTime(now.year, now.month, now.day);
      endDate = startDate;
      prevStartDate = startDate.subtract(const Duration(days: 1));
      prevEndDate = prevStartDate;
      break;

    case DashboardTimeframe.week:
      startDate = now.subtract(Duration(days: now.weekday - 1)); // Mon
      startDate = DateTime(startDate.year, startDate.month, startDate.day);
      endDate = startDate.add(const Duration(days: 6)); // Sun
      prevStartDate = startDate.subtract(const Duration(days: 7));
      prevEndDate = startDate.subtract(const Duration(days: 1));
      break;

    case DashboardTimeframe.month:
      startDate = DateTime(now.year, now.month, 1);
      endDate = DateTime(now.year, now.month + 1, 0);
      prevStartDate = DateTime(now.year, now.month - 1, 1);
      prevEndDate = DateTime(now.year, now.month, 0);
      break;

    case DashboardTimeframe.year:
      startDate = DateTime(now.year, 1, 1);
      endDate = DateTime(now.year, 12, 31);
      prevStartDate = DateTime(now.year - 1, 1, 1);
      prevEndDate = DateTime(now.year - 1, 12, 31);
      break;
  }

  final startIso = DateFormatters.formatDateIso(startDate);
  final endIso = DateFormatters.formatDateIso(endDate);
  final prevStartIso = DateFormatters.formatDateIso(prevStartDate);
  final prevEndIso = DateFormatters.formatDateIso(prevEndDate);

  // 2. Fetch Period Expenses
  final periodExpenses = await repo.getExpensesForPeriod(
    startDate: startIso,
    endDate: endIso,
  );

  final periodTotal = await repo.getTotalSpentForPeriod(
    startDate: startIso,
    endDate: endIso,
  );

  final previousPeriodTotal = await repo.getTotalSpentForPeriod(
    startDate: prevStartIso,
    endDate: prevEndIso,
  );

  final categoryBreakdown = await repo.getSpendingByCategory(
    startDate: startIso,
    endDate: endIso,
  );

  final classificationBreakdown = await repo.getSpendingByClassification(
    startDate: startIso,
    endDate: endIso,
  );

  final personBreakdown = await repo.getSpendingByPerson(
    startDate: startIso,
    endDate: endIso,
  );

  // 3. Today, Yesterday, Month Totals
  final startOfMonthIso = DateFormatters.formatDateIso(DateTime(now.year, now.month, 1));
  final endOfMonthIso = DateFormatters.formatDateIso(DateTime(now.year, now.month + 1, 0));

  final todayTotal = await repo.getTotalSpentForPeriod(
    startDate: todayIso,
    endDate: todayIso,
  );

  final yesterdayTotal = await repo.getTotalSpentForPeriod(
    startDate: yesterdayIso,
    endDate: yesterdayIso,
  );

  final monthTotal = await repo.getTotalSpentForPeriod(
    startDate: startOfMonthIso,
    endDate: endOfMonthIso,
  );

  final isZeroSpend = await repo.isZeroSpendDayConfirmed(todayIso);

  // 4. Build Trend Points for Charts
  final List<TrendPoint> trendPoints = [];
  String highestSpendLabel = 'N/A';
  double highestSpendAmount = 0.0;

  if (timeframe == DashboardTimeframe.day) {
    // 2 points: Yesterday vs Today
    trendPoints.add(TrendPoint(
      x: 0,
      label: 'Yesterday',
      amount: yesterdayTotal,
      date: prevStartDate,
    ));
    trendPoints.add(TrendPoint(
      x: 1,
      label: 'Today',
      amount: todayTotal,
      date: startDate,
    ));
    highestSpendLabel = todayTotal >= yesterdayTotal ? 'Today' : 'Yesterday';
    highestSpendAmount = todayTotal >= yesterdayTotal ? todayTotal : yesterdayTotal;
  } else if (timeframe == DashboardTimeframe.week) {
    // 7 Daily Points (Mon..Sun)
    for (int i = 0; i < 7; i++) {
      final d = startDate.add(Duration(days: i));
      final dIso = DateFormatters.formatDateIso(d);
      final dayAmount = await repo.getTotalSpentForPeriod(
        startDate: dIso,
        endDate: dIso,
      );
      final dayName = DateFormat('EEE').format(d); // Mon, Tue...
      trendPoints.add(TrendPoint(
        x: i.toDouble(),
        label: dayName,
        amount: dayAmount,
        date: d,
      ));
      if (dayAmount > highestSpendAmount) {
        highestSpendAmount = dayAmount;
        highestSpendLabel = DateFormat('EEE, MMM d').format(d);
      }
    }
  } else if (timeframe == DashboardTimeframe.month) {
    // Group into 4 or 5 weeks or daily points
    final daysInMonth = endDate.day;
    final Map<int, double> dailyMap = {};
    for (var exp in periodExpenses) {
      final dt = DateTime.parse(exp.expenseDate);
      dailyMap[dt.day] = (dailyMap[dt.day] ?? 0.0) + exp.amount;
    }
    for (int day = 1; day <= daysInMonth; day++) {
      final amt = dailyMap[day] ?? 0.0;
      trendPoints.add(TrendPoint(
        x: (day - 1).toDouble(),
        label: '$day',
        amount: amt,
        date: DateTime(now.year, now.month, day),
      ));
      if (amt > highestSpendAmount) {
        highestSpendAmount = amt;
        highestSpendLabel = DateFormat('MMM d').format(DateTime(now.year, now.month, day));
      }
    }
  } else if (timeframe == DashboardTimeframe.year) {
    // 12 Monthly Points (Jan..Dec)
    for (int m = 1; m <= 12; m++) {
      final mStart = DateTime(now.year, m, 1);
      final mEnd = DateTime(now.year, m + 1, 0);
      final mStartIso = DateFormatters.formatDateIso(mStart);
      final mEndIso = DateFormatters.formatDateIso(mEnd);

      final mAmt = await repo.getTotalSpentForPeriod(
        startDate: mStartIso,
        endDate: mEndIso,
      );
      final monthName = DateFormat('MMM').format(mStart);
      trendPoints.add(TrendPoint(
        x: (m - 1).toDouble(),
        label: monthName,
        amount: mAmt,
        date: mStart,
      ));
      if (mAmt > highestSpendAmount) {
        highestSpendAmount = mAmt;
        highestSpendLabel = DateFormat('MMMM yyyy').format(mStart);
      }
    }
  }

  // 5. Top Category
  String topCatName = 'None';
  double topCatAmount = 0.0;
  categoryBreakdown.forEach((catId, amt) {
    if (amt > topCatAmount) {
      topCatAmount = amt;
      topCatName = catId;
    }
  });

  // Average per day
  final numDays = timeframe == DashboardTimeframe.day
      ? 1
      : (timeframe == DashboardTimeframe.week
          ? 7
          : (timeframe == DashboardTimeframe.month ? endDate.day : 365));
  final averagePerDay = periodTotal / (numDays > 0 ? numDays : 1);

  return DashboardData(
    selectedTimeframe: timeframe,
    periodTotal: periodTotal,
    previousPeriodTotal: previousPeriodTotal,
    averagePerDay: averagePerDay,
    trendPoints: trendPoints,
    categoryBreakdown: categoryBreakdown,
    classificationBreakdown: classificationBreakdown,
    personBreakdown: personBreakdown,
    topCategoryName: topCatName,
    topCategoryAmount: topCatAmount,
    highestSpendDayLabel: highestSpendLabel,
    highestSpendDayAmount: highestSpendAmount,
    todayTotal: todayTotal,
    yesterdayTotal: yesterdayTotal,
    monthTotal: monthTotal,
    isZeroSpendConfirmedToday: isZeroSpend,
    periodExpenses: periodExpenses,
  );
});
