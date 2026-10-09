import 'package:intl/intl.dart';

class DateFormatters {
  static final DateFormat _isoDateFormat = DateFormat('yyyy-MM-dd');
  static final DateFormat _displayDateFormat = DateFormat('EEE, d MMM yyyy');
  static final DateFormat _shortDateFormat = DateFormat('d MMM');
  static final DateFormat _monthYearFormat = DateFormat('MMMM yyyy');
  static final DateFormat _timeFormat = DateFormat('hh:mm a');

  static String formatDateIso(DateTime date) => _isoDateFormat.format(date);

  static DateTime parseDateIso(String isoString) => _isoDateFormat.parse(isoString);

  static String formatDateDisplay(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final target = DateTime(date.year, date.month, date.day);

    if (target.isAtSameMomentAs(today)) {
      return 'Today';
    } else if (target.isAtSameMomentAs(yesterday)) {
      return 'Yesterday';
    } else {
      return _displayDateFormat.format(date);
    }
  }

  static String formatDateExactDisplay(DateTime date) => _displayDateFormat.format(date);

  static String formatDateShort(DateTime date) => _shortDateFormat.format(date);

  static String formatMonthYear(DateTime date) => _monthYearFormat.format(date);

  static String formatTime(DateTime time) => _timeFormat.format(time);

  static String todayIso() => formatDateIso(DateTime.now());

  static String yesterdayIso() => formatDateIso(DateTime.now().subtract(const Duration(days: 1)));
}
