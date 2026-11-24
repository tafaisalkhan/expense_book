import 'dart:async';
import 'dart:io';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'backup_scheduler.dart';
import 'cloud_backup_service.dart';

class CloudBackupBillingState {
  final bool active, pending, checking, preview;
  final String? activeProductId;
  final DateTime? expiresAt;
  final ProductDetails? monthlyProduct;
  final ProductDetails? yearlyProduct;
  final String? monthlyRecurringPrice;
  final String? yearlyRecurringPrice;
  final String? message;
  const CloudBackupBillingState({
    this.active = false,
    this.pending = false,
    this.checking = true,
    this.preview = false,
    this.activeProductId,
    this.expiresAt,
    this.monthlyProduct,
    this.yearlyProduct,
    this.monthlyRecurringPrice,
    this.yearlyRecurringPrice,
    this.message,
  });

  bool get hasAnyProduct => monthlyProduct != null || yearlyProduct != null;
  String get displayMonthlyPrice =>
      monthlyRecurringPrice ??
      ((monthlyProduct != null && monthlyProduct!.rawPrice > 0)
          ? monthlyProduct!.price
          : '\$0.99');
  String get displayYearlyPrice =>
      yearlyRecurringPrice ??
      ((yearlyProduct != null && yearlyProduct!.rawPrice > 0)
          ? yearlyProduct!.price
          : '\$5.99');
}

class CloudBackupBilling extends StateNotifier<CloudBackupBillingState> {
  final bool preview;
  final service = CloudBackupService();
  StreamSubscription<List<PurchaseDetails>>? _purchases;
  StreamSubscription<User?>? _auth;
  final Set<String> _verifying = {};
  bool _started = false;
  int _refreshGeneration = 0;

