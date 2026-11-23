import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:myexpence/features/ads/presentation/providers/ad_providers.dart';
import 'package:myexpence/features/ads/presentation/widgets/ad_availability_notice.dart';

class FakeRewarded extends Fake implements RewardedAd {
  FullScreenContentCallback<RewardedAd>? callbacks;
  void Function(AdWithoutView, RewardItem)? reward;
  int disposed = 0;
  int shown = 0;
  @override
  set fullScreenContentCallback(FullScreenContentCallback<RewardedAd>? value) =>
      callbacks = value;
  @override
  Future<void> show(
      {required void Function(AdWithoutView, RewardItem)
          onUserEarnedReward}) async {
    reward = onUserEarnedReward;
    shown++;
  }

  @override
  Future<void> dispose() async {
    disposed++;
  }
}

class FakeInterstitial extends Fake implements InterstitialAd {
  int disposed = 0;
  @override
  Future<void> dispose() async {
    disposed++;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('release test IDs disable ads before SDK initialization', () async {
    var initialized = false;
    final notifier = AdNotifier(
        autoStart: false,
        mobile: true,
        releaseBuild: true,
        enablePurchases: false,
        initializeAds: () async {
          initialized = true;
        });
    addTearDown(notifier.dispose);
    await notifier.start();
    expect(initialized, false);
    expect(notifier.state.noFillThisLaunch, true);
    expect(notifier.state.rewardedReady, false);
    expect(notifier.claimNoAdsNotice(), true);
    expect(notifier.claimNoAdsNotice(), false);
  });

  test('failure remains ad-free even after late successful loads', () async {
    late RewardedAdLoadCallback rewarded;
    late InterstitialAdLoadCallback interstitial;
    var requests = 0;
    final notifier = AdNotifier(
        autoStart: false,
        mobile: true,
        releaseBuild: false,
        enablePurchases: false,
        initializeAds: () async {},
        loadRewarded: (_, callback) {
          rewarded = callback;
          requests++;
        },
        loadInterstitial: (_, callback) {
          interstitial = callback;
          requests++;
        });
    addTearDown(notifier.dispose);
    await notifier.start();
    rewarded.onAdFailedToLoad(LoadAdError(3, 'test', 'no fill', null));
    final lateRewarded = FakeRewarded();
    final lateInterstitial = FakeInterstitial();
    rewarded.onAdLoaded(lateRewarded);
    interstitial.onAdLoaded(lateInterstitial);
    await notifier.start();
    expect(notifier.state.noFillThisLaunch, true);
    expect(notifier.state.rewardedReady, false);
    expect(lateRewarded.disposed, 1);
    expect(lateInterstitial.disposed, 1);
    expect(requests, 2);
  });

  testWidgets('unavailable buttons grant access and popup appears only once',
      (tester) async {
    final notifier = AdNotifier(autoStart: false, mobile: true);
    final navigatorKey = GlobalKey<NavigatorState>();
    var grants = 0;
    await tester.pumpWidget(ProviderScope(
        overrides: [
          adNotifierProvider.overrideWith((ref) => notifier),
        ],
        child: MaterialApp(
          navigatorKey: navigatorKey,
          builder: (_, child) =>
              AdAvailabilityNotice(navigatorKey: navigatorKey, child: child!),
          home: Scaffold(
              body: Column(children: [
            const AdBannerWidget(isTop: true),
            Builder(
                builder: (context) => TextButton(
                    onPressed: () => notifier.runWithRewardedAd(context,
                            featureName: 'Local backup', onRewardGranted: () {
                          grants++;
                        }),
                    child: const Text('Download Data'))),
            const AdBannerWidget(),
          ])),
        )));
    await tester.tap(find.text('Download Data'));
    await tester.pumpAndSettle();
    expect(grants, 1);
    expect(find.text('NO ADS TODAY — AD-FREE'), findsOneWidget);
    expect(find.byType(AdWidget), findsNothing);
    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();
    expect(find.byType(SafeArea), findsNothing);
    await tester.tap(find.text('Download Data'));
    await tester.pumpAndSettle();
    expect(grants, 2);
    expect(find.byType(Dialog), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final outcome in ['earned', 'cancelled', 'show failure']) {
    testWidgets('ready rewarded ad: $outcome', (tester) async {
      late RewardedAdLoadCallback load;
      final ad = FakeRewarded();
      final notifier = AdNotifier(
          autoStart: false,
          mobile: true,
          releaseBuild: false,
          enablePurchases: false,
          initializeAds: () async {},
          loadRewarded: (_, callback) {
            load = callback;
          },
          loadInterstitial: (_, __) {});
      addTearDown(() {
        if (notifier.mounted) notifier.dispose();
      });
      await notifier.start();
      load.onAdLoaded(ad);
      var grants = 0;
      await tester.pumpWidget(MaterialApp(
          home: Builder(
              builder: (context) => TextButton(
                  onPressed: () => notifier.runWithRewardedAd(context,
                          featureName: 'Restore', onRewardGranted: () {
                        grants++;
                      }),
                  child: const Text('Restore Data')))));
      await tester.tap(find.text('Restore Data'));
      expect(grants, 0);
      expect(ad.shown, 1);
      expect(notifier.state.rewardedReady, false);
      if (outcome == 'earned') {
        ad.reward!(ad, RewardItem(1, 'backup'));
        expect(grants, 0);
      }
      if (outcome == 'show failure') {
        ad.callbacks!.onAdFailedToShowFullScreenContent!(
            ad, AdError(1, 'test', 'offline'));
      } else {
        ad.callbacks!.onAdDismissedFullScreenContent!(ad);
      }
      ad.callbacks!.onAdDismissedFullScreenContent!(ad);
      expect(grants, outcome == 'cancelled' ? 0 : 1);
      expect(notifier.state.noFillThisLaunch, outcome == 'show failure');
      notifier.dispose();
    });
  }

  test('AdState.copyWith preserves removeAdsPrice cleanly', () {
    const initial = AdState(noFillThisLaunch: true, isAdsRemoved: false);
    final updated = initial.copyWith(removeAdsPrice: '\$4.99');
    expect(updated.removeAdsPrice, '\$4.99');
    expect(updated.noFillThisLaunch, true);
    expect(updated.isAdsRemoved, false);
  });

  testWidgets(
      'active cloud subscription hides all banners, disposes loaded ads, and bypasses rewarded gates',
      (tester) async {
    late RewardedAdLoadCallback loadRewarded;
    late InterstitialAdLoadCallback loadInterstitial;
    final rewardedAd = FakeRewarded();
    final interstitialAd = FakeInterstitial();
    final notifier = AdNotifier(
      autoStart: false,
      mobile: true,
      releaseBuild: false,
      enablePurchases: false,
      initializeAds: () async {},
      loadRewarded: (_, cb) => loadRewarded = cb,
      loadInterstitial: (_, cb) => loadInterstitial = cb,
    );
    addTearDown(() {
      if (notifier.mounted) notifier.dispose();
    });
    await notifier.start();
    loadRewarded.onAdLoaded(rewardedAd);
    loadInterstitial.onAdLoaded(interstitialAd);
    expect(notifier.state.rewardedReady, true);
    expect(notifier.adsAllowed, true);

    var grants = 0;
    await tester.pumpWidget(ProviderScope(
      overrides: [adNotifierProvider.overrideWith((ref) => notifier)],
      child: MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              const AdBannerWidget(isTop: true),
              Builder(
                builder: (context) => TextButton(
                  onPressed: () => notifier.runWithRewardedAd(
                    context,
                    featureName: 'Export',
                    onRewardGranted: () => grants++,
                  ),
                  child: const Text('Export'),
                ),
              ),
              const AdBannerWidget(),
            ],
          ),
        ),
      ),
    ));

    notifier.setSubscriptionActive(true);
    await tester.pumpAndSettle();

    expect(rewardedAd.disposed, 1);
    expect(interstitialAd.disposed, 1);
    expect(notifier.state.hasActiveSubscription, true);
    expect(notifier.state.adsSuppressed, true);
    expect(notifier.state.rewardedReady, false);
    expect(notifier.adsAllowed, false);
    expect(notifier.claimNoAdsNotice(), false);
    expect(find.byType(AdWidget), findsNothing);
    expect(find.byType(SafeArea), findsNothing);

    await tester.tap(find.text('Export'));
    await tester.pumpAndSettle();
    expect(grants, 1);
    expect(rewardedAd.shown, 0);

    notifier.setSubscriptionActive(false);
    expect(notifier.state.hasActiveSubscription, false);
    expect(notifier.state.adsSuppressed, false);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('stalled ad load times out and stops requests this launch',
      (tester) async {
    final notifier = AdNotifier(
        autoStart: false,
        mobile: true,
        releaseBuild: false,
        enablePurchases: false,
        initializeAds: () async {},
        loadRewarded: (_, __) {},
        loadInterstitial: (_, __) {});
    addTearDown(() {
      if (notifier.mounted) notifier.dispose();
    });
    await notifier.start();
    await tester.pump(const Duration(seconds: 16));
    expect(notifier.state.noFillThisLaunch, true);
    expect(notifier.state.rewardedReady, false);
  });
}
