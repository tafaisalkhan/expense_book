import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class AppPermissionsService {
  static bool _hasPromptedOnStartup = false;

  /// Prompts user on app launch for required permissions
  static Future<void> requestAllStartupPermissions(WidgetRef ref, {dynamic context, bool forceRefresh = false}) async {
    if (_hasPromptedOnStartup && !forceRefresh) return;
    _hasPromptedOnStartup = true;

    if (kIsWeb || (!Platform.isAndroid && !Platform.isIOS)) return;

    try {
      // Check & Request Local Notification Permission (Push Reminders)
      final localNotifs = FlutterLocalNotificationsPlugin();
      final androidImplementation = localNotifs
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      if (androidImplementation != null) {
        await androidImplementation.requestNotificationsPermission();
      }
    } catch (_) {}
  }
}