  CloudBackupBilling({this.preview = false})
      : super(CloudBackupBillingState(preview: preview)) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(initialize());
    });
  }

  Future<void> initialize() async {
    if (!mounted || _started) return;
    _started = true;
    if (preview) {
      state = const CloudBackupBillingState(
        preview: true,
        checking: false,
        message: 'Cloud backup uses your Google account in the Play Store app.',
      );
      return;
    }
    _purchases = InAppPurchase.instance.purchaseStream.listen((updates) {
      for (final purchase in updates.where((p) =>
          CloudBackupService.subscriptionProductIds.contains(p.productID))) {
        unawaited(_verifyPurchase(purchase));
      }
    }, onError: (Object _) {
      if (mounted) {
        _setMessage('Google Play could not connect. Please try again.');
      }
    });
    _auth = FirebaseAuth.instance.authStateChanges().listen((_) {
      if (mounted) unawaited(refresh());
    });
    unawaited(_loadProducts());
    await refresh();
  }

  void _setMessage(String message) {
    state = CloudBackupBillingState(
      active: state.active,
      activeProductId: state.activeProductId,
      monthlyProduct: state.monthlyProduct,
      yearlyProduct: state.yearlyProduct,
      monthlyRecurringPrice: state.monthlyRecurringPrice,
      yearlyRecurringPrice: state.yearlyRecurringPrice,
      expiresAt: state.expiresAt,
      checking: false,
      preview: preview,
      message: message,
    );
  }

  /// Prefers a Free Trial ($0) or lower introductory offer over the standard
  /// base plan when Google Play returns multiple offers for the same productId.
  ProductDetails _pickPreferredOffer(
    ProductDetails? current,
    ProductDetails candidate,
  ) {
    if (current == null) return candidate;
    if (candidate.rawPrice < current.rawPrice) return candidate;
    return current;
  }

  Future<void> _loadProducts() async {
    if (!Platform.isAndroid) return;
    try {
      if (!await InAppPurchase.instance
          .isAvailable()
          .timeout(const Duration(seconds: 10))) {
        return;
      }
      final result = await InAppPurchase.instance
          .queryProductDetails(CloudBackupService.subscriptionProductIds)
          .timeout(const Duration(seconds: 15));
      if (!mounted) return;
      ProductDetails? monthly;
      ProductDetails? yearly;
      String? monthlyBasePrice;
      String? yearlyBasePrice;
      for (final p in result.productDetails) {
        if (p.id == CloudBackupService.monthlyProductId) {
          monthly = _pickPreferredOffer(monthly, p);
          if (p.rawPrice > 0) monthlyBasePrice = p.price;
        }
        if (p.id == CloudBackupService.yearlyProductId) {
          yearly = _pickPreferredOffer(yearly, p);
          if (p.rawPrice > 0) yearlyBasePrice = p.price;
        }
      }
      state = CloudBackupBillingState(
        active: state.active,
        activeProductId: state.activeProductId,
        expiresAt: state.expiresAt,
        checking: state.checking,
        pending: state.pending,
        preview: preview,
        message: state.message,
        monthlyProduct: monthly,
        yearlyProduct: yearly,
        monthlyRecurringPrice: monthlyBasePrice,
        yearlyRecurringPrice: yearlyBasePrice,
      );
    } catch (_) {
      /* User can still restore a subscription later. */
    }
  }

  Future<void> refresh() async {
    if (preview || !mounted) return;
    final generation = ++_refreshGeneration;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    try {
      final result = await service.access();
      if (!mounted ||
          generation != _refreshGeneration ||
          FirebaseAuth.instance.currentUser?.uid != uid) {
        return;
      }
      final active = result['active'] == true;
      state = CloudBackupBillingState(
        active: active,
        activeProductId: result['productId'] as String?,
        monthlyProduct: state.monthlyProduct,
        yearlyProduct: state.yearlyProduct,
        monthlyRecurringPrice: state.monthlyRecurringPrice,
        yearlyRecurringPrice: state.yearlyRecurringPrice,
        checking: false,
        preview: preview,
        expiresAt: DateTime.tryParse(result['expiresAt'] as String? ?? ''),
      );
      if (!active) await BackupScheduler.disable();
    } catch (_) {
      if (!mounted || generation != _refreshGeneration) return;
      state = CloudBackupBillingState(
        monthlyProduct: state.monthlyProduct,
        yearlyProduct: state.yearlyProduct,
        monthlyRecurringPrice: state.monthlyRecurringPrice,
        yearlyRecurringPrice: state.yearlyRecurringPrice,
        checking: false,
        preview: preview,
        message: 'Sign in with Google to check cloud backup subscription.',
      );
    }
  }

  Future<void> buy(ProductDetails? product) async {
    if (preview || state.pending) return;
    if (product == null) {
      _setMessage(
          'Subscription is not available right now. Check Play Store setup.');
      return;
    }
    try {
      final uid = await service.signedInUid();
      state = CloudBackupBillingState(
        monthlyProduct: state.monthlyProduct,
        yearlyProduct: state.yearlyProduct,
        monthlyRecurringPrice: state.monthlyRecurringPrice,
        yearlyRecurringPrice: state.yearlyRecurringPrice,
        pending: true,
        checking: false,
      );
      final opened = await InAppPurchase.instance.buyNonConsumable(
          purchaseParam: PurchaseParam(
              productDetails: product,
              applicationUserName: CloudBackupService.accountHash(uid)));
      if (!opened && mounted) {
        _setMessage('Checkout could not open. Please try again.');
      }
    } catch (_) {
      if (mounted) _setMessage('Sign in with Google and try checkout again.');
    }
  }

  Future<void> restorePurchases() async {
    if (preview) return;
    try {
      await InAppPurchase.instance
          .restorePurchases()
          .timeout(const Duration(seconds: 30));
      await refresh();
    } catch (_) {
      if (mounted) {
        _setMessage(
            'Your subscription could not be restored. Please try again.');
      }
    }
  }

  Future<void> _verifyPurchase(PurchaseDetails purchase) async {
    if (!mounted) return;
    if (purchase.status == PurchaseStatus.pending) {
      state = CloudBackupBillingState(
        monthlyProduct: state.monthlyProduct,
        yearlyProduct: state.yearlyProduct,
        monthlyRecurringPrice: state.monthlyRecurringPrice,
        yearlyRecurringPrice: state.yearlyRecurringPrice,
        pending: true,
        checking: false,
      );
      return;
    }
    if (purchase.status == PurchaseStatus.canceled ||
        purchase.status == PurchaseStatus.error) {
      _setMessage(purchase.status == PurchaseStatus.canceled
          ? 'Checkout canceled.'
          : 'Payment did not finish. Please try again.');
      return;
    }
    if (![PurchaseStatus.purchased, PurchaseStatus.restored]
        .contains(purchase.status)) {
      return;
    }
    final token = purchase.verificationData.serverVerificationData;
    if (token.isEmpty || !_verifying.add(token)) return;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    _refreshGeneration++;
    try {
      final result = await service.access(
          productId: purchase.productID, purchaseToken: token);
      if (result['active'] != true) throw const CloudSubscriptionRequired();
      if (!mounted || FirebaseAuth.instance.currentUser?.uid != uid) return;
      if (purchase.pendingCompletePurchase) {
        await InAppPurchase.instance.completePurchase(purchase);
      }
      if (!mounted || FirebaseAuth.instance.currentUser?.uid != uid) return;
      state = CloudBackupBillingState(
        active: true,
        activeProductId: purchase.productID,
        monthlyProduct: state.monthlyProduct,
        yearlyProduct: state.yearlyProduct,
        monthlyRecurringPrice: state.monthlyRecurringPrice,
        yearlyRecurringPrice: state.yearlyRecurringPrice,
        checking: false,
        expiresAt: DateTime.tryParse(result['expiresAt'] as String? ?? ''),
        message: 'Cloud backup is now active!',
      );
    } catch (_) {
      if (mounted) {
        _setMessage(
            'Your subscription could not be confirmed yet. Try Restore purchase.');
      }
    } finally {
      _verifying.remove(token);
    }
  }

  @override
  void dispose() {
    _purchases?.cancel();
    _auth?.cancel();
    super.dispose();
  }
}

final monthlyBackupBillingProvider =
    StateNotifierProvider<CloudBackupBilling, CloudBackupBillingState>(
        (ref) => CloudBackupBilling());
