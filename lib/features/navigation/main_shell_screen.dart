import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:myexpence/core/services/app_permissions_service.dart';
import 'package:myexpence/core/widgets/draggable_floating_action_button.dart';
import 'package:myexpence/features/ads/presentation/providers/ad_providers.dart';
import 'package:myexpence/features/auth/domain/models/auth_user.dart';
import 'package:myexpence/features/auth/presentation/providers/auth_providers.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';

import 'package:myexpence/features/sms_parser/domain/services/sms_listener_service.dart';
import 'package:myexpence/features/sms_parser/presentation/widgets/sms_approval_dialog.dart';
import 'package:myexpence/features/subscription/domain/services/firebase_cloud_backup_service.dart';

class MainShellScreen extends ConsumerStatefulWidget {
  final Widget child;

  const MainShellScreen({super.key, required this.child});

  @override
  ConsumerState<MainShellScreen> createState() => _MainShellScreenState();
}

class _MainShellScreenState extends ConsumerState<MainShellScreen> with WidgetsBindingObserver {
  StreamSubscription? _intentDataStreamSubscription;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initSharedIntentListener();
    _checkInitialSmsNotification();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      AppPermissionsService.requestAllStartupPermissions(ref, context: context);
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _intentDataStreamSubscription?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) {
      // Re-evaluate permissions dynamically when app is resumed from background / settings
      AppPermissionsService.requestAllStartupPermissions(ref, context: context, forceRefresh: true);
      _checkInitialSmsNotification();
    }
  }

  Future<void> _checkInitialSmsNotification() async {
    if (kIsWeb || (!Platform.isAndroid)) return;
    try {
      final initialSms = await SmsListenerService.getInitialNotificationSms();
      if (initialSms != null && mounted) {
        final body = initialSms['body'];
        final sender = initialSms['sender'];
        if (body != null && body.isNotEmpty) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              showSmsApprovalDialog(context, ref, rawSms: body, sender: sender);
            }
          });
        }
      }
    } catch (_) {}
  }

  void _initSharedIntentListener() {
    if (kIsWeb || (!Platform.isAndroid && !Platform.isIOS)) return;
    try {
      // For sharing images/files while app is running/backgrounded
      _intentDataStreamSubscription =
          ReceiveSharingIntent.instance.getMediaStream().listen((List<SharedMediaFile> value) {
        if (value.isNotEmpty && mounted) {
          final sharedPath = value.first.path;
          context.push('/share-receipt', extra: sharedPath);
        }
      }, onError: (_) {});

      // For sharing images/files when app is launched via Share menu
      ReceiveSharingIntent.instance.getInitialMedia().then((List<SharedMediaFile> value) {
        if (value.isNotEmpty && mounted) {
          final sharedPath = value.first.path;
          context.push('/share-receipt', extra: sharedPath);
          ReceiveSharingIntent.instance.reset();
        }
      });
    } catch (_) {}
  }

  int _calculateSelectedIndex(BuildContext context) {
    final String location = GoRouterState.of(context).uri.path;
    if (location.startsWith('/expenses')) return 1;
    if (location.startsWith('/add')) return 2;
    if (location.startsWith('/analytics')) return 3;
    if (location.startsWith('/more') || location.startsWith('/people') || location.startsWith('/categories')) return 4;
    return 0; // Dashboard
  }

  void _onItemTapped(int index, BuildContext context) {
    ref.read(adNotifierProvider.notifier).recordNavigation(context, ref);
    switch (index) {
      case 0:
        context.go('/dashboard');
        break;
      case 1:
        context.go('/expenses');
        break;
      case 2:
        context.push('/add');
        break;
      case 3:
        context.go('/analytics');
        break;
      case 4:
        context.go('/more');
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<AuthUser>(authProvider, (previous, next) async {
      if (next.requiresLogoutDialog && mounted) {
        final reason = next.logoutDialogReason ??
            'You have been logged out because your account was logged into from another device.';
        await showDialog(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: const Row(
              children: [
                Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 28),
                SizedBox(width: 10),
                Text('Logged Out', style: TextStyle(fontWeight: FontWeight.bold)),
              ],
            ),
            content: Text(
              reason,
              style: const TextStyle(fontSize: 14, height: 1.4),
            ),
            actions: [
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red[700],
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                onPressed: () {
                  Navigator.of(ctx).pop();
                },
                child: const Text('OK', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        );
        if (mounted) {
          await ref.read(authProvider.notifier).signOut(reason: reason);
          if (context.mounted) {
            context.go('/login');
          }
        }
      } else if (!next.isLoggedIn && mounted) {
        context.go('/login');
      }
    });

    final selectedIndex = _calculateSelectedIndex(context);

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            const AdBannerWidget(), // Top Banner Ad (Ad #1)
            Expanded(
              child: Stack(
                children: [
                  widget.child,
                  DraggableFloatingActionButton(
                    onPressed: () => context.push('/add'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const AdBannerWidget(), // Bottom Banner Ad (Ad #2)
          NavigationBar(
            selectedIndex: selectedIndex,
            onDestinationSelected: (idx) => _onItemTapped(idx, context),
            destinations: const [
              NavigationDestination(
                icon: Icon(Icons.dashboard_outlined),
                selectedIcon: Icon(Icons.dashboard),
                label: 'Home',
              ),
              NavigationDestination(
                icon: Icon(Icons.receipt_long_outlined),
                selectedIcon: Icon(Icons.receipt_long),
                label: 'Expenses',
              ),
              NavigationDestination(
                icon: Icon(Icons.add_circle_outline, size: 30),
                selectedIcon: Icon(Icons.add_circle, size: 30),
                label: 'Add',
              ),
              NavigationDestination(
                icon: Icon(Icons.pie_chart_outline),
                selectedIcon: Icon(Icons.pie_chart),
                label: 'Analytics',
              ),
              NavigationDestination(
                icon: Icon(Icons.grid_view_outlined),
                selectedIcon: Icon(Icons.grid_view),
                label: 'More',
              ),
            ],
          ),
        ],
      ),
    );
  }
}
