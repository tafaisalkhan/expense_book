import 'dart:math';
import 'package:shared_preferences/shared_preferences.dart';

/// Daily usage quota rules for OCR receipt scans and Voice-to-Expense recordings:
/// - Free users: 1 OCR image/day and 1 voice recording/day (max 10 seconds).
/// - Subscribed users: unlimited OCR images and 10 voice recordings/day (max 10 seconds).
class FeatureQuotaService {
  static const int maxVoiceSeconds = 10;
  static const int freeMaxOcrImagesPerDay = 1;
  static const int freeMaxVoicePerDay = 1;
  static const int subscribedMaxVoicePerDay = 10;

  static String _todayKey([DateTime? now]) {
    final dt = now ?? DateTime.now();
    final y = dt.year.toString().padLeft(4, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  static String _ocrKey([DateTime? now]) => 'quota_ocr_count_${_todayKey(now)}';
  static String _voiceKey([DateTime? now]) =>
      'quota_voice_count_${_todayKey(now)}';

  static Future<int> getOcrUsedToday({DateTime? now}) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_ocrKey(now)) ?? 0;
  }

  static Future<int> getVoiceUsedToday({DateTime? now}) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_voiceKey(now)) ?? 0;
  }

  static Future<bool> canUseOcr({
    required bool isSubscribed,
    DateTime? now,
  }) async {
    if (isSubscribed) return true;
    final used = await getOcrUsedToday(now: now);
    return used < freeMaxOcrImagesPerDay;
  }

  static Future<bool> canUseVoice({
    required bool isSubscribed,
    DateTime? now,
  }) async {
    final used = await getVoiceUsedToday(now: now);
    final limit =
        isSubscribed ? subscribedMaxVoicePerDay : freeMaxVoicePerDay;
    return used < limit;
  }

  /// Returns `null` when unlimited (subscribed), otherwise remaining free scans today.
  static Future<int?> remainingOcrToday({
    required bool isSubscribed,
    DateTime? now,
  }) async {
    if (isSubscribed) return null;
    final used = await getOcrUsedToday(now: now);
    return max(0, freeMaxOcrImagesPerDay - used);
  }

  static Future<int> remainingVoiceToday({
    required bool isSubscribed,
    DateTime? now,
  }) async {
    final used = await getVoiceUsedToday(now: now);
    final limit =
        isSubscribed ? subscribedMaxVoicePerDay : freeMaxVoicePerDay;
    return max(0, limit - used);
  }

  static Future<void> recordOcrUsage({DateTime? now}) async {
    final prefs = await SharedPreferences.getInstance();
    final key = _ocrKey(now);
    final current = prefs.getInt(key) ?? 0;
    await prefs.setInt(key, current + 1);
  }

  static Future<void> recordVoiceUsage({DateTime? now}) async {
    final prefs = await SharedPreferences.getInstance();
    final key = _voiceKey(now);
    final current = prefs.getInt(key) ?? 0;
    await prefs.setInt(key, current + 1);
  }
}
