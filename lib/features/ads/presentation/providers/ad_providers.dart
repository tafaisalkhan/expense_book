import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:myexpence/features/backup/monthly_backup_billing.dart';

class AdState {
  final int navCount;
  final bool isShowingInterstitial;
  final bool isAdsRemoved;
  final bool hasActiveSubscription;
  final bool noFillThisLaunch;
  final bool rewardedReady;
  final bool sdkReady;
  final bool isShowingRewarded;
  final String? removeAdsPrice;

  const AdState({
    this.navCount = 0,
    this.isShowingInterstitial = false,
    this.isAdsRemoved = false,
    this.hasActiveSubscription = false,
    this.noFillThisLaunch = false,
    this.rewardedReady = false,
    this.sdkReady = false,
    this.isShowingRewarded = false,
    this.removeAdsPrice,
  });

  bool get adsSuppressed => isAdsRemoved || hasActiveSubscription;

  AdState copyWith({
    int? navCount,
    bool? isShowingInterstitial,
    bool? isAdsRemoved,
    bool? hasActiveSubscription,
    bool? noFillThisLaunch,
    bool? rewardedReady,
    bool? sdkReady,
    bool? isShowingRewarded,
    String? removeAdsPrice,
  }) {
    return AdState(
      navCount: navCount ?? this.navCount,
      isShowingInterstitial:
          isShowingInterstitial ?? this.isShowingInterstitial,
      isAdsRemoved: isAdsRemoved ?? this.isAdsRemoved,
      hasActiveSubscription:
          hasActiveSubscription ?? this.hasActiveSubscription,
      noFillThisLaunch: noFillThisLaunch ?? this.noFillThisLaunch,
      rewardedReady: rewardedReady ?? this.rewardedReady,
      sdkReady: sdkReady ?? this.sdkReady,
      isShowingRewarded: isShowingRewarded ?? this.isShowingRewarded,
      removeAdsPrice: removeAdsPrice ?? this.removeAdsPrice,
    );
  }
}

class AdNotifier extends StateNotifier<AdState> {
  static const String removeAdsProductId = 'remove_ads';
  static const int interstitialEveryNNavigations = 3;
  static const int minInterstitialIntervalSec = 120;
  static const int maxInterstitialsPerHour = 10;
  // Version bumped to v3 to ensure any accidentally set flag from earlier local testing is cleared
  static const String _prefKeyAdsRemoved = 'ads_removed_product_v3';
  static const String _legacyPrefKeyAdsRemoved = 'ads_removed_product_v2';
  StreamSubscription<List<PurchaseDetails>>? _purchaseSub;
  InterstitialAd? _preloadedInterstitialAd;
  bool _isLoadingInterstitial = false;
  int _navCounter = 0;
  bool _firstNavSkipped = false;
  DateTime? _lastInterstitialShownAt;
  final List<DateTime> _interstitialHourlyTimestamps = <DateTime>[];
  RewardedAd? _rewardedAd;
  bool _isLoadingRewarded = false;
  bool _started = false;
  bool _noticeShown = false;
  bool noAdsNoticeOpen = false;
  Timer? _rewardedLoadTimeout;
  Timer? _interstitialLoadTimeout;
  final bool mobile;
  final bool releaseBuild;
  final Future<void> Function()? initializeAds;
  final void Function(String, RewardedAdLoadCallback)? loadRewarded;
  final void Function(String, InterstitialAdLoadCallback)? loadInterstitial;
  final Future<String?> Function()? readAppId;
  final bool enablePurchases;

