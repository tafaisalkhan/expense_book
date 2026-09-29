import 'dart:async';
import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:myexpence/features/sms_parser/domain/services/sms_parser_service.dart';
import 'package:myexpence/features/sms_parser/presentation/providers/sms_whitelist_provider.dart';

class SmsListenerService {
  static const _eventChannel = EventChannel('com.myexpense.book/sms_receiver');
  static const _methodChannel = MethodChannel('com.myexpense.book/sms_permissions');
  static const String _keyProcessedSms = 'processed_sms_keys_v1';

  StreamSubscription? _subscription;

  /// Fetch set of unique SMS keys that have already been read/processed by MyExpense
  static Future<Set<String>> getProcessedSmsKeys() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = prefs.getStringList(_keyProcessedSms) ?? [];
      return list.toSet();
    } catch (_) {
      return {};
    }
  }

  /// Mark an SMS unique key as read/processed so it will never be read or prompted again
  static Future<void> markSmsAsProcessed(String key) async {
    if (key.trim().isEmpty) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = prefs.getStringList(_keyProcessedSms) ?? [];
      if (!list.contains(key)) {
        list.add(key);
        await prefs.setStringList(_keyProcessedSms, list);
      }
    } catch (_) {}
  }

  /// Check whether RECEIVE_SMS and READ_SMS permissions are granted on Android
  static Future<bool> checkPermission() async {
    try {
      final bool hasPermission = await _methodChannel.invokeMethod('checkSmsPermission');
      return hasPermission;
    } catch (_) {
      return false;
    }
  }

  /// Request RECEIVE_SMS and READ_SMS permissions from user on Android
  static Future<bool> requestPermission() async {
    try {
      final bool requested = await _methodChannel.invokeMethod('requestSmsPermission');
      return requested;
    } catch (_) {
      return false;
    }
  }

  /// Read all existing/unread SMS messages from whitelisted bank senders in Android Inbox asynchronously
  static Future<List<Map<String, dynamic>>> readWhitelistedInboxSms(List<String> whitelist) async {
    try {
      final List<dynamic>? rawList = await _methodChannel.invokeMethod('readWhitelistedInboxSms', {
        'allowedSenders': whitelist,
      });
      if (rawList == null) return [];
      return rawList.map((item) => Map<String, dynamic>.from(item as Map)).toList();
    } catch (_) {
      return [];
    }
  }

  /// Fetch pending SMS notifications saved in state file while app was closed
  static Future<List<Map<String, dynamic>>> getPendingSmsNotifications() async {
    try {
      final String? jsonStr = await _methodChannel.invokeMethod('getPendingSmsNotifications');
      if (jsonStr == null || jsonStr.isEmpty || jsonStr == '[]') return [];
      final List rawList = jsonDecode(jsonStr);
      return rawList.map((item) => Map<String, dynamic>.from(item as Map)).toList();
    } catch (_) {
      return [];
    }
  }

  /// Get initial SMS if app was opened by tapping an SMS system notification
  static Future<Map<String, String>?> getInitialNotificationSms() async {
    try {
      final Map? rawMap = await _methodChannel.invokeMethod('getInitialNotificationSms');
      if (rawMap == null) return null;
      return Map<String, String>.from(rawMap);
    } catch (_) {
      return null;
    }
  }

  /// Syncs inbox SMS messages & pending background SMS notifications saved into state file while app was closed
  /// Deduplicates messages so an SMS is read EXACTLY ONCE and never read again!
  Future<int> syncInboxSms(WidgetRef ref, {required Future<void> Function(SmsParseResult result) onWhitelistedSmsReceived}) async {
    var hasPermission = await checkPermission();
    if (!hasPermission) {
      hasPermission = await requestPermission();
    }
    if (!hasPermission) return 0;

    final whitelist = ref.read(smsWhitelistProvider);
    final processedKeys = await getProcessedSmsKeys();
    int count = 0;

    // 1. Process pending background SMS saved to state file when app was closed
    final pendingMessages = await getPendingSmsNotifications();
    for (final msg in pendingMessages) {
      final sender = msg['sender'] as String? ?? '';
      final body = msg['body'] as String? ?? '';
      final smsId = msg['id'] as String? ?? '';
      final smsKey = smsId.isNotEmpty ? smsId : 'pending_${sender}_${body.hashCode}';

      if (processedKeys.contains(smsKey)) continue;

      if (sender.isNotEmpty && body.isNotEmpty) {
        final parsed = SmsParserService.parseSmsText(
          body,
          sender: sender,
          customAllowedSenders: whitelist,
        );
        await markSmsAsProcessed(smsKey);
        processedKeys.add(smsKey);
        await onWhitelistedSmsReceived(parsed);
        count++;
      }
    }

    // 2. Read all inbox SMS (checks whitelisted as well as non-whitelisted senders for financial transaction keywords)
    final messages = await readWhitelistedInboxSms([]);
    for (final msg in messages) {
      final sender = msg['sender'] as String? ?? '';
      final body = msg['body'] as String? ?? '';
      final date = msg['date']?.toString() ?? '';
      final smsId = msg['id']?.toString() ?? '';
      final smsKey = msg['key'] as String? ?? '${smsId}_${sender}_${date}_${body.hashCode}';

      // SKIP IF ALREADY READ PREVIOUSLY!
      if (processedKeys.contains(smsKey)) continue;

      if (sender.isNotEmpty && body.isNotEmpty) {
        final parsed = SmsParserService.parseSmsText(
          body,
          sender: sender,
          customAllowedSenders: whitelist,
        );
        // Only trigger prompt if transaction amount was detected
        if (parsed.amount > 0) {
          await markSmsAsProcessed(smsKey);
          processedKeys.add(smsKey);
          await onWhitelistedSmsReceived(parsed);
          count++;
        }
      }
    }
    return count;
  }

  Timer? _periodicTimer;

  /// Start periodic 1-minute SMS scheduler that reads unread whitelisted bank SMS from Android inbox (requires ONLY READ_SMS permission)
  void startListening(WidgetRef ref, {required Function(SmsParseResult result) onWhitelistedSmsReceived}) {
    // 1. Immediate sync on start
    syncInboxSms(ref, onWhitelistedSmsReceived: (parsed) async {
      onWhitelistedSmsReceived(parsed);
    });

    // 2. Schedule inbox poll every 1 minute
    _periodicTimer?.cancel();
    _periodicTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      syncInboxSms(ref, onWhitelistedSmsReceived: (parsed) async {
        onWhitelistedSmsReceived(parsed);
      });
    });

    _subscription?.cancel();
    _subscription = _eventChannel.receiveBroadcastStream().listen((dynamic event) {
      if (event is Map) {
        final sender = event['sender'] as String? ?? '';
        final body = event['body'] as String? ?? '';
        final smsKey = 'live_${sender}_${body.hashCode}';

        getProcessedSmsKeys().then((processedKeys) {
          if (processedKeys.contains(smsKey)) return;

          if (sender.isNotEmpty && body.isNotEmpty) {
            final whitelist = ref.read(smsWhitelistProvider);
            final isWhitelisted = SmsParserService.isAllowedSender(sender, customAllowedSenders: whitelist);

            // Only parse & read SMS if sender is in user's whitelisted bank numbers/IDs
            if (isWhitelisted) {
              markSmsAsProcessed(smsKey);
              final parsed = SmsParserService.parseSmsText(
                body,
                sender: sender,
                customAllowedSenders: whitelist,
              );
              onWhitelistedSmsReceived(parsed);
            }
          }
        });
      }
    }, onError: (dynamic error) {
      // Handle stream errors silently
    });
  }

  void stopListening() {
    _periodicTimer?.cancel();
    _periodicTimer = null;
    _subscription?.cancel();
    _subscription = null;
  }
}

final smsListenerServiceProvider = Provider<SmsListenerService>((ref) {
  return SmsListenerService();
});
