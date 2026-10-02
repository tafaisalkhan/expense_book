import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:myexpence/core/theme/app_theme.dart';

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
  static const String _prefKeyAdsRemoved = 'ads_removed_product_v1';
  StreamSubscription<List<PurchaseDetails>>? _purchaseSub;

  AdNotifier() : super(const AdState()) {
    _loadAdState();
    _initInAppPurchase();
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
      final isRemoved = prefs.getBool(_prefKeyAdsRemoved) ?? false;
      state = state.copyWith(isAdsRemoved: isRemoved);
    } catch (_) {}
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
    }

    // Direct fallback (e.g. debug mode / test emulator / offline)
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_prefKeyAdsRemoved, true);
      state = state.copyWith(isAdsRemoved: true);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Restore Google Play In-App Purchases for `remove_ads`
  Future<void> restorePurchases() async {
    try {
      if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
        await InAppPurchase.instance.restorePurchases();
      }
    } catch (e) {
      debugPrint('Restore purchases notice: $e');
    }
  }

  @override
  void dispose() {
    _purchaseSub?.cancel();
    super.dispose();
  }

  void recordNavigation(BuildContext context, WidgetRef ref) {
    if (state.isAdsRemoved) return;

    final newCount = state.navCount + 1;
    state = state.copyWith(navCount: newCount);

    if (newCount % 5 == 0 || newCount % 6 == 0) {
      if (!state.isShowingInterstitial && context.mounted) {
        showInterstitialAd(context, ref);
      }
    }
  }

  void showInterstitialAd(BuildContext context, WidgetRef ref) {
    if (state.isAdsRemoved || kIsWeb || (!Platform.isAndroid && !Platform.isIOS)) return;

    state = state.copyWith(isShowingInterstitial: true);

    try {
      InterstitialAd.load(
        adUnitId: interstitialAdUnitId,
        request: const AdRequest(),
        adLoadCallback: InterstitialAdLoadCallback(
          onAdLoaded: (ad) {
            ad.fullScreenContentCallback = FullScreenContentCallback(
              onAdDismissedFullScreenContent: (ad) {
                ad.dispose();
                state = state.copyWith(isShowingInterstitial: false);
              },
              onAdFailedToShowFullScreenContent: (ad, err) {
                ad.dispose();
                state = state.copyWith(isShowingInterstitial: false);
              },
            );
            ad.show();
          },
          onAdFailedToLoad: (err) {
            debugPrint('Google Interstitial Ad failed to load: $err');
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
  const AdBannerWidget({super.key});

  @override
  ConsumerState<AdBannerWidget> createState() => _AdBannerWidgetState();
}

class _AdBannerWidgetState extends ConsumerState<AdBannerWidget> {
  BannerAd? _bannerAd;
  bool _isAdLoaded = false;
  int _retryCount = 0;

  static String get bannerAdUnitId {
    if (Platform.isAndroid) {
      return 'ca-app-pub-1852108665659812/8920108867'; // Production Banner Ad ID
    } else if (Platform.isIOS) {
      return 'ca-app-pub-3940256099942544/2934735716';
    }
    return 'ca-app-pub-1852108665659812/8920108867';
  }

  @override
  void initState() {
    super.initState();
    _loadBannerAd();
  }

  void _loadBannerAd() {
    if (kIsWeb || (!Platform.isAndroid && !Platform.isIOS)) return;
    try {
      _bannerAd?.dispose();
      _bannerAd = BannerAd(
        adUnitId: bannerAdUnitId,
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
            debugPrint('Google BannerAd failed to load: $error');
            ad.dispose();
            if (mounted) {
              setState(() {
                _isAdLoaded = false;
                _bannerAd = null;
              });
              if (_retryCount < 3) {
                _retryCount++;
                Future.delayed(Duration(seconds: 3 * _retryCount), () {
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

    if (_isAdLoaded && _bannerAd != null) {
      return Container(
        margin: const EdgeInsets.symmetric(vertical: 8),
        alignment: Alignment.center,
        width: _bannerAd!.size.width.toDouble(),
        height: _bannerAd!.size.height.toDouble(),
        child: AdWidget(ad: _bannerAd!),
      );
    }

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.amber.shade700.withValues(alpha: 0.5)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.amber,
              borderRadius: BorderRadius.circular(4),
            ),
            child: const Text(
              'AD',
              style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.black),
            ),
          ),
          const SizedBox(width: 8),
          const Expanded(
            child: Text(
              'Remove Ads permanently (Product ID: remove_ads)',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 6),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.amber,
              foregroundColor: Colors.black,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              visualDensity: VisualDensity.compact,
            ),
            onPressed: () async {
              await ref.read(adNotifierProvider.notifier).purchaseRemoveAds();
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('🎉 Ads Removed permanently (`remove_ads`)!')),
                );
              }
            },
            child: const Text('Remove Ads', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }
}
