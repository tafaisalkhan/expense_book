import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:myexpence/core/theme/app_theme.dart';
import 'package:myexpence/core/utils/currency_formatters.dart';
import 'package:myexpence/core/utils/date_formatters.dart';
import 'package:myexpence/features/ads/presentation/providers/ad_providers.dart';
import 'package:myexpence/features/calendar/presentation/providers/calendar_providers.dart';
import 'package:myexpence/features/expenses/presentation/providers/expense_providers.dart';

class CalendarScreen extends ConsumerWidget {
  const CalendarScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final monthDate = ref.watch(calendarMonthProvider);
    final calendarAsync = ref.watch(calendarMonthDataProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Expense Calendar'),
        actions: [
          IconButton(
            icon: const Icon(Icons.chevron_left),
            onPressed: () {
              ref.read(calendarMonthProvider.notifier).state = DateTime(monthDate.year, monthDate.month - 1, 1);
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
              ref.read(calendarMonthProvider.notifier).state = DateTime(monthDate.year, monthDate.month + 1, 1);
            },
          ),
        ],
      ),
      body: calendarAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(child: Text('Error loading calendar: $err')),
        data: (days) {
          return Column(
            children: [
              // Legend
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
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
                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                color: Colors.grey[100],
                child: Row(
                  children: const [
                    Expanded(child: Center(child: Text('Mon', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: Colors.black54)))),
                    Expanded(child: Center(child: Text('Tue', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: Colors.black54)))),
                    Expanded(child: Center(child: Text('Wed', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: Colors.black54)))),
                    Expanded(child: Center(child: Text('Thu', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: Colors.black54)))),
                    Expanded(child: Center(child: Text('Fri', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: Colors.black54)))),
                    Expanded(child: Center(child: Text('Sat', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: Colors.black54)))),
                    Expanded(child: Center(child: Text('Sun', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: Colors.black54)))),
                  ],
                ),
              ),
              const SizedBox(height: 4),

              // Days Grid
              Expanded(
                child: GridView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
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
          );
        },
      ),
    );
  }

  Widget _buildLegendItem(String label, Color color) {
    return Row(
      children: [
        Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500)),
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
          ref.read(adNotifierProvider.notifier).recordNavigation(context);
          context.push('/expenses?date=${day.dateIso}', extra: day.dateIso);
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
                  CurrencyFormatters.formatCompact(day.totalAmount, currencySymbol: ''),
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 10, color: color),
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

  void _showMissingDayOptions(BuildContext context, WidgetRef ref, DayDetail day) {
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
                      ref.read(expenseNotifierProvider.notifier).confirmZeroSpend(day.dateIso);
                      ref.invalidate(calendarMonthDataProvider);
                      Navigator.pop(ctx);
                    },
                    child: const Text('Mark Zero-Spend'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryColor, foregroundColor: Colors.white),
                    onPressed: () {
                      Navigator.pop(ctx);
                      ref.read(adNotifierProvider.notifier).recordNavigation(context);
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
