import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:myexpence/core/services/app_permissions_service.dart';
import 'package:myexpence/core/providers/core_providers.dart';
import 'package:myexpence/core/widgets/draggable_floating_action_button.dart';
import 'package:myexpence/features/ads/presentation/providers/ad_providers.dart';
import 'package:myexpence/features/auth/domain/models/auth_user.dart';
import 'package:myexpence/features/auth/presentation/providers/auth_providers.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';

import 'package:myexpence/features/sms_parser/domain/services/sms_listener_service.dart';
import 'package:myexpence/features/sms_parser/presentation/widgets/sms_approval_dialog.dart';
import 'package:myexpence/features/expenses/presentation/widgets/pending_recurring_expenses_dialog.dart';
import 'package:myexpence/features/support/support_actions.dart';
import 'package:myexpence/features/support/support_dialog.dart';
import 'package:myexpence/features/backup/backup_refresh.dart';
import 'package:myexpence/features/backup/backup_scheduler.dart';
import 'package:myexpence/features/backup/cloud_backup_service.dart';
import 'package:myexpence/features/backup/monthly_backup_billing.dart';

class MainShellScreen extends ConsumerStatefulWidget {
  final Widget child;

  const MainShellScreen({super.key, required this.child});

  @override
  ConsumerState<MainShellScreen> createState() => _MainShellScreenState();
}

