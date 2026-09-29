import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SmsWhitelistNotifier extends StateNotifier<List<String>> {
  static const String _keyWhitelist = 'sms_whitelisted_senders_v2';
  static const String _keyOldWhitelist = 'sms_whitelisted_senders';

  static const List<String> defaultSenders = [];

  SmsWhitelistNotifier() : super(const []) {
    _loadWhitelist();
  }

  Future<void> _loadWhitelist() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.containsKey(_keyOldWhitelist)) {
      await prefs.remove(_keyOldWhitelist);
    }
    final saved = prefs.getStringList(_keyWhitelist);
    state = saved ?? const [];
  }

  Future<void> clearAll() async {
    state = const [];
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_keyWhitelist, const []);
  }

  Future<void> addSender(String sender) async {
    final clean = sender.trim();
    if (clean.isEmpty) return;
    if (!state.any((s) => s.toLowerCase() == clean.toLowerCase())) {
      final updated = [...state, clean];
      state = updated;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_keyWhitelist, updated);
    }
  }

  Future<void> removeSender(String sender) async {
    final updated = state.where((s) => s.toLowerCase() != sender.toLowerCase()).toList();
    state = updated;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_keyWhitelist, updated);
  }

  Future<void> resetToDefaults() async {
    state = defaultSenders;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_keyWhitelist, defaultSenders);
  }
}

final smsWhitelistProvider = StateNotifierProvider<SmsWhitelistNotifier, List<String>>((ref) {
  return SmsWhitelistNotifier();
});
