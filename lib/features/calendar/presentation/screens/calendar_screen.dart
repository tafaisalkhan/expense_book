import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:myexpence/core/theme/app_theme.dart';
import 'package:myexpence/core/utils/currency_formatters.dart';
import 'package:myexpence/core/utils/date_formatters.dart';
import 'package:myexpence/features/ads/presentation/providers/ad_providers.dart';
import 'package:myexpence/features/calendar/presentation/providers/calendar_providers.dart';
import 'package:myexpence/features/expenses/presentation/providers/expense_providers.dart';

class CalendarScreen extends ConsumerStatefulWidget {
  const CalendarScreen({super.key});

  @override
  ConsumerState<CalendarScreen> createState() => _CalendarScreenState();
}

enum _BarSort { amount, newestDate, oldestDate }

class _CalendarScreenState extends ConsumerState<CalendarScreen> {
  bool _showBarView = false;
  _BarSort _barSort = _BarSort.amount;

  @override
  Widget build(BuildContext context) {
    final monthDate = ref.watch(calendarMonthProvider);
    final calendarAsync = ref.watch(calendarMonthDataProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Expense Calendar'),
        actions: [
          IconButton(
            icon: const Icon(Icons.chevron_left),
            onPressed: () {
              ref.read(calendarMonthProvider.notifier).state =
                  DateTime(monthDate.year, monthDate.month - 1, 1);
            },
          ),
          Center(
            child: Text(
              DateFormatters.formatMonthYear(monthDate),
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right),
            onPressed: () {
              ref.read(calendarMonthProvider.notifier).state =
                  DateTime(monthDate.year, monthDate.month + 1, 1);
            },
          ),
        ],
      ),
      body: calendarAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(child: Text('Error loading calendar: $err')),
        data: (days) {
          final spendingDays = days.where((day) => day.totalAmount > 0).toList();
          final highestDay = spendingDays.isEmpty
              ? null
              : spendingDays.reduce((a, b) =>
                  a.totalAmount >= b.totalAmount ? a : b);
          spendingDays.sort((a, b) {
            switch (_barSort) {
              case _BarSort.amount:
                final amountOrder = b.totalAmount.compareTo(a.totalAmount);
                return amountOrder != 0
                    ? amountOrder
                    : b.dateIso.compareTo(a.dateIso);
              case _BarSort.newestDate:
                return b.dateIso.compareTo(a.dateIso);
              case _BarSort.oldestDate:
                return a.dateIso.compareTo(b.dateIso);
            }
          });
          final monthlyTotal = spendingDays.fold<double>(
              0, (total, day) => total + day.totalAmount);
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Monthly spending: ${CurrencyFormatters.defaultCurrency} ${monthlyTotal.toStringAsFixed(2)}',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    if (highestDay != null)
                      Text(
                        'Highest day: ${DateFormatters.formatDateDisplay(highestDay.date!)} · ${CurrencyFormatters.defaultCurrency} ${highestDay.totalAmount.toStringAsFixed(2)}',
                      ),
                    const SizedBox(height: 12),
                    SegmentedButton<bool>(
                      segments: const [
                        ButtonSegment(
                            value: false,
                            icon: Icon(Icons.calendar_month),
                            label: Text('Calendar')),
                        ButtonSegment(
                            value: true,
                            icon: Icon(Icons.bar_chart),
                            label: Text('Bar view')),
                      ],
                      selected: {_showBarView},
                      onSelectionChanged: (selection) =>
                          setState(() => _showBarView = selection.first),
                    ),
                  ],
                ),
              ),
              if (_showBarView) ...[
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      const Text('Sort by '),
                      DropdownButton<_BarSort>(
                        value: _barSort,
                        items: const [
                          DropdownMenuItem(
                            value: _BarSort.amount,
                            child: Text('Expense (highest first)'),
                          ),
                          DropdownMenuItem(
                            value: _BarSort.newestDate,
                            child: Text('Date (newest first)'),
                          ),
                          DropdownMenuItem(
                            value: _BarSort.oldestDate,
                            child: Text('Date (oldest first)'),
                          ),
                        ],
                        onChanged: (sort) {
                          if (sort != null) setState(() => _barSort = sort);
                        },
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: spendingDays.isEmpty
                      ? const Center(
                          child: Text('No expenses recorded this month.'))
                      : ListView.builder(
                          padding: const EdgeInsets.all(16),
                          itemCount: spendingDays.length,
                          itemBuilder: (context, index) {
                            final day = spendingDays[index];
                            final isHighest = day.dateIso == highestDay?.dateIso;
                            return InkWell(
                              onTap: () => _openDay(context, day),
                              child: Padding(
                                padding: const EdgeInsets.only(bottom: 16),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            DateFormatters.formatDateDisplay(
                                                day.date!),
                                            style: TextStyle(
                                              fontWeight: isHighest
                                                  ? FontWeight.bold
                                                  : FontWeight.normal,
                                            ),
                                          ),
                                        ),
                                        if (isHighest)
                                          const Text('Highest  ',
                                              style: TextStyle(
                                                  color: Colors.deepOrange)),
                                        Text(
                                            '${CurrencyFormatters.defaultCurrency} ${day.totalAmount.toStringAsFixed(2)}'),
                                      ],
                                    ),
                                    const SizedBox(height: 6),
                                    LinearProgressIndicator(
                                      value: day.totalAmount /
                                          highestDay!.totalAmount,
                                      minHeight: 12,
                                      borderRadius: BorderRadius.circular(6),
                                      color: isHighest
                                          ? Colors.deepOrange
                                          : AppTheme.primaryColor,
                                      backgroundColor: Colors.grey.shade200,
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ] else ...[
                // Legend
                Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16.0, vertical: 8.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _buildLegendItem('Spend Recorded', Colors.green),
                      _buildLegendItem('Zero-Spend', Colors.blue),
                      _buildLegendItem('Missing Day', Colors.amber),
                    ],
                  ),
                ),
                const Divider(height: 1),

                // Weekday Headers (Mon - Sun)
                Container(
                  padding:
                      const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                  color: Colors.grey[100],
                  child: Row(
                    children: const [
                      Expanded(
                          child: Center(
                              child: Text('Mon',
                                  style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 11,
                                      color: Colors.black54)))),
                      Expanded(
                          child: Center(
                              child: Text('Tue',
                                  style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 11,
                                      color: Colors.black54)))),
                      Expanded(
                          child: Center(
                              child: Text('Wed',
                                  style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 11,
                                      color: Colors.black54)))),
                      Expanded(
                          child: Center(
                              child: Text('Thu',
                                  style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 11,
                                      color: Colors.black54)))),
                      Expanded(
                          child: Center(
                              child: Text('Fri',
                                  style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 11,
                                      color: Colors.black54)))),
                      Expanded(
                          child: Center(
                              child: Text('Sat',
                                  style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 11,
                                      color: Colors.black54)))),
                      Expanded(
                          child: Center(
                              child: Text('Sun',
                                  style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 11,
                                      color: Colors.black54)))),
                    ],
                  ),
                ),
                const SizedBox(height: 4),

                // Days Grid
                Expanded(
                  child: GridView.builder(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 7,
                      childAspectRatio: 0.85,
                      crossAxisSpacing: 6,
                      mainAxisSpacing: 6,
                    ),
                    itemCount: days.length,
                    itemBuilder: (context, index) {
                      final day = days[index];
                      return _buildDayCell(context, ref, day);
                    },
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }

  void _openDay(BuildContext context, DayDetail day) {
    ref.read(adNotifierProvider.notifier).recordNavigation(context);
    context.push('/expenses?date=${day.dateIso}', extra: day.dateIso);
  }

  Widget _buildLegendItem(String label, Color color) {
    return Row(
      children: [
        Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 4),
        Text(label,
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500)),
      ],
    );
  }

  Widget _buildDayCell(BuildContext context, WidgetRef ref, DayDetail day) {
    if (day.isPlaceholder || day.date == null) {
      return const SizedBox.shrink();
    }

    Color color;
    IconData? icon;

    switch (day.status) {
      case DayStatus.recorded:
        color = Colors.green;
        break;
      case DayStatus.zeroSpend:
        color = Colors.blue;
        icon = Icons.check_circle_outline;
        break;
      case DayStatus.missing:
        color = Colors.amber;
        icon = Icons.help_outline;
        break;
      case DayStatus.future:
        color = Colors.grey;
        break;
    }

    return InkWell(
      onTap: () {
        if (day.status == DayStatus.missing) {
          _showMissingDayOptions(context, ref, day);
        } else if (day.status == DayStatus.recorded ||
            day.status == DayStatus.zeroSpend) {
          _openDay(context, day);
        }
      },
      borderRadius: BorderRadius.circular(8),
      child: Container(
        decoration: BoxDecoration(
          color: color.withOpacity(0.12),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withOpacity(0.4)),
        ),
        padding: const EdgeInsets.all(4),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              '${day.date?.day ?? ""}',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 12,
                color: color,
              ),
            ),
            if (day.totalAmount > 0)
              FittedBox(
                child: Text(
                  CurrencyFormatters.formatCompact(day.totalAmount,
                      currencySymbol: ''),
                  style: TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 10, color: color),
                ),
              )
            else if (icon != null)
              Icon(icon, size: 14, color: color)
            else
              const SizedBox.shrink(),
          ],
        ),
      ),
    );
  }

  void _showMissingDayOptions(
      BuildContext context, WidgetRef ref, DayDetail day) {
    if (day.date == null) return;

    showModalBottomSheet(
      context: context,
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Unconfirmed Day: ${DateFormatters.formatDateDisplay(day.date!)}',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 12),
            const Text('You have not confirmed expenses for this date.'),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () {
                      ref
                          .read(expenseNotifierProvider.notifier)
                          .confirmZeroSpend(day.dateIso);
                      ref.invalidate(calendarMonthDataProvider);
                      Navigator.pop(ctx);
                    },
                    child: const Text('Mark Zero-Spend'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primaryColor,
                        foregroundColor: Colors.white),
                    onPressed: () {
                      Navigator.pop(ctx);
                      ref
                          .read(adNotifierProvider.notifier)
                          .recordNavigation(context);
                      context.push('/add');
                    },
                    child: const Text('Add Expense'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
