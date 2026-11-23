import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

enum SupportAction { rate, share, coffee }

/// Kept in the app's ProviderScope, so route changes cannot reset the limit.
class SupportPromptSession {
  final Random random;
  bool _visitedHome = false;
  bool _leftHome = false;
  bool _shown = false;
  String _path = '';
  SupportPromptSession({Random? random}) : random = random ?? Random();

  void visit(String path) {
    _path = path;
    if (path == '/dashboard') {
      _visitedHome = true;
    } else if (_visitedHome && path != '/login') {
      _leftHome = true;
    }
  }

  bool get eligible => _path == '/dashboard' && _leftHome && !_shown;
  SupportAction? claim() {
    if (!eligible) return null;
    _shown = true;
    return SupportAction.values[random.nextInt(SupportAction.values.length)];
  }
}

final supportPromptSessionProvider = Provider((ref) => SupportPromptSession());

enum CoffeeStatus {
  loading,
  ready,
  pending,
  purchased,
  unavailable,
  canceled,
  error
}

class CoffeeState {
  final CoffeeStatus status;
  final ProductDetails? product;
  final String? message;
  final bool preview;
  final bool updateDownloaded;
  const CoffeeState(
      {this.status = CoffeeStatus.loading,
      this.product,
      this.message,
      this.preview = false,
      this.updateDownloaded = false});

  CoffeeState copyWith({
    CoffeeStatus? status,
    ProductDetails? product,
    String? message,
    bool? preview,
    bool? updateDownloaded,
  }) {
    return CoffeeState(
      status: status ?? this.status,
      product: product ?? this.product,
      message: message ?? this.message,
      preview: preview ?? this.preview,
      updateDownloaded: updateDownloaded ?? this.updateDownloaded,
    );
  }
}

class SupportActions extends StateNotifier<CoffeeState> {
  static const coffeeProductId = 'cofee';
  static const _channel = MethodChannel('com.myexpense.book/support');
  final bool preview;
  final InAppPurchase _billing;
  StreamSubscription<List<PurchaseDetails>>? _subscription;
  bool _started = false;

  SupportActions({this.preview = false, InAppPurchase? billing})
      : _billing = billing ?? InAppPurchase.instance,
        super(CoffeeState(preview: preview)) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(initialize());
    });
  }

  Future<void> initialize() async {
    if (_started || !mounted) return;
    _started = true;
    if (preview) {
      state =
          const CoffeeState(status: CoffeeStatus.unavailable, preview: true);
      return;
    }
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onUpdateDownloaded' && mounted) {
        state = state.copyWith(updateDownloaded: true);
      }
    });
    try {
      _subscription = _billing.purchaseStream.listen((purchases) {
        unawaited(_purchasesUpdated(purchases));
      }, onError: (Object _) {
        if (mounted) {
          state = CoffeeState(
              status: CoffeeStatus.error,
              product: state.product,
              message:
                  'Google Play checkout is unavailable. Please try again later.',
              updateDownloaded: state.updateDownloaded);
        }
      });
      if (!await _billing.isAvailable().timeout(const Duration(seconds: 10))) {
        if (mounted) {
          state = CoffeeState(
              status: CoffeeStatus.unavailable,
              updateDownloaded: state.updateDownloaded);
        }
        return;
      }
      final response = await _billing.queryProductDetails(
          {coffeeProductId}).timeout(const Duration(seconds: 15));
      if (!mounted) return;
      final products =
          response.productDetails.where((p) => p.id == coffeeProductId);
      if (response.error != null || products.isEmpty) {
        state = CoffeeState(
            status: CoffeeStatus.unavailable,
            updateDownloaded: state.updateDownloaded);
      } else {
        state = CoffeeState(
            status: state.status == CoffeeStatus.pending ||
                    state.status == CoffeeStatus.purchased
                ? state.status
                : CoffeeStatus.ready,
            product: products.first,
            updateDownloaded: state.updateDownloaded);
      }
    } catch (_) {
      if (mounted) {
        state = CoffeeState(
            status: CoffeeStatus.unavailable,
            updateDownloaded: state.updateDownloaded);
      }
    }
  }

  Future<void> _purchasesUpdated(List<PurchaseDetails> purchases) async {
    for (final purchase
        in purchases.where((p) => p.productID == coffeeProductId)) {
      try {
        if (purchase.status == PurchaseStatus.pending) {
          if (mounted) {
            state = CoffeeState(
                status: CoffeeStatus.pending,
                product: state.product,
                updateDownloaded: state.updateDownloaded);
          }
          continue;
        }
        if (purchase.pendingCompletePurchase &&
            (purchase.status == PurchaseStatus.purchased ||
                purchase.status == PurchaseStatus.restored)) {
          await _billing.completePurchase(purchase);
        }
        if (!mounted) return;
        final status = switch (purchase.status) {
          PurchaseStatus.purchased => CoffeeStatus.purchased,
          PurchaseStatus.canceled => CoffeeStatus.canceled,
          PurchaseStatus.error => CoffeeStatus.error,
          _ => CoffeeStatus.ready,
        };
        state = CoffeeState(
            status: status,
            product: state.product,
            message: status == CoffeeStatus.error
                ? 'Payment was not completed. Please try again.'
                : null,
            updateDownloaded: state.updateDownloaded);
      } catch (_) {
        if (mounted) {
          state = CoffeeState(
              status: CoffeeStatus.error,
              product: state.product,
              message:
                  'We could not confirm checkout. Please try again later.',
              updateDownloaded: state.updateDownloaded);
        }
      }
    }
  }

  Future<void> buyCoffee() async {
    if (preview ||
        state.product == null ||
        state.status == CoffeeStatus.pending) {
      return;
    }
    final product = state.product!;
    state = CoffeeState(
        status: CoffeeStatus.pending,
        product: product,
        updateDownloaded: state.updateDownloaded);
    try {
      final started = await _billing.buyConsumable(
          purchaseParam: PurchaseParam(productDetails: product));
      if (!started && mounted) {
        state = CoffeeState(
            status: CoffeeStatus.error,
            product: product,
            message: 'Checkout could not open. Please try again.',
            updateDownloaded: state.updateDownloaded);
      }
    } catch (_) {
      if (mounted) {
        state = CoffeeState(
            status: CoffeeStatus.error,
            product: product,
            message:
                'Google Play checkout is unavailable. Please try again later.',
            updateDownloaded: state.updateDownloaded);
      }
    }
  }

  Future<void> rate() => _channel.invokeMethod<void>('rateApp');
  Future<void> share() => _channel.invokeMethod<void>('shareApp');

  Future<void> checkForAppUpdate({bool force = false}) async {
    if (preview || kIsWeb || !Platform.isAndroid) return;
    try {
      await _channel.invokeMethod<void>('checkForAppUpdate', {'force': force});
    } catch (_) {}
  }

  Future<void> completeAppUpdate() async {
    if (preview || kIsWeb || !Platform.isAndroid) return;
    try {
      await _channel.invokeMethod<void>('completeAppUpdate');
    } catch (_) {}
  }

  @override
  void dispose() {
    if (!preview) _channel.setMethodCallHandler(null);
    _subscription?.cancel();
    super.dispose();
  }
}

final supportActionsProvider =
    StateNotifierProvider<SupportActions, CoffeeState>(
        (ref) => SupportActions());