  AdNotifier(
      {bool autoStart = true,
      bool? mobile,
      this.releaseBuild = kReleaseMode,
      this.initializeAds,
      this.loadRewarded,
      this.loadInterstitial,
      this.readAppId,
      this.enablePurchases = true})
      : mobile = mobile ?? (!kIsWeb && (Platform.isAndroid || Platform.isIOS)),
        super(const AdState()) {
    if (autoStart) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(start());
      });
    }
  }

  static String get interstitialAdUnitId {
    if (!kIsWeb && Platform.isAndroid) {
      return const String.fromEnvironment('ADMOB_INTERSTITIAL_ID',
          defaultValue: 'ca-app-pub-3940256099942544/1033173712');
    } else if (!kIsWeb && Platform.isIOS) {
      return 'ca-app-pub-3940256099942544/4411468910';
    }
    return const String.fromEnvironment('ADMOB_INTERSTITIAL_ID',
        defaultValue: 'ca-app-pub-3940256099942544/1033173712');
  }

  static String get rewardedAdUnitId {
    if (!kIsWeb && Platform.isAndroid) {
      return const String.fromEnvironment('ADMOB_REWARDED_ID',
          defaultValue: 'ca-app-pub-3940256099942544/5224354917');
    } else if (!kIsWeb && Platform.isIOS) {
      return 'ca-app-pub-3940256099942544/1712485313';
    }
    return const String.fromEnvironment('ADMOB_REWARDED_ID',
        defaultValue: 'ca-app-pub-3940256099942544/5224354917');
  }

  static String get bannerAdUnitId =>
      const String.fromEnvironment('ADMOB_BANNER_ID').isNotEmpty
          ? const String.fromEnvironment('ADMOB_BANNER_ID')
          : (!kIsWeb && Platform.isIOS
              ? 'ca-app-pub-3940256099942544/2934735716'
              : 'ca-app-pub-3940256099942544/6300978111');

  static bool validReleaseId(String id) =>
      id.startsWith('ca-app-pub-') && !id.contains('3940256099942544');

  bool get adsAllowed =>
      mounted &&
      mobile &&
      state.sdkReady &&
      !state.adsSuppressed &&
      !state.noFillThisLaunch;

  /// Suppresses or restores ads dynamically when the Cloud Backup subscription changes.
  void setSubscriptionActive(bool active) {
    if (!mounted || state.hasActiveSubscription == active) return;
    if (active) {
      _rewardedLoadTimeout?.cancel();
      _interstitialLoadTimeout?.cancel();
      _rewardedAd?.dispose();
      _rewardedAd = null;
      _preloadedInterstitialAd?.dispose();
      _preloadedInterstitialAd = null;
      _isLoadingRewarded = false;
      _isLoadingInterstitial = false;
      state = state.copyWith(hasActiveSubscription: true, rewardedReady: false);
    } else {
      state = state.copyWith(hasActiveSubscription: false);
      if (adsAllowed) {
        _preloadRewardedAd();
        _preloadInterstitialAd();
      }
    }
  }

  /// Starts only after the first frame. Billing and ads never delay runApp.
  Future<void> start() async {
    if (_started || !mounted) return;
    _started = true;
    await _loadAdState();
    if (!mounted || !mobile) return;
    if (enablePurchases) {
      _initInAppPurchase();
      unawaited(restorePurchases());
      unawaited(_loadRemoveAdsPrice());
    }
    if (state.adsSuppressed || state.noFillThisLaunch) return;
    if (releaseBuild &&
        [interstitialAdUnitId, rewardedAdUnitId, bannerAdUnitId]
            .any((id) => !validReleaseId(id))) {
      markUnavailable();
      return;
    }
    try {
      // Read the installed Android manifest, not a possibly different Dart ID.
      if (releaseBuild) {
        final appId = await (readAppId?.call() ??
                (Platform.isAndroid
                    ? const MethodChannel('com.myexpense.book/ad_config')
                        .invokeMethod<String>('getAppId')
                    : Future.value(
                        const String.fromEnvironment('ADMOB_APP_ID'))))
            .timeout(const Duration(seconds: 5));
        if (!mounted) return;
        if (appId == null || !validReleaseId(appId)) {
          markUnavailable();
          return;
        }
      }
      await (initializeAds?.call() ??
              MobileAds.instance.initialize().then((_) {}))
          .timeout(const Duration(seconds: 10));
      if (!mounted || state.noFillThisLaunch || state.adsSuppressed) return;
      state = state.copyWith(sdkReady: true);
      _preloadRewardedAd();
      _preloadInterstitialAd();
    } catch (_) {
      markUnavailable();
    }
  }

  /// Sticky for this process only. A later callback can never re-enable ads.
  void markUnavailable() {
    if (!mounted || state.noFillThisLaunch || state.adsSuppressed) return;
    _rewardedLoadTimeout?.cancel();
    _interstitialLoadTimeout?.cancel();
    _rewardedAd?.dispose();
    _rewardedAd = null;
    _preloadedInterstitialAd?.dispose();
    _preloadedInterstitialAd = null;
    _isLoadingRewarded = false;
    _isLoadingInterstitial = false;
    state = state.copyWith(noFillThisLaunch: true, rewardedReady: false);
  }

  bool claimNoAdsNotice() {
    if (!state.noFillThisLaunch ||
        state.adsSuppressed ||
        _noticeShown ||
        state.isShowingInterstitial ||
        state.isShowingRewarded) {
      return false;
    }
    _noticeShown = true;
    noAdsNoticeOpen = true;
    return true;
  }

  void finishNoAdsNotice() {
    noAdsNoticeOpen = false;
    if (mounted) state = state.copyWith();
  }

  Future<void> _loadAdState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_legacyPrefKeyAdsRemoved);
      await prefs.remove('ads_removed_product_v1');
      final isRemoved = prefs.getBool(_prefKeyAdsRemoved) ?? false;
      if (!mounted) return;
      state = state.copyWith(isAdsRemoved: isRemoved);
    } catch (_) {}
  }

  /// Reset ads removed state (useful for QA / testing to guarantee ads show)
  Future<void> resetAds() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_prefKeyAdsRemoved);
      await prefs.remove(_legacyPrefKeyAdsRemoved);
      await prefs.remove('ads_removed_product_v1');
    } catch (_) {}
    state = state.copyWith(isAdsRemoved: false);
    _preloadInterstitialAd();
    _preloadRewardedAd();
  }

  void _initInAppPurchase() {
    if (kIsWeb) return;
    try {
      final Stream<List<PurchaseDetails>> purchaseUpdated =
          InAppPurchase.instance.purchaseStream;
      _purchaseSub = purchaseUpdated.listen(
        (purchaseDetailsList) {
          _listenToPurchaseUpdated(purchaseDetailsList);
        },
        onDone: () => _purchaseSub?.cancel(),
        onError: (error) {
          debugPrint('InAppPurchase stream notice: $error');
        },
      );
    } catch (e) {
      debugPrint('InAppPurchase init notice: $e');
    }
  }

  Future<void> _listenToPurchaseUpdated(
      List<PurchaseDetails> purchaseDetailsList) async {
    for (final purchaseDetails in purchaseDetailsList) {
      if (purchaseDetails.productID == removeAdsProductId) {
        if (purchaseDetails.status == PurchaseStatus.purchased ||
            purchaseDetails.status == PurchaseStatus.restored) {
          if (purchaseDetails.pendingCompletePurchase) {
            await InAppPurchase.instance.completePurchase(purchaseDetails);
          }
          final prefs = await SharedPreferences.getInstance();
          await prefs.setBool(_prefKeyAdsRemoved, true);
          state = state.copyWith(isAdsRemoved: true);
          debugPrint('In-App Purchase verified & restored: remove_ads = true');
        } else if (purchaseDetails.status == PurchaseStatus.error) {
          final errStr = purchaseDetails.error?.message.toLowerCase() ?? '';
          final errCode = purchaseDetails.error?.code.toLowerCase() ?? '';
          if (errCode.contains('already') ||
              errStr.contains('already') ||
              errCode.contains('owned') ||
              errStr.contains('owned')) {
            final prefs = await SharedPreferences.getInstance();
            await prefs.setBool(_prefKeyAdsRemoved, true);
            state = state.copyWith(isAdsRemoved: true);
            debugPrint('Item already owned: restored remove_ads = true');
          }
        }
      }
    }
  }

  /// Purchase `remove_ads` In-App Purchase product (Google Play Product ID: `remove_ads`)
  Future<bool> purchaseRemoveAds() async {
    try {
      if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
        final bool isAvailable = await InAppPurchase.instance.isAvailable();
        if (isAvailable) {
          final ProductDetailsResponse response = await InAppPurchase.instance
              .queryProductDetails({removeAdsProductId});
          if (response.error == null && response.productDetails.isNotEmpty) {
            final ProductDetails productDetails = response.productDetails.first;
            final PurchaseParam purchaseParam =
                PurchaseParam(productDetails: productDetails);
            await InAppPurchase.instance
                .buyNonConsumable(purchaseParam: purchaseParam);
            return true;
          }
        }
      }
    } catch (e) {
      debugPrint('Google Play In-App Purchase billing notice: $e');
      // If purchase failed because item is already owned on Google Play account:
      await restorePurchases();
    }

    // In debug mode, if Google Play Billing is unavailable (e.g. testing local APK),
    // allow testing ad removal so developers and QA can verify the ad-free experience.
    if (kDebugMode) {
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool(_prefKeyAdsRemoved, true);
        state = state.copyWith(isAdsRemoved: true);
        return true;
      } catch (_) {}
    }

    return false;
  }

  /// Restore Google Play In-App Purchases for `remove_ads`
  Future<void> restorePurchases() async {
    try {
      if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
        final bool isAvailable = await InAppPurchase.instance.isAvailable();
        if (isAvailable) {
          await InAppPurchase.instance.restorePurchases();
        }
      }
    } catch (e) {
      debugPrint('Restore purchases notice: $e');
    }
  }

  Future<void> _loadRemoveAdsPrice() async {
    if (!mounted || !mobile || !enablePurchases || state.adsSuppressed) return;
    try {
      final available = await InAppPurchase.instance
          .isAvailable()
          .timeout(const Duration(seconds: 10));
      if (!available || !mounted) return;
      final response = await InAppPurchase.instance
          .queryProductDetails({removeAdsProductId})
          .timeout(const Duration(seconds: 15));
      if (mounted &&
          response.error == null &&
          response.productDetails.isNotEmpty) {
        state = state.copyWith(
          removeAdsPrice: response.productDetails.first.price,
        );
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _rewardedLoadTimeout?.cancel();
    _interstitialLoadTimeout?.cancel();
    _purchaseSub?.cancel();
    _rewardedAd?.dispose();
    _preloadedInterstitialAd?.dispose();
    super.dispose();
  }

  void _preloadInterstitialAd() {
    if (!adsAllowed ||
        _isLoadingInterstitial ||
        _preloadedInterstitialAd != null) {
      return;
    }
    _isLoadingInterstitial = true;
    _interstitialLoadTimeout =
        Timer(const Duration(seconds: 15), markUnavailable);
    final callbacks = InterstitialAdLoadCallback(
      onAdLoaded: (ad) {
        _interstitialLoadTimeout?.cancel();
        _isLoadingInterstitial = false;
        if (!adsAllowed) {
          ad.dispose();
          return;
        }
        _preloadedInterstitialAd = ad;
      },
      onAdFailedToLoad: (_) {
        _interstitialLoadTimeout?.cancel();
        _isLoadingInterstitial = false;
        markUnavailable();
      },
    );
    try {
      if (loadInterstitial != null) {
        loadInterstitial!(interstitialAdUnitId, callbacks);
      } else {
        unawaited(InterstitialAd.load(
                adUnitId: interstitialAdUnitId,
                request: const AdRequest(),
                adLoadCallback: callbacks)
            .catchError((Object _) => markUnavailable()));
      }
    } catch (_) {
      markUnavailable();
    }
  }

  void _preloadRewardedAd() {
    if (!adsAllowed || _isLoadingRewarded || _rewardedAd != null) return;
    _isLoadingRewarded = true;
    _rewardedLoadTimeout = Timer(const Duration(seconds: 15), markUnavailable);
    final callbacks = RewardedAdLoadCallback(
      onAdLoaded: (ad) {
        _rewardedLoadTimeout?.cancel();
        _isLoadingRewarded = false;
        if (!adsAllowed) {
          ad.dispose();
          return;
        }
        _rewardedAd = ad;
        state = state.copyWith(rewardedReady: true);
      },
      onAdFailedToLoad: (_) {
        _rewardedLoadTimeout?.cancel();
        _isLoadingRewarded = false;
        markUnavailable();
      },
    );
    try {
      if (loadRewarded != null) {
        loadRewarded!(rewardedAdUnitId, callbacks);
      } else {
        unawaited(RewardedAd.load(
                adUnitId: rewardedAdUnitId,
                request: const AdRequest(),
                rewardedAdLoadCallback: callbacks)
            .catchError((Object _) => markUnavailable()));
      }
    } catch (_) {
      markUnavailable();
    }
  }

  void recordNavigation(BuildContext context, [WidgetRef? ref]) {
    if (!adsAllowed) return;
    state = state.copyWith(navCount: state.navCount + 1);
    // First-navigation interstitial: Disabled
    if (!_firstNavSkipped) {
      _firstNavSkipped = true;
      return;
    }
    _navCounter++;
    if (_navCounter >= interstitialEveryNNavigations) {
      if (_canShowInterstitialNow()) {
        _navCounter = 0;
        if (context.mounted) showInterstitialAd(context, ref);
      }
    }
  }

  bool _canShowInterstitialNow() {
    if (!adsAllowed || state.isShowingInterstitial || state.isShowingRewarded) {
      return false;
    }
    final now = DateTime.now();
    // Minimum interval between interstitials: 120 seconds
    if (_lastInterstitialShownAt != null &&
        now.difference(_lastInterstitialShownAt!).inSeconds <
            minInterstitialIntervalSec) {
      return false;
    }
    // Maximum interstitials per hour: 10 (rolling 3600s window)
    _interstitialHourlyTimestamps
        .removeWhere((t) => now.difference(t).inSeconds >= 3600);
    if (_interstitialHourlyTimestamps.length >= maxInterstitialsPerHour) {
      return false;
    }
    return true;
  }

  void showInterstitialAd(BuildContext context, [WidgetRef? ref]) {
    if (!_canShowInterstitialNow()) {
      return;
    }
    final ad = _preloadedInterstitialAd;
    if (ad == null) return;
    _preloadedInterstitialAd = null;
    final now = DateTime.now();
    _lastInterstitialShownAt = now;
    _interstitialHourlyTimestamps.add(now);
    state = state.copyWith(isShowingInterstitial: true);
    bool finished = false;
    void finish({bool failed = false}) {
      if (finished) return;
      finished = true;
      ad.dispose();
      if (!mounted) return;
      state = state.copyWith(isShowingInterstitial: false);
      if (failed) {
        markUnavailable();
      } else {
        _preloadInterstitialAd();
      }
    }

    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (_) => finish(),
      onAdFailedToShowFullScreenContent: (_, __) => finish(failed: true),
    );
    try {
      unawaited(ad.show().catchError((Object _) => finish(failed: true)));
    } catch (_) {
      finish(failed: true);
    }
  }

  /// Only a genuinely ready ad can gate a feature. No-fill grants access;
  /// closing an available ad before earning its reward does not.
  void runWithRewardedAd(
    BuildContext context, {
    required String featureName,
    required VoidCallback onRewardGranted,
  }) {
    if (!context.mounted || !mounted) return;
    if (state.isShowingRewarded || state.isShowingInterstitial) return;
    if (state.adsSuppressed || state.noFillThisLaunch || !mobile) {
      onRewardGranted();
      return;
    }
    final ad = _rewardedAd;
    if (!state.rewardedReady || ad == null) {
      markUnavailable();
      onRewardGranted();
      return;
    }
    _rewardedAd = null;
    state = state.copyWith(rewardedReady: false, isShowingRewarded: true);
    bool earned = false;
    bool finished = false;
    bool granted = false;
    void grant() {
      if (granted || !mounted || !context.mounted) return;
      granted = true;
      onRewardGranted();
    }

    void finish({bool failed = false}) {
      if (finished) return;
      finished = true;
      ad.dispose();
      if (!mounted) return;
      state = state.copyWith(isShowingRewarded: false);
      if (failed) {
        markUnavailable();
      }
      if (earned || failed) grant();
      if (!failed) _preloadRewardedAd();
    }

    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (_) => finish(),
      onAdFailedToShowFullScreenContent: (_, __) => finish(failed: true),
    );
    try {
      unawaited(ad.show(onUserEarnedReward: (_, __) {
        earned = true;
        if (finished) grant();
      }).catchError((Object _) => finish(failed: true)));
    } catch (_) {
      finish(failed: true);
    }
  }
}

