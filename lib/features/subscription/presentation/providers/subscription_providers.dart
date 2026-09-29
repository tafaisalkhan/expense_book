import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:myexpence/features/subscription/domain/models/subscription_plan.dart';

class SubscriptionNotifier extends StateNotifier<UserSubscription> {
  SubscriptionNotifier() : super(const UserSubscription()) {
    _loadSubscription();
  }

  static const String _prefKeyTier = 'user_sub_tier';
  static const String _prefKeyExpiry = 'user_sub_expiry';
  static const String _prefKeyTrialStart = 'user_sub_trial_start';

  Future<void> reloadSubscription() async {
    await _loadSubscription();
  }

  Future<void> _loadSubscription() async {
    final prefs = await SharedPreferences.getInstance();
    String? tierCode = prefs.getString(_prefKeyTier);
    String? expiryIso = prefs.getString(_prefKeyExpiry);
    String? trialStartIso = prefs.getString(_prefKeyTrialStart);

    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      try {
        final email = user.email ?? '';
        final sanitizedEmail = email.contains('@')
            ? email.toLowerCase().trim().replaceAll(RegExp(r'[^a-zA-Z0-9_]'), '_')
            : '';
        final docIds = <String>{};
        if (sanitizedEmail.isNotEmpty) docIds.add('user_$sanitizedEmail');
        docIds.add(user.uid);

        for (final docId in docIds) {
          final doc = await FirebaseFirestore.instance
              .collection('user_subscriptions')
              .doc(docId)
              .get();

          if (doc.exists && doc.data() != null) {
            final data = doc.data()!;
            final cloudTier = data['sub_tier'] as String?;
            final cloudExpiry = data['sub_expiry_iso'] as String?;
            final cloudTrialStart = data['sub_trial_start_iso'] as String?;

            if (cloudTier != null &&
                cloudTier.isNotEmpty &&
                cloudTier != SubscriptionTier.free.code) {
              tierCode = cloudTier;
              expiryIso = cloudExpiry;
              trialStartIso = cloudTrialStart;

              await prefs.setString(_prefKeyTier, cloudTier);
              if (cloudExpiry != null) {
                await prefs.setString(_prefKeyExpiry, cloudExpiry);
              }
              if (cloudTrialStart != null) {
                await prefs.setString(_prefKeyTrialStart, cloudTrialStart);
              }
              break;
            }
          }
        }
      } catch (e) {
        debugPrint('Cloud subscription fetch notice: $e');
      }
    }

    if (tierCode == null || tierCode.isEmpty) {
      tierCode = SubscriptionTier.free.code;
      await prefs.setString(_prefKeyTier, tierCode);
    }

    final tier = SubscriptionTier.fromCode(tierCode);
    bool active = false;

    if (tier != SubscriptionTier.free) {
      if (expiryIso != null) {
        final expiryDate = DateTime.tryParse(expiryIso);
        active = expiryDate != null && expiryDate.isAfter(DateTime.now());
      } else {
        active = true;
      }
    }

    if (!mounted) return;

    state = UserSubscription(
      tier: active ? tier : SubscriptionTier.free,
      isActive: active,
      expiryDateIso: expiryIso,
      trialStartIso: trialStartIso,
      isTrial: tier == SubscriptionTier.promo3Month,
    );

