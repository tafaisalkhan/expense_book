import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:myexpence/core/theme/app_theme.dart';
import 'package:myexpence/features/navigation/app_router.dart';
import 'package:myexpence/features/security/presentation/screens/app_lock_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await Firebase.initializeApp();
  } catch (_) {}
  try {
    await MobileAds.instance.initialize();
    await MobileAds.instance.updateRequestConfiguration(
      RequestConfiguration(
        testDeviceIds: [
          '7FAD65EC0E638FA926CE871CB91C3E96',
          'D8DC7BA59F51F2B7C1529F09E1F0EA3E',
        ],
      ),
    );
  } catch (_) {}
  runApp(
    const ProviderScope(
      child: MyExpenseApp(),
    ),
  );
}

class MyExpenseApp extends StatelessWidget {
  const MyExpenseApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'MyExpense',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: ThemeMode.system,
      routerConfig: appRouter,
      builder: (context, child) {
        return AppLockOverlayWrapper(
          child: child ?? const SizedBox.shrink(),
        );
      },
    );
  }
}
