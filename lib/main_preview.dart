import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:myexpence/main.dart' show MyExpenseApp;
import 'package:myexpence/features/ads/presentation/providers/ad_providers.dart';
import 'package:myexpence/features/auth/presentation/providers/auth_providers.dart';
import 'package:myexpence/features/navigation/app_router.dart';
import 'package:myexpence/features/subscription/presentation/providers/subscription_providers.dart';
import 'package:myexpence/features/support/support_actions.dart';
import 'package:myexpence/features/backup/monthly_backup_billing.dart';

/// flutter build apk --debug --target lib/main_preview.dart
/// Installs alongside the production app and never initializes live Firebase.
Future<void> main() async {
  if (!kDebugMode) throw StateError('The preview entry point is debug-only.');
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  appRouter.go('/dashboard');
  runApp(ProviderScope(overrides: [
    authProvider.overrideWith((ref) => AuthNotifier.localPreview()),
    subscriptionProvider
        .overrideWith((ref) => SubscriptionNotifier.localPreview()),
    supportActionsProvider.overrideWith((ref) => SupportActions(preview: true)),
    monthlyBackupBillingProvider
        .overrideWith((ref) => CloudBackupBilling(preview: true)),
    // Exercise the release safety guard without making real ad/purchase requests.
    adNotifierProvider.overrideWith((ref) => AdNotifier(
          releaseBuild: true,
          enablePurchases: false,
        )),
  ], child: const MyExpenseApp()));
}