    if (active) {
      _syncSubscriptionToCloud(state);
    }
  }

  Future<void> _syncSubscriptionToCloud(UserSubscription sub) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        final email = user.email ?? '';
        final sanitizedEmail = email.contains('@')
            ? email.toLowerCase().trim().replaceAll(RegExp(r'[^a-zA-Z0-9_]'), '_')
            : '';
        final docIds = <String>{};
        if (sanitizedEmail.isNotEmpty) docIds.add('user_$sanitizedEmail');
        docIds.add(user.uid);

        final payload = {
          'userId': user.uid,
          'userEmail': email,
          'sub_tier': sub.tier.code,
          'sub_expiry_iso': sub.expiryDateIso,
          'sub_trial_start_iso': sub.trialStartIso,
          'isPremium': sub.isPremium,
          'isTrial': sub.isTrial,
          'updatedAt': FieldValue.serverTimestamp(),
        };

        for (final docId in docIds) {
          await FirebaseFirestore.instance
              .collection('user_subscriptions')
              .doc(docId)
              .set(payload, SetOptions(merge: true))
              .catchError((_) {});
        }
      }
    } catch (e) {
      debugPrint('Cloud subscription sync notice: $e');
    }
  }

  Future<void> setSubscriptionData({
    required String tierCode,
    String? expiryIso,
    String? trialStartIso,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefKeyTier, tierCode);
    if (expiryIso != null) {
      await prefs.setString(_prefKeyExpiry, expiryIso);
    }
    if (trialStartIso != null) {
      await prefs.setString(_prefKeyTrialStart, trialStartIso);
    }

    await _loadSubscription();
  }

  Future<void> subscribeMonthly() async {
    final prefs = await SharedPreferences.getInstance();
    final expiry = DateTime.now().add(const Duration(days: 30)).toIso8601String();

    await prefs.setString(_prefKeyTier, SubscriptionTier.premiumMonthly.code);
    await prefs.setString(_prefKeyExpiry, expiry);

    state = UserSubscription(
      tier: SubscriptionTier.premiumMonthly,
      isActive: true,
      expiryDateIso: expiry,
      isTrial: false,
    );

    _syncSubscriptionToCloud(state);
  }

  Future<void> subscribeYearly() async {
    final prefs = await SharedPreferences.getInstance();
    final expiry = DateTime.now().add(const Duration(days: 365)).toIso8601String();

    await prefs.setString(_prefKeyTier, SubscriptionTier.premiumYearly.code);
    await prefs.setString(_prefKeyExpiry, expiry);

    state = UserSubscription(
      tier: SubscriptionTier.premiumYearly,
      isActive: true,
      expiryDateIso: expiry,
      isTrial: false,
    );

    _syncSubscriptionToCloud(state);
  }

  Future<void> startFreeTrial() async {
    final prefs = await SharedPreferences.getInstance();
    final now = DateTime.now();
    final expiry = now.add(const Duration(days: 90)).toIso8601String();

    await prefs.setString(_prefKeyTier, SubscriptionTier.promo3Month.code);
    await prefs.setString(_prefKeyExpiry, expiry);
    await prefs.setString(_prefKeyTrialStart, now.toIso8601String());

    state = UserSubscription(
      tier: SubscriptionTier.promo3Month,
      isActive: true,
      expiryDateIso: expiry,
      trialStartIso: now.toIso8601String(),
      isTrial: true,
    );

    _syncSubscriptionToCloud(state);
  }

  Future<bool> redeemPromoCode(String code) async {
    final trimmed = code.trim();
    if (trimmed.isEmpty) return false;

    final prefs = await SharedPreferences.getInstance();
    final now = DateTime.now();
    final expiry = now.add(const Duration(days: 90)).toIso8601String();

    await prefs.setString(_prefKeyTier, SubscriptionTier.promo3Month.code);
    await prefs.setString(_prefKeyExpiry, expiry);
    await prefs.setString(_prefKeyTrialStart, now.toIso8601String());

    state = UserSubscription(
      tier: SubscriptionTier.promo3Month,
      isActive: true,
      expiryDateIso: expiry,
      trialStartIso: now.toIso8601String(),
      isTrial: true,
    );

    _syncSubscriptionToCloud(state);

    return true;
  }

  Future<void> cancelSubscription() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefKeyTier);
    await prefs.remove(_prefKeyExpiry);
    await prefs.remove(_prefKeyTrialStart);

    state = const UserSubscription(
      tier: SubscriptionTier.free,
      isActive: false,
    );

    _syncSubscriptionToCloud(state);
  }
}

final subscriptionProvider = StateNotifierProvider<SubscriptionNotifier, UserSubscription>((ref) {
  return SubscriptionNotifier();
});

final isPremiumUserProvider = Provider<bool>((ref) {
  final sub = ref.watch(subscriptionProvider);
  return sub.isPremium;
});
