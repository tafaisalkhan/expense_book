import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:myexpence/features/notifications/presentation/providers/location_notification_providers.dart';
import 'package:myexpence/features/sms_parser/domain/services/sms_listener_service.dart';
import 'package:myexpence/features/sms_parser/presentation/widgets/sms_approval_dialog.dart';

class AppPermissionsService {
  static bool _hasPromptedOnStartup = false;

  /// Prompts user on app launch for all required permissions & handles permission updates seamlessly
  static Future<void> requestAllStartupPermissions(WidgetRef ref, {dynamic context, bool forceRefresh = false}) async {
    if (_hasPromptedOnStartup && !forceRefresh) return;
    _hasPromptedOnStartup = true;

    if (kIsWeb || (!Platform.isAndroid && !Platform.isIOS)) return;

    try {
      // 1. Check & Request Location Permission (GPS & Geofencing)
      LocationPermission locationPermission = await Geolocator.checkPermission();
      if (locationPermission == LocationPermission.denied) {
        locationPermission = await Geolocator.requestPermission();
      }

      // 2. Check & Request Local Notification Permission (Push Reminders)
      final localNotifs = FlutterLocalNotificationsPlugin();
      final androidImplementation = localNotifs
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      if (androidImplementation != null) {
        await androidImplementation.requestNotificationsPermission();
      }

      // 3. Start Live GPS Tracking & Geofencing Radar
      final locationNotifier = ref.read(locationNotificationProvider.notifier);
      await locationNotifier.startLiveLocationTracking();
      await locationNotifier.checkProximityNow();
    } catch (_) {}
  }
}
