import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AdState {
  final int navCount;
  final bool isShowingInterstitial;
  final bool isAdsRemoved;

  const AdState({
    this.navCount = 0,
    this.isShowingInterstitial = false,
    this.isAdsRemoved = false,
  });

  AdState copyWith({
    int? navCount,
    bool? isShowingInterstitial,
    bool? isAdsRemoved,
  }) {
    return AdState(
      navCount: navCount ?? this.navCount,
      isShowingInterstitial: isShowingInterstitial ?? this.isShowingInterstitial,
      isAdsRemoved: isAdsRemoved ?? this.isAdsRemoved,
    );
  }
}

class AdNotifier extends StateNotifier<AdState> {
  static const String removeAdsProductId = 'remove_ads';
  // Version bumped to v3 to ensure any accidentally set flag from earlier local testing is cleared
  static const String _prefKeyAdsRemoved = 'ads_removed_product_v3';
  static const String _legacyPrefKeyAdsRemoved = 'ads_removed_product_v2';
  StreamSubscription<List<PurchaseDetails>>? _purchaseSub;
  InterstitialAd? _preloadedInterstitialAd;
  bool _isLoadingInterstitial = false;
  int _navCounter = 0;
  Timer? _interstitialRetryTimer;

  AdNotifier() : super(const AdState()) {
    _loadAdState();
    _initInAppPurchase();
    // Auto-retry preloading Interstitial Ad periodically so when internet becomes available,
    // the ad is immediately loaded and ready for navigation transitions.
    _interstitialRetryTimer = Timer.periodic(const Duration(seconds: 15), (timer) {
      if (!state.isAdsRemoved && _preloadedInterstitialAd == null && !_isLoadingInterstitial) {
        _preloadInterstitialAd();
      }
    });
  }

  static String get interstitialAdUnitId {
    if (!kIsWeb && Platform.isAndroid) {
      return 'ca-app-pub-1852108665659812/6272840780'; // Production Interstitial Ad ID
    } else if (!kIsWeb && Platform.isIOS) {
      return 'ca-app-pub-3940256099942544/4411468910';
    }
    return 'ca-app-pub-1852108665659812/6272840780';
  }

  static String get rewardedAdUnitId {
    if (!kIsWeb && Platform.isAndroid) {
      return 'ca-app-pub-1852108665659812/7203527509'; // Production Rewarded Ad ID
    } else if (!kIsWeb && Platform.isIOS) {
      return 'ca-app-pub-3940256099942544/1712485313';
    }
    return 'ca-app-pub-1852108665659812/7203527509';
  }

