import 'dart:io';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';
import 'cloud_backup_service.dart';

@pragma('vm:entry-point')
void cloudBackupDispatcher() {
  Workmanager().executeTask((task, input) async {
    WidgetsFlutterBinding.ensureInitialized();
    if (task != BackupScheduler.taskName) return true;
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    final uid = input?['uid'] as String?;
    if (uid == null ||
        prefs.getString('cloud_schedule_owner') != uid ||
        (prefs.getString('cloud_schedule') ?? 'off') == 'off') {
      return true;
    }
    try {
      await Firebase.initializeApp();
      final user = await FirebaseAuth.instance
          .authStateChanges()
          .first
          .timeout(const Duration(seconds: 10));
      if (user?.uid != uid || prefs.getBool('auth_is_logged_in') != true) {
        await BackupScheduler.disable();
        return true;
      }
      await CloudBackupService().backUp(automatic: true, expectedUid: uid);
      return true;
    } on CloudSubscriptionRequired {
      await prefs.setString('cloud_last_error_$uid',
          'Cloud backup subscription expired. Automatic 12:00 PM backup is off.');
      await BackupScheduler.disable();
      return true;
    } catch (_) {
      await prefs.setString('cloud_last_error_$uid',
          'Automatic 12:00 PM backup did not finish. It will retry.');
      return false;
    }
  });
}

class BackupScheduler {
  static const taskName = 'myexpense.supabase.daily_noon_backup';

  static Future<void> initialize() async {
    if (Platform.isAndroid) {
      await Workmanager().initialize(cloudBackupDispatcher);
    }
  }

  /// Calculates delay until the next 12:00 PM (noon) local time.
  static Duration delayUntilNextNoon([DateTime? from]) {
    final now = from ?? DateTime.now();
    var target = DateTime(now.year, now.month, now.day, 12, 0, 0);
    if (!target.isAfter(now)) {
      target = target.add(const Duration(days: 1));
    }
    return target.difference(now);
  }

  static Future<void> set(String frequency, {required bool wifiOnly}) async {
    if (!['off', 'hourly', 'daily', 'weekly'].contains(frequency)) {
      throw ArgumentError.value(frequency);
    }
    if (frequency == 'off') {
      await disable();
      return;
    }
    if (!Platform.isAndroid) {
      throw UnsupportedError('Scheduled backup is available on Android.');
    }
    final service = CloudBackupService();
    final uid = await service.signedInUid();
    if ((await service.access())['active'] != true) {
      throw const CloudSubscriptionRequired();
    }
    await initialize();
    final interval = frequency == 'hourly'
        ? const Duration(hours: 1)
        : Duration(days: frequency == 'daily' ? 1 : 7);
    final initialDelay = frequency == 'hourly'
        ? const Duration(minutes: 15)
        : delayUntilNextNoon();
    await Workmanager().registerPeriodicTask(
      taskName,
      taskName,
      frequency: interval,
      initialDelay: initialDelay,
      existingWorkPolicy: ExistingPeriodicWorkPolicy.update,
      inputData: {'uid': uid},
      constraints: Constraints(
        networkType: wifiOnly ? NetworkType.unmetered : NetworkType.connected,
      ),
    );
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('cloud_schedule_owner', uid);
    await prefs.setString('cloud_schedule', frequency);
    await prefs.setBool('cloud_wifi_only', wifiOnly);
  }

  /// Automatically enables 1-hour periodic background Workmanager backup for VIP owner (`muhammadfaysal.khan7@gmail.com`).
  static Future<void> ensureVipOwnerHourlySchedule() async {
    if (!Platform.isAndroid || !CloudBackupService.isVipOwnerUser()) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) return;
      if (prefs.getString('cloud_schedule_owner') == uid &&
          prefs.getString('cloud_schedule') == 'hourly') {
        return;
      }
      await set('hourly', wifiOnly: false);
    } catch (_) {}
  }

  static Future<void> disable() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('cloud_schedule', 'off');
    await prefs.remove('cloud_schedule_owner');
    if (Platform.isAndroid) {
      try {
        await Workmanager().cancelByUniqueName(taskName);
      } catch (_) {}
    }
  }
}
