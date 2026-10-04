import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppErrorLogger {
  static const String _logKey = 'app_startup_error_logs_v1';

  /// Log an exception or error message with timestamp
  static Future<void> logError(String tag, Object error, [StackTrace? stackTrace]) async {
    final timestamp = DateTime.now().toIso8601String();
    final logEntry = '[$timestamp] [$tag] $error\n${stackTrace ?? ''}';

    debugPrint('AppErrorLogger: $logEntry');

    try {
      final prefs = await SharedPreferences.getInstance();
      final currentLogs = prefs.getStringList(_logKey) ?? [];
      currentLogs.add(logEntry);
      
      // Keep last 50 log entries to prevent excessive memory usage
      if (currentLogs.length > 50) {
        currentLogs.removeRange(0, currentLogs.length - 50);
      }
      
      await prefs.setStringList(_logKey, currentLogs);
    } catch (_) {}
  }

  /// Get stored diagnostic logs
  static Future<List<String>> getLogs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getStringList(_logKey) ?? [];
    } catch (_) {
      return [];
    }
  }

  /// Clear diagnostic logs
  static Future<void> clearLogs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_logKey);
    } catch (_) {}
  }
}