  Future<void> _loadAdState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_legacyPrefKeyAdsRemoved);
      await prefs.remove('ads_removed_product_v1');
      final isRemoved = prefs.getBool(_prefKeyAdsRemoved) ?? false;
      state = state.copyWith(isAdsRemoved: isRemoved);
    } catch (_) {}
    // Re-sync with Google Play so genuine `remove_ads` owners are restored.
    await restorePurchases();
    if (!state.isAdsRemoved) {
      _preloadInterstitialAd();
    }
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
  }

  void _initInAppPurchase() {
    if (kIsWeb) return;
    try {
      final Stream<List<PurchaseDetails>> purchaseUpdated = InAppPurchase.instance.purchaseStream;
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

  Future<void> _listenToPurchaseUpdated(List<PurchaseDetails> purchaseDetailsList) async {
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
          if (errCode.contains('already') || errStr.contains('already') || errCode.contains('owned') || errStr.contains('owned')) {
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
          final ProductDetailsResponse response =
              await InAppPurchase.instance.queryProductDetails({removeAdsProductId});
          if (response.error == null && response.productDetails.isNotEmpty) {
            final ProductDetails productDetails = response.productDetails.first;
            final PurchaseParam purchaseParam = PurchaseParam(productDetails: productDetails);
            await InAppPurchase.instance.buyNonConsumable(purchaseParam: purchaseParam);
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

  @override
  void dispose() {
    _interstitialRetryTimer?.cancel();
    _purchaseSub?.cancel();
    _preloadedInterstitialAd?.dispose();
    super.dispose();
  }

  /// Preloads an Interstitial Ad in advance so it can be shown immediately without delay
  void _preloadInterstitialAd() {
    if (state.isAdsRemoved || kIsWeb || (!Platform.isAndroid && !Platform.isIOS)) return;
    if (_preloadedInterstitialAd != null || _isLoadingInterstitial) return;

    _isLoadingInterstitial = true;
    final unitId = interstitialAdUnitId;

    try {
      InterstitialAd.load(
        adUnitId: unitId,
        request: const AdRequest(),
        adLoadCallback: InterstitialAdLoadCallback(
          onAdLoaded: (ad) {
            _isLoadingInterstitial = false;
            _preloadedInterstitialAd = ad;
            ad.fullScreenContentCallback = FullScreenContentCallback(
              onAdDismissedFullScreenContent: (ad) {
                ad.dispose();
                _preloadedInterstitialAd = null;
                state = state.copyWith(isShowingInterstitial: false);
                _preloadInterstitialAd();
              },
              onAdFailedToShowFullScreenContent: (ad, err) {
                ad.dispose();
                _preloadedInterstitialAd = null;
                state = state.copyWith(isShowingInterstitial: false);
                _preloadInterstitialAd();
              },
            );
          },
          onAdFailedToLoad: (err) {
            _isLoadingInterstitial = false;
            _preloadedInterstitialAd = null;
            debugPrint('Interstitial Ad load error ($unitId): $err');
          },
        ),
      );
    } catch (e) {
      _isLoadingInterstitial = false;
      debugPrint('InterstitialAd load exception: $e');
    }
  }

  /// Call whenever the user navigates. Shows an interstitial ad every 2 navigations.
  void recordNavigation(BuildContext context, [WidgetRef? ref]) {
    if (state.isAdsRemoved) return;

    _navCounter++;
    final newCount = state.navCount + 1;
    state = state.copyWith(navCount: newCount);

    if (_preloadedInterstitialAd == null && !_isLoadingInterstitial) {
      _preloadInterstitialAd();
    }

    // Shows every 2 navigations
    if (_navCounter >= 2) {
      _navCounter = 0;
      if (!state.isShowingInterstitial && context.mounted) {
        showInterstitialAd(context, ref);
      }
    }
  }

  void showInterstitialAd(BuildContext context, [WidgetRef? ref]) {
    if (state.isAdsRemoved || kIsWeb || (!Platform.isAndroid && !Platform.isIOS)) return;

    if (_preloadedInterstitialAd != null) {
      state = state.copyWith(isShowingInterstitial: true);
      _preloadedInterstitialAd!.show();
      _preloadedInterstitialAd = null;
    } else {
      _loadAndShowInterstitial();
    }
  }

  void _loadAndShowInterstitial() {
    if (state.isAdsRemoved || kIsWeb || (!Platform.isAndroid && !Platform.isIOS)) return;
    state = state.copyWith(isShowingInterstitial: true);
    final unitId = interstitialAdUnitId;

    try {
      InterstitialAd.load(
        adUnitId: unitId,
        request: const AdRequest(),
        adLoadCallback: InterstitialAdLoadCallback(
          onAdLoaded: (ad) {
            ad.fullScreenContentCallback = FullScreenContentCallback(
              onAdDismissedFullScreenContent: (ad) {
                ad.dispose();
                state = state.copyWith(isShowingInterstitial: false);
                _preloadInterstitialAd();
              },
              onAdFailedToShowFullScreenContent: (ad, err) {
                ad.dispose();
                state = state.copyWith(isShowingInterstitial: false);
                _preloadInterstitialAd();
              },
            );
            ad.show();
          },
          onAdFailedToLoad: (err) {
            debugPrint('Google Interstitial Ad failed to load ($unitId): $err');
            state = state.copyWith(isShowingInterstitial: false);
          },
        ),
      );
    } catch (e) {
      debugPrint('InterstitialAd error: $e');
      state = state.copyWith(isShowingInterstitial: false);
    }
  }

  /// Requires user to watch a Rewarded Ad before running/unlocking a gated feature
  /// If `remove_ads` product is purchased, bypasses ad check immediately!
  void runWithRewardedAd(
    BuildContext context, {
    required String featureName,
    required VoidCallback onRewardGranted,
  }) {
    if (state.isAdsRemoved || kIsWeb || (!Platform.isAndroid && !Platform.isIOS)) {
      onRewardGranted();
      return;
    }

    try {
      RewardedAd.load(
        adUnitId: rewardedAdUnitId,
        request: const AdRequest(),
        rewardedAdLoadCallback: RewardedAdLoadCallback(
          onAdLoaded: (ad) {
            ad.fullScreenContentCallback = FullScreenContentCallback(
              onAdDismissedFullScreenContent: (ad) {
                ad.dispose();
              },
              onAdFailedToShowFullScreenContent: (ad, err) {
                ad.dispose();
                _showRewardedFallbackDialog(context, featureName, onRewardGranted);
              },
            );
            ad.show(
              onUserEarnedReward: (AdWithoutView ad, RewardItem reward) {
                onRewardGranted();
              },
            );
          },
          onAdFailedToLoad: (err) {
            debugPrint('Rewarded Ad load error: $err');
            _showRewardedFallbackDialog(context, featureName, onRewardGranted);
          },
        ),
      );
    } catch (e) {
      debugPrint('RewardedAd exception: $e');
      _showRewardedFallbackDialog(context, featureName, onRewardGranted);
    }
  }

  void _showRewardedFallbackDialog(
    BuildContext context,
    String featureName,
    VoidCallback onRewardGranted,
  ) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _RewardedAdDialog(
        featureName: featureName,
        onWatchCompleted: () {
          Navigator.of(ctx).pop();
          onRewardGranted();
        },
        onRemoveAdsRequested: () async {
          Navigator.of(ctx).pop();
          await purchaseRemoveAds();
          // Only grant access once Google Play has actually confirmed the purchase.
          if (!state.isAdsRemoved) return;
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('🎉 Ads Removed permanently (`remove_ads`)! Access granted.'),
                backgroundColor: Colors.green,
              ),
            );
          }
          onRewardGranted();
        },
      ),
    );
  }
}

