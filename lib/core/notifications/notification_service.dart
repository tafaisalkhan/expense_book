import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

class NotificationService {
  final FlutterLocalNotificationsPlugin _notificationsPlugin =
      FlutterLocalNotificationsPlugin();

  Future<void> init() async {
    tz_data.initializeTimeZones();
    tz.setLocalLocation(tz.getLocation('Asia/Karachi'));
    const androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings();

    const initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _notificationsPlugin.initialize(
      initSettings,
      onDidReceiveNotificationResponse: (NotificationResponse details) {
        // Deep link handling
      },
    );

    await requestPermissions();
  }

  Future<void> scheduleRecurringApprovalReminder() async {
    await requestPermissions();
    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        'recurring_approval_channel',
        'Recurring expense approvals',
        channelDescription:
            'Daily reminder to approve or reject recurring expenses',
        importance: Importance.high,
        priority: Priority.high,
      ),
      iOS: DarwinNotificationDetails(),
    );
    final now = tz.TZDateTime.now(tz.local);
    var scheduled = tz.TZDateTime(tz.local, now.year, now.month, now.day, 21);
    if (!scheduled.isAfter(now))
      scheduled = scheduled.add(const Duration(days: 1));
    await _notificationsPlugin.zonedSchedule(
      1002,
      'Review recurring expenses',
      'Open MyExpense to approve or reject today’s automatic expenses.',
      scheduled,
      details,
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      matchDateTimeComponents: DateTimeComponents.time,
    );
  }

  Future<bool?> requestPermissions() async {
    final androidImplementation =
        _notificationsPlugin.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    if (androidImplementation != null) {
      return await androidImplementation.requestNotificationsPermission();
    }
    return true;
  }

  Future<void> showDailyCompletionReminder() async {
    await requestPermissions();
    const androidDetails = AndroidNotificationDetails(
      'daily_completion_channel',
      'Daily Expense Reminders',
      channelDescription:
          'Reminds you to record daily expenses before end of day',
      importance: Importance.high,
      priority: Priority.high,
    );

    const notificationDetails = NotificationDetails(
      android: androidDetails,
      iOS: DarwinNotificationDetails(),
    );

    await _notificationsPlugin.show(
      1001,
      'MyExpense Daily Check',
      'Have you recorded all your expenses for today?',
      notificationDetails,
    );
  }

  Future<void> showBudgetWarningNotification(
      String categoryName, double percentage) async {
    await requestPermissions();
    const androidDetails = AndroidNotificationDetails(
      'budget_warning_channel',
      'Budget Warning Notifications',
      channelDescription: 'Notifies when spending approaches budget limits',
      importance: Importance.high,
      priority: Priority.high,
    );

    const notificationDetails = NotificationDetails(
      android: androidDetails,
      iOS: DarwinNotificationDetails(),
    );

    await _notificationsPlugin.show(
      2001,
      'Budget Threshold Alert',
      'You have used ${percentage.toStringAsFixed(0)}% of your $categoryName budget.',
      notificationDetails,
    );
  }
}
