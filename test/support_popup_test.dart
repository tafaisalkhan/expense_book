import 'dart:math';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:myexpence/features/ads/presentation/providers/ad_providers.dart';
import 'package:myexpence/features/support/support_actions.dart';
import 'package:myexpence/features/support/support_dialog.dart';

class FixedRandom implements Random {
  final int value;
  FixedRandom(this.value);
  @override
  int nextInt(int max) => value % max;
  @override
  bool nextBool() => false;
  @override
  double nextDouble() => 0;
}

class FakeCoffeeStore extends Fake implements InAppPurchase {
  final updates = StreamController<List<PurchaseDetails>>();
  int started = 0;
  int completed = 0;
  @override
  Stream<List<PurchaseDetails>> get purchaseStream => updates.stream;
  @override
  Future<bool> isAvailable() async => true;
  @override
  Future<ProductDetailsResponse> queryProductDetails(Set<String> ids) async =>
      ProductDetailsResponse(productDetails: [
        ProductDetails(
            id: 'cofee',
            title: 'Coffee',
            description: 'Support',
            price: 'Rs 599',
            rawPrice: 599,
            currencyCode: 'PKR')
      ], notFoundIDs: []);
  @override
  Future<bool> buyConsumable(
      {required PurchaseParam purchaseParam, bool autoConsume = true}) async {
    started++;
    return true;
  }

  @override
  Future<void> completePurchase(PurchaseDetails purchase) async {
    completed++;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('coffee waits for store confirmation and completes the purchase',
      () async {
    final store = FakeCoffeeStore();
    final actions = SupportActions(billing: store);
    addTearDown(() async {
      actions.dispose();
      await store.updates.close();
    });
    await actions.initialize();
    expect(actions.state.product!.price, 'Rs 599');
    await actions.buyCoffee();
    await actions.buyCoffee();
    expect(store.started, 1);
    expect(actions.state.status, CoffeeStatus.pending);
    final purchased = PurchaseDetails(
        productID: 'cofee',
        purchaseID: 'coffee-1',
        verificationData: PurchaseVerificationData(
            localVerificationData: '',
            serverVerificationData: '',
            source: 'google_play'),
        transactionDate: '1',
        status: PurchaseStatus.purchased)
      ..pendingCompletePurchase = true;
    store.updates.add([purchased]);
    await Future<void>.delayed(Duration.zero);
    expect(actions.state.status, CoffeeStatus.purchased);
    expect(store.completed, 1);
  });

  test('canceling coffee checkout does not report a successful purchase',
      () async {
    final store = FakeCoffeeStore();
    final actions = SupportActions(billing: store);
    addTearDown(() async {
      actions.dispose();
      await store.updates.close();
    });
    await actions.initialize();
    await actions.buyCoffee();
    store.updates.add([
      PurchaseDetails(
          productID: 'cofee',
          purchaseID: 'coffee-2',
          verificationData: PurchaseVerificationData(
              localVerificationData: '',
              serverVerificationData: '',
              source: 'google_play'),
          transactionDate: '1',
          status: PurchaseStatus.canceled)
    ]);
    await Future<void>.delayed(Duration.zero);
    expect(actions.state.status, CoffeeStatus.canceled);
    expect(store.completed, 0);
  });
  test('support prompt waits for a genuine Home return and appears once', () {
    final session = SupportPromptSession(random: FixedRandom(0));
    session.visit('/login');
    expect(session.claim(), isNull);
    session.visit('/dashboard');
    expect(session.claim(), isNull);
    session.visit('/more');
    expect(session.claim(), isNull);
    session.visit('/dashboard');
    expect(session.claim(), SupportAction.rate);
    session.visit('/expenses');
    session.visit('/dashboard');
    expect(session.claim(), isNull);
  });

  for (final action in SupportAction.values) {
    test('random selection supports ${action.name}', () {
      final session = SupportPromptSession(random: FixedRandom(action.index));
      session.visit('/dashboard');
      session.visit('/add');
      session.visit('/dashboard');
      expect(session.claim(), action);
    });

    testWidgets('${action.name} popup closes and handles its action',
        (tester) async {
      final methods = <String>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
              const MethodChannel('com.myexpense.book/support'), (call) async {
        methods.add(call.method);
        return null;
      });
      addTearDown(() => TestDefaultBinaryMessengerBinding
          .instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
              const MethodChannel('com.myexpense.book/support'), null));
      await tester.pumpWidget(ProviderScope(
          overrides: [
            adNotifierProvider.overrideWith(
                (ref) => AdNotifier(autoStart: false, mobile: false)),
            supportActionsProvider
                .overrideWith((ref) => SupportActions(preview: true)),
          ],
          child: MaterialApp(
              home: Builder(
                  builder: (context) => TextButton(
                      onPressed: () => showDialog<void>(
                          context: context,
                          builder: (_) => SupportDialog(action: action)),
                      child: const Text('Open'))))));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Close'), findsOneWidget);
      expect(find.text('Maybe later'), findsOneWidget);
      if (action == SupportAction.coffee) {
        await tester.tap(find.text('Buy a coffee · \$1.99'));
        await tester.pumpAndSettle();
        expect(find.textContaining('No payment will be taken'), findsOneWidget);
        expect(methods, isEmpty);
        await tester.tap(find.byTooltip('Close'));
      } else {
        await tester.tap(find.text(action == SupportAction.rate
            ? 'Rate on Google Play'
            : 'Share the app'));
        await tester.pumpAndSettle();
        expect(
            methods, [action == SupportAction.rate ? 'rateApp' : 'shareApp']);
      }
      await tester.pumpAndSettle();
      expect(find.byType(Dialog), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  test('preview app update helpers skip platform calls and CoffeeState preserves updateDownloaded',
      () async {
    final methods = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('com.myexpense.book/support'), (call) async {
      methods.add(call.method);
      return null;
    });
    addTearDown(() => TestDefaultBinaryMessengerBinding
        .instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('com.myexpense.book/support'), null));

    final previewActions = SupportActions(preview: true);
    addTearDown(previewActions.dispose);
    await previewActions.checkForAppUpdate(force: true);
    await previewActions.completeAppUpdate();
    expect(methods, isEmpty);

    const state = CoffeeState(status: CoffeeStatus.ready, updateDownloaded: false);
    final updated = state.copyWith(updateDownloaded: true);
    expect(updated.status, CoffeeStatus.ready);
    expect(updated.updateDownloaded, true);
  });
}
