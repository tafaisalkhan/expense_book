import 'dart:async';
import 'dart:convert';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:myexpence/features/notifications/domain/models/geofence_target.dart';
import 'package:myexpence/features/notifications/domain/models/location_notification.dart';

import 'package:flutter/foundation.dart';

class LocationNotificationState {
  final List<LocationVisitNotification> todayNotifications;
  final Set<String> mutedPlaces;
  final List<GeofenceTarget> savedGeofences;
  final double? lastUserLat;
  final double? lastUserLng;

  const LocationNotificationState({
    this.todayNotifications = const [],
    this.mutedPlaces = const {},
    this.savedGeofences = const [],
    this.lastUserLat,
    this.lastUserLng,
  });

  List<LocationVisitNotification> get activeNotifications =>
      todayNotifications.where((n) => n.isActive).toList();

  LocationNotificationState copyWith({
    List<LocationVisitNotification>? todayNotifications,
    Set<String>? mutedPlaces,
    List<GeofenceTarget>? savedGeofences,
    double? lastUserLat,
    double? lastUserLng,
  }) {
    return LocationNotificationState(
      todayNotifications: todayNotifications ?? this.todayNotifications,
      mutedPlaces: mutedPlaces ?? this.mutedPlaces,
      savedGeofences: savedGeofences ?? this.savedGeofences,
      lastUserLat: lastUserLat ?? this.lastUserLat,
      lastUserLng: lastUserLng ?? this.lastUserLng,
    );
  }
}

class LocationNotificationNotifier extends StateNotifier<LocationNotificationState> {
  LocationNotificationNotifier() : super(const LocationNotificationState()) {
    _init();
  }

  LocationNotificationState get currentState => state;

  static const String _prefKeyNotifs = 'location_notifications_v1';
  static const String _prefKeyMuted = 'location_muted_places_v1';
  static const String _prefKeyGeofences = 'location_geofences_v1';
  static const String _prefKeyInside = 'location_inside_geofences_v1';

  final FlutterLocalNotificationsPlugin _localNotifs = FlutterLocalNotificationsPlugin();
  StreamSubscription<Position>? _positionStreamSub;
  Timer? _periodicGeofenceTimer;
  final Set<String> _insideGeofences = {};