class _RewardedAdDialog extends StatefulWidget {
  final String featureName;
  final VoidCallback onWatchCompleted;
  final VoidCallback onRemoveAdsRequested;

  const _RewardedAdDialog({
    required this.featureName,
    required this.onWatchCompleted,
    required this.onRemoveAdsRequested,
  });

  @override
  State<_RewardedAdDialog> createState() => _RewardedAdDialogState();
}

class _RewardedAdDialogState extends State<_RewardedAdDialog> {
  int _secondsRemaining = 3;
  bool _isWatching = false;
  Timer? _timer;

  void _startWatchingAd() {
    setState(() {
      _isWatching = true;
    });

    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      if (_secondsRemaining > 1) {
        setState(() {
          _secondsRemaining--;
        });
      } else {
        _timer?.cancel();
        widget.onWatchCompleted();
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Row(
        children: [
          const Icon(Icons.movie_filter, color: Colors.purple, size: 28),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Rewarded Ad — ${widget.featureName}',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.purple.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.purple.shade200),
            ),
            child: Row(
              children: [
                const Icon(Icons.stars, color: Colors.purple, size: 24),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Watch a short sponsored video to unlock "${widget.featureName}" or purchase Remove Ads (`remove_ads`) to skip all ads forever.',
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          if (_isWatching)
            Column(
              children: [
                LinearProgressIndicator(
                  value: (3 - _secondsRemaining) / 3.0,
                  backgroundColor: Colors.purple.shade100,
                  color: Colors.purple,
                ),
                const SizedBox(height: 8),
                Text(
                  '🎬 Watching Ad... ($_secondsRemaining sec)',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.purple),
                ),
              ],
            )
          else
            const Text(
              'Tap "Watch Rewarded Ad" to unlock feature now, or purchase "Remove Ads".',
              style: TextStyle(fontSize: 13, color: Colors.grey),
            ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        if (!_isWatching) ...[
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(foregroundColor: Colors.purple[800]),
            onPressed: widget.onRemoveAdsRequested,
            icon: const Icon(Icons.block, size: 16),
            label: const Text('Remove Ads (\$4.99)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
          ),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.purple,
              foregroundColor: Colors.white,
            ),
            onPressed: _startWatchingAd,
            icon: const Icon(Icons.play_circle_fill, size: 18),
            label: const Text('Watch Ad', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ],
    );
  }
}

final adNotifierProvider = StateNotifierProvider<AdNotifier, AdState>((ref) {
  return AdNotifier();
});

final isAdsRemovedProvider = Provider<bool>((ref) {
  final adState = ref.watch(adNotifierProvider);
  return adState.isAdsRemoved;
});

/// Responsive Banner Widget (100% hidden if remove_ads product is purchased)
class AdBannerWidget extends ConsumerStatefulWidget {
  final bool isTop;
  const AdBannerWidget({super.key, this.isTop = false});

  @override
  ConsumerState<AdBannerWidget> createState() => _AdBannerWidgetState();
}

class _AdBannerWidgetState extends ConsumerState<AdBannerWidget>
    with WidgetsBindingObserver {
  BannerAd? _bannerAd;
  bool _isAdLoaded = false;
  int _retryCount = 0;
  Timer? _autoRetryTimer;

  static String get bannerAdUnitId {
    if (!kIsWeb && Platform.isAndroid) {
      return 'ca-app-pub-1852108665659812/8920108867'; // Production Banner Ad ID
    } else if (!kIsWeb && Platform.isIOS) {
      return 'ca-app-pub-3940256099942544/2934735716';
    }
    return 'ca-app-pub-1852108665659812/8920108867';
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (widget.isTop) {
      // Stagger top banner load slightly to avoid concurrent request clash with bottom banner
      Future.delayed(const Duration(milliseconds: 350), () {
        if (mounted) _loadBannerAd();
      });
    } else {
      _loadBannerAd();
    }

    // Auto-retry periodically in case network was initially unavailable
    _autoRetryTimer = Timer.periodic(const Duration(seconds: 20), (timer) {
      if (mounted && !_isAdLoaded) {
        _retryCount = 0;
        _loadBannerAd();
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted && !_isAdLoaded) {
      // Re-try ad load whenever user resumes the app (e.g. turned on Wi-Fi)
      _retryCount = 0;
      _loadBannerAd();
    }
  }

  void _loadBannerAd() {
    if (kIsWeb || (!Platform.isAndroid && !Platform.isIOS)) return;
    try {
      _bannerAd?.dispose();
      final unitId = bannerAdUnitId;

      _bannerAd = BannerAd(
        adUnitId: unitId,
        size: AdSize.banner,
        request: const AdRequest(),
        listener: BannerAdListener(
          onAdLoaded: (ad) {
            if (mounted) {
              setState(() {
                _isAdLoaded = true;
              });
            }
          },
          onAdFailedToLoad: (ad, error) {
            debugPrint('Google BannerAd failed to load ($unitId): $error');
            ad.dispose();
            if (mounted) {
              setState(() {
                _isAdLoaded = false;
                _bannerAd = null;
              });
              if (_retryCount < 3) {
                _retryCount++;
                Future.delayed(Duration(seconds: 4 * _retryCount), () {
                  if (mounted && !_isAdLoaded) {
                    _loadBannerAd();
                  }
                });
              }
            }
          },
        ),
      );
      _bannerAd?.load();
    } catch (e) {
      debugPrint('BannerAd load error: $e');
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _autoRetryTimer?.cancel();
    _bannerAd?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isAdsRemoved = ref.watch(isAdsRemovedProvider);

    // 100% HIDDEN if user has purchased remove_ads product!
    if (isAdsRemoved) {
      return const SizedBox.shrink();
    }

    // Only mobile platforms (Android/iOS) support Google Mobile Ads
    if (kIsWeb || (!Platform.isAndroid && !Platform.isIOS)) {
      return const SizedBox.shrink();
    }

    if (_isAdLoaded && _bannerAd != null) {
      return Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        alignment: Alignment.center,
        width: _bannerAd!.size.width.toDouble(),
        height: _bannerAd!.size.height.toDouble(),
        child: AdWidget(ad: _bannerAd!),
      );
    }

    // While loading or if fill is not available, render zero height to avoid layout shift
    return const SizedBox.shrink();
  }
}