class _MainShellScreenState extends ConsumerState<MainShellScreen>
    with WidgetsBindingObserver {
  StreamSubscription? _intentDataStreamSubscription;
  Timer? _vipHourlyBackupTimer;
  bool _vipSyncRunning = false;
  bool _checkingRecurringExpenses = false;
  GoRouter? _supportRouter;
  bool _supportCheckScheduled = false;
  bool _updateSnackShown = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final router = GoRouter.of(context);
    if (_supportRouter != router) {
      _supportRouter?.routerDelegate.removeListener(_supportRouteChanged);
      _supportRouter = router;
      router.routerDelegate.addListener(_supportRouteChanged);
      _supportRouteChanged();
    }
  }

  void _supportRouteChanged() {
    if (!mounted || _supportRouter == null) return;
    ref
        .read(supportPromptSessionProvider)
        .visit(_supportRouter!.routeInformationProvider.value.uri.path);
    _checkSupportPopup();
  }

  void _checkSupportPopup() {
    if (_supportCheckScheduled || !mounted) return;
    _supportCheckScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _supportCheckScheduled = false;
      if (!mounted) return;
      final session = ref.read(supportPromptSessionProvider);
      final ads = ref.read(adNotifierProvider);
      if (!session.eligible ||
          _checkingRecurringExpenses ||
          !ref.read(authProvider).isLoggedIn ||
          ref.read(adNotifierProvider.notifier).noAdsNoticeOpen ||
          ads.isShowingInterstitial ||
          ads.isShowingRewarded ||
          Navigator.of(context, rootNavigator: true).canPop()) {
        return;
      }
      final action = session.claim();
      if (action == null) return;
      unawaited(showDialog<void>(
          context: context,
          barrierColor: Colors.black.withValues(alpha: .45),
          builder: (_) => SupportDialog(action: action)));
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initSharedIntentListener();
    _checkInitialSmsNotification();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      AppPermissionsService.requestAllStartupPermissions(ref, context: context);
      _checkRecurringExpenses();
      _scheduleRecurringReminder();
      unawaited(ref.read(supportActionsProvider.notifier).checkForAppUpdate());
      _startVipOwnerHourlySync();
    });
  }

  void _startVipOwnerHourlySync() {
    _vipHourlyBackupTimer?.cancel();
    unawaited(_triggerVipOwnerSync());
    _vipHourlyBackupTimer = Timer.periodic(
      const Duration(hours: 1),
      (_) => unawaited(_triggerVipOwnerSync()),
    );
  }

  Future<void> _triggerVipOwnerSync() async {
    if (_vipSyncRunning || !mounted || !CloudBackupService.isVipOwnerUser()) {
      return;
    }
    _vipSyncRunning = true;
    try {
      await BackupScheduler.ensureVipOwnerHourlySchedule();
      final msg = await CloudBackupService().runVipOwnerHourlySync();
      if (!mounted || msg == null) return;
      if (msg.startsWith('Auto-restored from Supabase:')) {
        refreshAfterBackupRestore(ref);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(msg)),
        );
      }
    } catch (_) {
    } finally {
      _vipSyncRunning = false;
    }
  }

  @override
  void dispose() {
    _vipHourlyBackupTimer?.cancel();
    _supportRouter?.routerDelegate.removeListener(_supportRouteChanged);
    WidgetsBinding.instance.removeObserver(this);
    _intentDataStreamSubscription?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) {
      // Re-evaluate permissions dynamically when app is resumed from background / settings
      AppPermissionsService.requestAllStartupPermissions(ref,
          context: context, forceRefresh: true);
      _checkInitialSmsNotification();
      _checkRecurringExpenses();
      unawaited(ref.read(supportActionsProvider.notifier).checkForAppUpdate());
      unawaited(_triggerVipOwnerSync());
    }
  }

  Future<void> _checkRecurringExpenses() async {
    if (_checkingRecurringExpenses || !mounted) return;
    _checkingRecurringExpenses = true;
    try {
      await showPendingRecurringExpensesDialog(context, ref);
    } catch (_) {
    } finally {
      _checkingRecurringExpenses = false;
      _checkSupportPopup();
    }
  }

  Future<void> _scheduleRecurringReminder() async {
    try {
      final service = ref.read(notificationServiceProvider);
      await service.init();
      await service.scheduleRecurringApprovalReminder();
    } catch (_) {}
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
      _intentDataStreamSubscription = ReceiveSharingIntent.instance
          .getMediaStream()
          .listen((List<SharedMediaFile> value) {
        if (value.isNotEmpty && mounted) {
          final sharedPath = value.first.path;
          context.push('/share-receipt', extra: sharedPath);
        }
      }, onError: (_) {});

      // For sharing images/files when app is launched via Share menu
      ReceiveSharingIntent.instance
          .getInitialMedia()
          .then((List<SharedMediaFile> value) {
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
    if (location.startsWith('/more') ||
        location.startsWith('/people') ||
        location.startsWith('/categories') ||
        location.startsWith('/calendar') ||
        location.startsWith('/budgets')) {
      return 4;
    }
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
    ref.watch(supportActionsProvider);
    ref.watch(monthlyBackupBillingProvider);
    ref.listen<AdState>(adNotifierProvider, (_, __) => _checkSupportPopup());
    ref.listen<bool>(supportActionsProvider.select((s) => s.updateDownloaded),
        (_, downloaded) {
      if (!downloaded || _updateSnackShown || !mounted) return;
      _updateSnackShown = true;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 12),
          content: const Text('App update downloaded and ready to install.'),
          action: SnackBarAction(
            label: 'Restart',
            onPressed: () =>
                ref.read(supportActionsProvider.notifier).completeAppUpdate(),
          ),
        ),
      );
    });
    ref.listen<AuthUser>(authProvider, (previous, next) async {
      if (next.isLoggedIn && previous?.uid != next.uid) {
        unawaited(_triggerVipOwnerSync());
      }
      if (next.requiresLogoutDialog && mounted) {
        final reason = next.logoutDialogReason ??
            'You have been logged out because your account was logged into from another device.';
        await showDialog(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => AlertDialog(
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: const Row(
              children: [
                Icon(Icons.warning_amber_rounded,
                    color: Colors.orange, size: 28),
                SizedBox(width: 10),
                Text('Logged Out',
                    style: TextStyle(fontWeight: FontWeight.bold)),
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
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                ),
                onPressed: () {
                  Navigator.of(ctx).pop();
                },
                child: const Text('OK',
                    style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        );
        if (mounted) {
          await ref
              .read(authProvider.notifier)
              .signOut(reason: reason, clearLocalData: false);
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
      body: Stack(
        children: [
          widget.child,
          DraggableFloatingActionButton(
            onPressed: () {
              ref
                  .read(adNotifierProvider.notifier)
                  .recordNavigation(context, ref);
              context.push('/add');
            },
          ),
        ],
      ),
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const AdBannerWidget(), // Single Bottom Banner Ad (One per screen, away from controls)
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