  Future<void> _saveInsideGeofences() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_prefKeyInside, _insideGeofences.toList());
    } catch (_) {}
  }

  Future<void>? _initFuture;

  Future<void> ensureInitialized() {
    _initFuture ??= _init();
    return _initFuture!;
  }

  Future<void> _init() async {
    await _initLocalNotifications();
    await _loadNotificationsInternal();
    await startLiveLocationTracking();
    await checkProximityNow();
  }

  Future<void> _initLocalNotifications() async {
    try {
      const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
      const initSettings = InitializationSettings(android: androidSettings);
      await _localNotifs.initialize(initSettings);
      final androidImplementation = _localNotifs
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      if (androidImplementation != null) {
        await androidImplementation.requestNotificationsPermission();

        const channel1 = AndroidNotificationChannel(
          'location_reminders_channel',
          'Location Reminders',
          description: 'Expense logging notifications after entering or leaving Mart, Petrol Pump, Hospital, or Mall.',
          importance: Importance.max,
          playSound: true,
          enableVibration: true,
        );
        const channel2 = AndroidNotificationChannel(
          'daily_end_of_day_channel',
          'End of Day Expense Reminders',
          description: 'Daily evening reminder to add left expenses and approve or reject pending logs.',
          importance: Importance.max,
          playSound: true,
          enableVibration: true,
        );
        await androidImplementation.createNotificationChannel(channel1);
        await androidImplementation.createNotificationChannel(channel2);
      }
      await scheduleDailyEndOfDayReminder();
    } catch (_) {}
  }

  /// Listens to real-time GPS stream & automatically triggers notifications upon entering or leaving geofence surroundings
  Future<void> startLiveLocationTracking() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        await _sendGpsDisabledNotification();
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
        await _sendGpsDisabledNotification();
        return;
      }

      await _positionStreamSub?.cancel();

      late final LocationSettings locationSettings;
      if (defaultTargetPlatform == TargetPlatform.android) {
        locationSettings = AndroidSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 0,
          forceLocationManager: false,
          intervalDuration: const Duration(seconds: 2),
        );
      } else {
        locationSettings = const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 0,
        );
      }

      _positionStreamSub = Geolocator.getPositionStream(
        locationSettings: locationSettings,
      ).listen((Position pos) {
        if (!mounted) return;
        _checkGeofenceProximity(pos.latitude, pos.longitude);
      });

      // Periodic 1-minute geofence proximity check scheduler
      _periodicGeofenceTimer?.cancel();
      _periodicGeofenceTimer = Timer.periodic(const Duration(minutes: 1), (_) {
        if (mounted) {
          checkProximityNow();
        }
      });

      // Also trigger an immediate proximity check right away
      await checkProximityNow();
    } catch (_) {}
  }

  Future<void> _sendGpsDisabledNotification() async {
    try {
      const androidDetails = AndroidNotificationDetails(
        'location_reminders_channel',
        'Location Reminders',
        importance: Importance.high,
        priority: Priority.high,
      );
      const details = NotificationDetails(android: androidDetails);
      await _localNotifs.show(
        7777,
        '⚠️ GPS Location Services Disabled',
        'Geofencing expense reminders are paused. Please turn on GPS Location & allow permissions to resume.',
        details,
      );
    } catch (_) {}
  }

  /// Immediately fetches device position and checks proximity against all saved geofences
  Future<bool> checkProximityNow() async {
    if (!mounted) return false;
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return false;

      Position? pos = await Geolocator.getLastKnownPosition();
      pos ??= await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 4),
        ),
      );
      if (!mounted || pos == null) return false;
      _checkGeofenceProximity(pos.latitude, pos.longitude);
      return true;
    } catch (_) {
      return false;
    }
  }

  void _checkGeofenceProximity(double userLat, double userLng) {
    if (!mounted) return;
    state = state.copyWith(lastUserLat: userLat, lastUserLng: userLng);
    for (final target in state.savedGeofences) {
      final double distanceMeters = Geolocator.distanceBetween(
        userLat,
        userLng,
        target.latitude,
        target.longitude,
      );

      final isInside = distanceMeters <= target.radiusMeters;
      final wasInside = _insideGeofences.contains(target.id);

      if (isInside && !wasInside) {
        _insideGeofences.add(target.id);
        _saveInsideGeofences();
        userEnteredLocation(placeName: target.name, type: target.locationType);
      } else if (!isInside && wasInside) {
        _insideGeofences.remove(target.id);
        _saveInsideGeofences();
        userLeftLocation(placeName: target.name, type: target.locationType);
      }
    }
  }

  @override
  void dispose() {
    _periodicGeofenceTimer?.cancel();
    _periodicGeofenceTimer = null;
    _positionStreamSub?.cancel();
    _positionStreamSub = null;
    super.dispose();
  }

  Future<void> loadNotifications() async {
    await ensureInitialized();
    await _loadNotificationsInternal();
  }

  Future<void> _loadNotificationsInternal() async {
    final prefs = await SharedPreferences.getInstance();

    // 0. Load Inside Geofences State
    final insideList = prefs.getStringList(_prefKeyInside) ?? [];
    _insideGeofences.clear();
    _insideGeofences.addAll(insideList);

    // 1. Load Muted Places
    final mutedList = prefs.getStringList(_prefKeyMuted) ?? [];
    final mutedPlaces = mutedList.map((e) => e.toUpperCase()).toSet();

    // 2. Load Notifications & Filter Previous Day Expiry
    final todayIso = DateTime.now().toIso8601String().split('T').first;
    final jsonListStr = prefs.getString(_prefKeyNotifs);

    List<LocationVisitNotification> notifications = [];
    if (jsonListStr != null) {
      try {
        final List raw = jsonDecode(jsonListStr);
        notifications = raw
            .map((item) => LocationVisitNotification.fromJson(item))
            .where((n) => n.visitDateIso == todayIso)
            .toList();
      } catch (_) {}
    }

    // 3. Load Saved Map Geofences
    final geofencesJsonStr = prefs.getString(_prefKeyGeofences);
    List<GeofenceTarget> geofences = [];
    if (geofencesJsonStr != null) {
      try {
        final List rawGeo = jsonDecode(geofencesJsonStr);
        geofences = rawGeo.map((item) => GeofenceTarget.fromJson(item)).toList();
      } catch (_) {}
    }

    if (geofences.isEmpty) {
      double defaultLat = 31.5204;
      double defaultLng = 74.3587;
      try {
        final pos = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
            timeLimit: Duration(seconds: 4),
          ),
        );
        defaultLat = pos.latitude;
        defaultLng = pos.longitude;
      } catch (_) {}

      geofences = [
        GeofenceTarget(
          id: 'default_my_location',
          name: 'My Current Location Target',
          locationType: LocationType.localMarket,
          latitude: defaultLat,
          longitude: defaultLng,
          radiusMeters: 300,
        ),
        GeofenceTarget(
          id: 'default_shell_pump',
          name: 'Shell Petrol Pump',
          locationType: LocationType.petrolPump,
          latitude: defaultLat + 0.002,
          longitude: defaultLng + 0.002,
          radiusMeters: 300,
        ),
        GeofenceTarget(
          id: 'default_metro_mart',
          name: 'Metro Super Market',
          locationType: LocationType.superMarket,
          latitude: defaultLat - 0.002,
          longitude: defaultLng - 0.002,
          radiusMeters: 300,
        ),
      ];
      try {
        await prefs.setString(_prefKeyGeofences, jsonEncode(geofences.map((e) => e.toJson()).toList()));
      } catch (_) {}
    }

    state = state.copyWith(
      todayNotifications: notifications,
      mutedPlaces: mutedPlaces,
      savedGeofences: geofences,
    );

    await _saveToPrefs();
  }

  /// Re-centers default geofences dynamically around the user's real-time GPS location
  Future<bool> autoSetGeofencesAtCurrentLocation() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        await _sendGpsDisabledNotification();
        return false;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
        await _sendGpsDisabledNotification();
        return false;
      }

      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 5),
        ),
      );
      final double lat = pos.latitude;
      final double lng = pos.longitude;

      final updatedGeofences = [
        GeofenceTarget(
          id: 'current_my_location_${DateTime.now().millisecondsSinceEpoch}',
          name: 'Current Spot (Center)',
          locationType: LocationType.localMarket,
          latitude: lat,
          longitude: lng,
          radiusMeters: 200,
        ),
        GeofenceTarget(
          id: 'current_nearby_pump_${DateTime.now().millisecondsSinceEpoch}',
          name: 'Nearby Petrol Station',
          locationType: LocationType.petrolPump,
          latitude: lat + 0.001,
          longitude: lng + 0.001,
          radiusMeters: 250,
        ),
        GeofenceTarget(
          id: 'current_super_market_${DateTime.now().millisecondsSinceEpoch}',
          name: 'Nearby Super Market',
          locationType: LocationType.superMarket,
          latitude: lat - 0.001,
          longitude: lng - 0.001,
          radiusMeters: 250,
        ),
      ];

      state = state.copyWith(savedGeofences: updatedGeofences);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefKeyGeofences, jsonEncode(updatedGeofences.map((e) => e.toJson()).toList()));

      await checkProximityNow();
      return true;
    } catch (_) {
      await _sendGpsDisabledNotification();
      return false;
    }
  }

  /// Adds a map-selected geofence zone target
  Future<void> addGeofenceTarget(GeofenceTarget target) async {
    final updated = [...state.savedGeofences.where((g) => g.id != target.id), target];
    state = state.copyWith(savedGeofences: updated);

    final prefs = await SharedPreferences.getInstance();
    final raw = updated.map((e) => e.toJson()).toList();
    await prefs.setString(_prefKeyGeofences, jsonEncode(raw));

    // Immediately check proximity for the new target
    await checkProximityNow();
  }

  /// Removes a saved geofence zone
  Future<void> deleteGeofenceTarget(String id) async {
    final updated = state.savedGeofences.where((g) => g.id != id).toList();
    state = state.copyWith(savedGeofences: updated);

    final prefs = await SharedPreferences.getInstance();
    final raw = updated.map((e) => e.toJson()).toList();
    await prefs.setString(_prefKeyGeofences, jsonEncode(raw));
  }

  /// Manually simulates or triggers Enter Range for a specific geofence target or place
  Future<LocationVisitNotification?> simulateEnterGeofence(GeofenceTarget target) async {
    _insideGeofences.add(target.id);
    await _saveInsideGeofences();
    return await userEnteredLocation(placeName: target.name, type: target.locationType);
  }

  /// Manually simulates or triggers Exit Range for a specific geofence target or place
  Future<LocationVisitNotification?> simulateExitGeofence(GeofenceTarget target) async {
    _insideGeofences.remove(target.id);
    await _saveInsideGeofences();
    return await userLeftLocation(placeName: target.name, type: target.locationType);
  }

  /// Triggers when user ENTERS a commercial location or map geofence zone
  Future<LocationVisitNotification?> userEnteredLocation({
    required String placeName,
    required LocationType type,
  }) async {
    await ensureInitialized();
    final upperPlace = placeName.trim().toUpperCase();

    if (state.mutedPlaces.contains(upperPlace)) {
      return null;
    }

    final now = DateTime.now();
    final todayIso = now.toIso8601String().split('T').first;
    final nowIso = now.toIso8601String();

    final notifId = 'loc_enter_${type.name}_${now.millisecondsSinceEpoch}';

    final notif = LocationVisitNotification(
      id: notifId,
      placeName: placeName.trim(),
      locationType: type,
      visitDateIso: todayIso,
      leftAtIso: nowIso,
      lastRemindedAtIso: nowIso,
      reminderCount: 1,
      isLogged: false,
      isMuted: false,
      isDiscarded: false,
    );

    final updated = [...state.todayNotifications, notif];
    state = state.copyWith(todayNotifications: updated);
    await _saveToPrefs();

    await _sendPushNotification(notif, isEntry: true);

    return notif;
  }

  /// Triggers when user LEAVES a commercial location or map geofence zone
  Future<LocationVisitNotification?> userLeftLocation({
    required String placeName,
    required LocationType type,
  }) async {
    await ensureInitialized();
    final upperPlace = placeName.trim().toUpperCase();

    if (state.mutedPlaces.contains(upperPlace)) {
      return null;
    }

    final now = DateTime.now();
    final todayIso = now.toIso8601String().split('T').first;
    final nowIso = now.toIso8601String();

    final notifId = 'loc_${type.name}_${now.millisecondsSinceEpoch}';

    final notif = LocationVisitNotification(
      id: notifId,
      placeName: placeName.trim(),
      locationType: type,
      visitDateIso: todayIso,
      leftAtIso: nowIso,
      lastRemindedAtIso: nowIso,
      reminderCount: 1,
      isLogged: false,
      isMuted: false,
      isDiscarded: false,
    );

    final updated = [...state.todayNotifications, notif];
    state = state.copyWith(todayNotifications: updated);
    await _saveToPrefs();

    await _sendPushNotification(notif);

    return notif;
  }

  Future<void> triggerHourlyReminders() async {
    final now = DateTime.now();
    final todayIso = now.toIso8601String().split('T').first;

    final updated = <LocationVisitNotification>[];

    for (final notif in state.todayNotifications) {
      if (notif.visitDateIso == todayIso && notif.isActive) {
        final lastReminded = DateTime.tryParse(notif.lastRemindedAtIso) ?? now;
        final hoursDiff = now.difference(lastReminded).inHours;

        if (hoursDiff >= 1) {
          final nextNotif = notif.copyWith(
            reminderCount: notif.reminderCount + 1,
            lastRemindedAtIso: now.toIso8601String(),
          );
          updated.add(nextNotif);
          await _sendPushNotification(nextNotif);
        } else {
          updated.add(notif);
        }
      } else if (!notif.isExpired) {
        updated.add(notif);
      }
    }

    state = state.copyWith(todayNotifications: updated);
    await _saveToPrefs();
  }

  Future<void> muteLocation(String placeName) async {
    final upperPlace = placeName.trim().toUpperCase();
    final updatedMuted = {...state.mutedPlaces, upperPlace};

    final updatedNotifs = state.todayNotifications.map((n) {
      if (n.placeName.trim().toUpperCase() == upperPlace) {
        return n.copyWith(isMuted: true);
      }
      return n;
    }).toList();

    state = state.copyWith(
      mutedPlaces: updatedMuted,
      todayNotifications: updatedNotifs,
    );

    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_prefKeyMuted, updatedMuted.toList());
    await _saveToPrefs();
  }

  Future<void> unmuteLocation(String placeName) async {
    final upperPlace = placeName.trim().toUpperCase();
    final updatedMuted = state.mutedPlaces.where((p) => p != upperPlace).toSet();

    state = state.copyWith(mutedPlaces: updatedMuted);

    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_prefKeyMuted, updatedMuted.toList());
  }

  Future<void> discardNotification(String id) async {
    final updatedNotifs = state.todayNotifications.map((n) {
      if (n.id == id) {
        return n.copyWith(isDiscarded: true);
      }
      return n;
    }).toList();

    state = state.copyWith(todayNotifications: updatedNotifs);
    await _saveToPrefs();
  }

  Future<void> markLogged(String id) async {
    final updatedNotifs = state.todayNotifications.map((n) {
      if (n.id == id) {
        return n.copyWith(isLogged: true);
      }
      return n;
    }).toList();

    state = state.copyWith(todayNotifications: updatedNotifs);
    await _saveToPrefs();
  }

  Future<void> _saveToPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = state.todayNotifications.map((e) => e.toJson()).toList();
    await prefs.setString(_prefKeyNotifs, jsonEncode(raw));
  }

  Future<void> _sendPushNotification(LocationVisitNotification notif, {bool isEntry = false}) async {
    try {
      const androidDetails = AndroidNotificationDetails(
        'location_reminders_channel',
        'Location Reminders',
        channelDescription: 'Expense logging notifications after entering or leaving Mart, Petrol Pump, Hospital, or Mall.',
        importance: Importance.max,
        priority: Priority.max,
        playSound: true,
        enableVibration: true,
      );
      const details = NotificationDetails(android: androidDetails);

      final title = isEntry
          ? '📍 Entered ${notif.placeName} (${notif.locationType.label})'
          : '📍 Left ${notif.placeName} (${notif.locationType.label})';

      final body = isEntry
          ? 'You have entered ${notif.placeName} range. Tap to log expenses or view details.'
          : 'Did you make a purchase at ${notif.placeName}? Tap to log expense details.'
              '${notif.reminderCount > 1 ? ' (Hourly reminder #${notif.reminderCount})' : ''}';

      await _localNotifs.show(
        notif.id.hashCode,
        title,
        body,
        details,
      );
    } catch (_) {}
  }

  Future<void> scheduleDailyEndOfDayReminder() async {
    try {
      const androidDetails = AndroidNotificationDetails(
        'daily_end_of_day_channel',
        'End of Day Expense Reminders',
        channelDescription: 'Daily evening reminder to add left expenses and approve or reject pending logs.',
        importance: Importance.high,
        priority: Priority.high,
      );
      const details = NotificationDetails(android: androidDetails);

      await _localNotifs.periodicallyShow(
        8888,
        '🌙 Daily End of Day Expense Check',
        'Have any left expenses for today? Open MyExpense to add them or approve/reject pending items.',
        RepeatInterval.daily,
        details,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      );
    } catch (_) {}
  }

  Future<void> triggerManualDailyReminder() async {
    try {
      const androidDetails = AndroidNotificationDetails(
        'daily_end_of_day_channel',
        'End of Day Expense Reminders',
        channelDescription: 'Daily evening reminder to add left expenses and approve or reject pending logs.',
        importance: Importance.high,
        priority: Priority.high,
      );
      const details = NotificationDetails(android: androidDetails);

      await _localNotifs.show(
        9999,
        '🌙 Daily End of Day Expense Check',
        'Don\'t forget to add any left expenses for today, or review approve/reject pending receipts!',
        details,
      );
    } catch (_) {}
  }
  void clearTodayNotificationsForTest() {
    state = state.copyWith(todayNotifications: []);
  }
}

final locationNotificationProvider =
    StateNotifierProvider<LocationNotificationNotifier, LocationNotificationState>((ref) {
  return LocationNotificationNotifier();
});