final adNotifierProvider = StateNotifierProvider<AdNotifier, AdState>((ref) {
  final notifier = AdNotifier();
  ref.listen<bool>(
    monthlyBackupBillingProvider.select((s) => s.active),
    (_, active) => notifier.setSubscriptionActive(active),
    fireImmediately: true,
  );
  return notifier;
});

final isAdsRemovedProvider = Provider<bool>((ref) {
  final adState = ref.watch(adNotifierProvider);
  return adState.adsSuppressed;
});

/// Unavailable placements collapse entirely, including their SafeArea padding.
class AdBannerWidget extends ConsumerStatefulWidget {
  final bool isTop;
  const AdBannerWidget({super.key, this.isTop = false});
  @override
  ConsumerState<AdBannerWidget> createState() => _AdBannerWidgetState();
}

class _AdBannerWidgetState extends ConsumerState<AdBannerWidget> {
  BannerAd? _bannerAd;
  bool _isAdLoaded = false;
  bool _requested = false;
  Timer? _timeout;

  void _loadBannerAd() {
    if (!mounted || _requested) return;
    final notifier = ref.read(adNotifierProvider.notifier);
    if (!notifier.adsAllowed) return;
    _requested = true;
    _timeout = Timer(const Duration(seconds: 15), notifier.markUnavailable);
    try {
      _bannerAd = BannerAd(
        adUnitId: AdNotifier.bannerAdUnitId,
        size: AdSize.banner,
        request: const AdRequest(),
        listener: BannerAdListener(
          onAdLoaded: (ad) {
            _timeout?.cancel();
            if (!mounted) {
              ad.dispose();
              return;
            }
            if (!ref.read(adNotifierProvider.notifier).adsAllowed) {
              _bannerAd = null;
              ad.dispose();
              return;
            }
            setState(() => _isAdLoaded = true);
          },
          onAdFailedToLoad: (ad, error) {
            _timeout?.cancel();
            ad.dispose();
            if (!mounted) return;
            setState(() {
              _bannerAd = null;
              _isAdLoaded = false;
            });
            ref.read(adNotifierProvider.notifier).markUnavailable();
          },
        ),
      );
      unawaited(_bannerAd!
          .load()
          .catchError((Object _) => notifier.markUnavailable()));
    } catch (_) {
      notifier.markUnavailable();
    }
  }

  void _releaseBanner() {
    _timeout?.cancel();
    final ad = _bannerAd;
    _bannerAd = null;
    _isAdLoaded = false;
    WidgetsBinding.instance.addPostFrameCallback((_) => ad?.dispose());
  }

  @override
  void dispose() {
    _releaseBanner();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(adNotifierProvider);
    final notifier = ref.read(adNotifierProvider.notifier);
    if (!notifier.mobile || state.adsSuppressed || state.noFillThisLaunch) {
      if (_bannerAd != null) _releaseBanner();
      return const SizedBox.shrink();
    }
    if (state.sdkReady && !_requested) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _loadBannerAd());
    }
    if (!_isAdLoaded || _bannerAd == null) return const SizedBox.shrink();
    return SafeArea(
      top: widget.isTop,
      bottom: !widget.isTop,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Center(
            child: SizedBox(
          width: _bannerAd!.size.width.toDouble(),
          height: _bannerAd!.size.height.toDouble(),
          child: AdWidget(ad: _bannerAd!),
        )),
      ),
    );
  }
}
