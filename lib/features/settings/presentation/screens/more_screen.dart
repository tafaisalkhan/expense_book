import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:myexpence/core/theme/app_theme.dart';
import 'package:myexpence/core/utils/app_error_logger.dart';
import 'package:myexpence/features/ads/presentation/providers/ad_providers.dart';
import 'package:myexpence/features/auth/presentation/providers/auth_providers.dart';
import 'package:myexpence/features/security/presentation/providers/security_providers.dart';
import 'package:myexpence/features/settings/domain/models/app_currency.dart';
import 'package:myexpence/features/settings/presentation/providers/settings_providers.dart';
import 'package:myexpence/features/subscription/domain/services/local_data_backup_service.dart';

class MoreScreen extends ConsumerWidget {
  const MoreScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authUser = ref.watch(authProvider);
    final isAdsRemoved = ref.watch(isAdsRemovedProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('More & Settings'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Google Profile & Account Card (Firebase for Login only)
          Card(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                children: [
                  Row(
                    children: [
                      CircleAvatar(
                        radius: 24,
                        backgroundColor: AppTheme.primaryColor,
                        child: Text(
                          (authUser.displayName ?? authUser.email ?? 'G')[0].toUpperCase(),
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              authUser.displayName ??
                                  (kDebugMode ? 'Test User (Local Mode)' : 'Google User'),
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              authUser.email ??
                                  (kDebugMode ? 'No login required (Test Mode)' : 'Not logged in'),
                              style: TextStyle(fontSize: 13, color: Colors.grey[700]),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  if (authUser.isLoggedIn) ...[
                    const Divider(height: 24),
                    Row(
                      children: [
                        // Sign Out Button
                        Expanded(
                          child: OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.grey[800],
                              visualDensity: VisualDensity.compact,
                            ),
                            onPressed: () async {
                              final confirm = await showDialog<bool>(
                                context: context,
                                builder: (ctx) => AlertDialog(
                                  title: const Row(
                                    children: [
                                      Icon(Icons.logout, color: Colors.orange),
                                      SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          'Sign Out & Clear Data?',
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ],
                                  ),
                                  content: const Text(
                                    'Are you sure you want to sign out? This will sign you out and permanently flush all local expenses, profiles, and data from this device.',
                                  ),
                                  actions: [
                                    TextButton(
                                      onPressed: () => Navigator.pop(ctx, false),
                                      child: const Text('Cancel'),
                                    ),
                                    ElevatedButton(
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.orange[800],
                                        foregroundColor: Colors.white,
                                      ),
                                      onPressed: () => Navigator.pop(ctx, true),
                                      child: const Text('Sign Out'),
                                    ),
                                  ],
                                ),
                              );

                              if (confirm == true && context.mounted) {
                                showDialog(
                                  context: context,
                                  barrierDismissible: false,
                                  builder: (ctx) => const PopScope(
                                    canPop: false,
                                    child: AlertDialog(
                                      content: Row(
                                        children: [
                                          CircularProgressIndicator(),
                                          SizedBox(width: 20),
                                          Expanded(
                                            child: Text(
                                              'Signing out & flushing device data...',
                                              style: TextStyle(fontWeight: FontWeight.bold),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                );

                                await ref.read(authProvider.notifier).signOut();

                                if (context.mounted) {
                                  Navigator.of(context, rootNavigator: true).pop();

                                  await showDialog(
                                    context: context,
                                    barrierDismissible: false,
                                    builder: (ctx) => AlertDialog(
                                      title: const Row(
                                        children: [
                                          Icon(Icons.check_circle, color: Colors.green),
                                          SizedBox(width: 8),
                                          Expanded(
                                            child: Text(
                                              'Signed Out',
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                        ],
                                      ),
                                      content: const Text(
                                        'Signed out successfully. All local device data has been flushed.',
                                        style: TextStyle(fontSize: 14),
                                      ),
                                      actions: [
                                        ElevatedButton(
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: AppTheme.primaryColor,
                                            foregroundColor: Colors.white,
                                          ),
                                          onPressed: () {
                                            Navigator.pop(ctx);
                                            context.go('/login');
                                          },
                                          child: const Text('OK'),
                                        ),
                                      ],
                                    ),
                                  );
                                }
                              }
                            },
                            icon: const Icon(Icons.logout, size: 16),
                            label: const Text('Sign Out', overflow: TextOverflow.ellipsis),
                          ),
                        ),
                        const SizedBox(width: 8),

                        // Delete Account Button
                        Expanded(
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.red[50],
                              foregroundColor: Colors.red[700],
                              elevation: 0,
                              visualDensity: VisualDensity.compact,
                            ),
                            onPressed: () async {
                              final confirm = await showDialog<bool>(
                                context: context,
                                builder: (ctx) => AlertDialog(
                                  title: const Row(
                                    children: [
                                      Icon(Icons.warning_amber_rounded, color: Colors.red),
                                      SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          'Delete Account?',
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ],
                                  ),
                                  content: const Text(
                                    'Are you sure you want to delete your account? This will permanently erase all your data from this device and sign you out of MyExpense.',
                                  ),
                                  actions: [
                                    TextButton(
                                      onPressed: () => Navigator.pop(ctx, false),
                                      child: const Text('Cancel'),
                                    ),
                                    ElevatedButton(
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.red,
                                        foregroundColor: Colors.white,
                                      ),
                                      onPressed: () => Navigator.pop(ctx, true),
                                      child: const Text('Delete Account'),
                                    ),
                                  ],
                                ),
                              );

                              if (confirm == true && context.mounted) {
                                showDialog(
                                  context: context,
                                  barrierDismissible: false,
                                  builder: (ctx) => const PopScope(
                                    canPop: false,
                                    child: AlertDialog(
                                      content: Row(
                                        children: [
                                          CircularProgressIndicator(),
                                          SizedBox(width: 20),
                                          Expanded(
                                            child: Text(
                                              'Deleting account & wiping all data...',
                                              style: TextStyle(fontWeight: FontWeight.bold),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                );

                                await ref.read(authProvider.notifier).deleteAccount();

                                if (context.mounted) {
                                  Navigator.of(context, rootNavigator: true).pop();
                                  context.go('/login');
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Row(
                                        children: [
                                          Icon(Icons.check_circle, color: Colors.white, size: 20),
                                          SizedBox(width: 10),
                                          Expanded(
                                            child: Text(
                                              'Account deleted & logged out successfully.',
                                              style: TextStyle(fontWeight: FontWeight.bold),
                                            ),
                                          ),
                                        ],
                                      ),
                                      backgroundColor: Colors.redAccent,
                                      duration: Duration(seconds: 4),
                                    ),
                                  );
                                }
                              }
                            },
                            icon: const Icon(Icons.delete_forever, size: 16),
                            label: const Text('Delete Account', overflow: TextOverflow.ellipsis),
                          ),
                        ),
                      ],
                    ),
                  ] else ...[
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () => context.go('/login'),
                        child: const Text('Sign In with Google'),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Remove Ads Product Card (`remove_ads`)
          Card(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(color: isAdsRemoved ? Colors.green : Colors.amber),
            ),
            color: isAdsRemoved ? Colors.green.withValues(alpha: 0.08) : Colors.amber.withValues(alpha: 0.1),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        isAdsRemoved ? Icons.check_circle : Icons.star,
                        color: isAdsRemoved ? Colors.green : Colors.amber,
                        size: 32,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              isAdsRemoved ? 'Remove Ads Purchased ✅' : 'Remove All Ads (`remove_ads`)',
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              isAdsRemoved
                                  ? 'All banner, interstitial & rewarded ads are completely removed!'
                                  : 'One-time Google Play purchase (\$4.99). Bypasses all Rewarded Ads for Location, SMS, Download & Restore!',
                              style: TextStyle(fontSize: 12, color: Colors.grey[800]),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: isAdsRemoved ? Colors.green[700] : Colors.amber[800],
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      onPressed: isAdsRemoved
                          ? null
                          : () async {
                              await ref.read(adNotifierProvider.notifier).purchaseRemoveAds();
                              if (context.mounted) {
                                final isNowRemoved = ref.read(adNotifierProvider).isAdsRemoved;
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      isNowRemoved
                                          ? '🎉 Ads Removed permanently (`remove_ads`)! Unrestricted access unlocked.'
                                          : 'ℹ️ Purchase request processed.',
                                    ),
                                    backgroundColor: isNowRemoved ? Colors.green : Colors.blue,
                                  ),
                                );
                              }
                            },
                      icon: Icon(isAdsRemoved ? Icons.verified : Icons.shopping_bag, size: 18),
                      label: Text(
                        isAdsRemoved ? 'Ads Removed Permanently ✅' : 'Remove Ads (\$4.99)',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                      ),
                    ),
                  ),
                  if (isAdsRemoved) ...[
                    const SizedBox(height: 6),
                    Center(
                      child: TextButton.icon(
                        onPressed: () async {
                          await ref.read(adNotifierProvider.notifier).resetAds();
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('🔄 Ads enabled again for testing!'),
                                backgroundColor: Colors.blue,
                              ),
                            );
                          }
                        },
                        icon: const Icon(Icons.refresh, size: 16),
                        label: const Text('Reset / Enable Ads (Testing)', style: TextStyle(fontSize: 12)),
                      ),
                    ),
                  ],
                  if (!isAdsRemoved) ...[
                    const SizedBox(height: 6),
                    Center(
                      child: TextButton.icon(
                        onPressed: () async {
                          await ref.read(adNotifierProvider.notifier).restorePurchases();
                          if (context.mounted) {
                            final isNowRemoved = ref.read(adNotifierProvider).isAdsRemoved;
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  isNowRemoved
                                      ? '🎉 Google Play purchase restored! Ads Removed permanently.'
                                      : 'ℹ️ Google Play restore check completed.',
                                ),
                                backgroundColor: isNowRemoved ? Colors.green : Colors.blue,
                              ),
                            );
                          }
                        },
                        icon: const Icon(Icons.restore, size: 16),
                        label: const Text('Already Purchased? Restore Purchases', style: TextStyle(fontSize: 12)),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Main App Navigation Tiles
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.receipt_long, color: AppTheme.primaryColor),
                  title: const Text('All Expenses & History', style: TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: const Text('View and filter all expenses by type, date, or category'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    ref.read(adNotifierProvider.notifier).recordNavigation(context);
                    context.push('/expenses');
                  },
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.account_balance_wallet, color: AppTheme.primaryColor),
                  title: const Text('Monthly & Category Budgets', style: TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: const Text('Set monthly limits and receive alert warnings'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    ref.read(adNotifierProvider.notifier).recordNavigation(context);
                    context.push('/budgets');
                  },
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.calendar_month, color: AppTheme.primaryColor),
                  title: const Text('Expense Calendar', style: TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: const Text('View daily spending grid, missing days, and zero-spend log'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    ref.read(adNotifierProvider.notifier).recordNavigation(context);
                    context.push('/calendar');
                  },
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.people, color: AppTheme.primaryColor),
                  title: const Text('Family Members & Profiles', style: TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: const Text('Manage household members and student profiles'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    ref.read(adNotifierProvider.notifier).recordNavigation(context);
                    context.push('/people');
                  },
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.category, color: AppTheme.primaryColor),
                  title: const Text('Categories & Subcategories', style: TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: const Text('View and configure default spending taxonomy'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    ref.read(adNotifierProvider.notifier).recordNavigation(context);
                    context.push('/categories');
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Local Data Download & Restore Card (Runs after Rewarded Ad unless remove_ads purchased)
          Card(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.sd_storage, color: AppTheme.primaryColor),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          'Local Data Download & Restore',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (!isAdsRemoved)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.purple,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Text('🎬 AD', style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.white)),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Export your expenses & data to a local file. Restore this backup file on any device. (Runs after Rewarded Ad):',
                    style: TextStyle(fontSize: 12, color: Colors.grey[700]),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      // Download Data Button
                      Expanded(
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.teal[700],
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                          onPressed: () {
                            ref.read(adNotifierProvider.notifier).runWithRewardedAd(
                              context,
                              featureName: 'Download Local Data',
                              onRewardGranted: () async {
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text('📦 Exporting expenses & database to file...')),
                                  );
                                }
                                final localService = ref.read(localDataBackupServiceProvider);
                                final result = await localService.downloadLocalDataFile(ref);
                                if (context.mounted) {
                                  showDialog(
                                    context: context,
                                    builder: (ctx) => AlertDialog(
                                      title: Row(
                                        children: [
                                          Icon(
                                            result.success ? Icons.check_circle : Icons.error,
                                            color: result.success ? Colors.green : Colors.red,
                                          ),
                                          const SizedBox(width: 8),
                                          const Text('Download Data'),
                                        ],
                                      ),
                                      content: Text(
                                        result.success
                                            ? '${result.message}\n\nSaved File Path:\n${result.filePath}'
                                            : result.message,
                                        style: const TextStyle(fontSize: 13),
                                      ),
                                      actions: [
                                        ElevatedButton(
                                          onPressed: () => Navigator.pop(ctx),
                                          child: const Text('OK'),
                                        ),
                                      ],
                                    ),
                                  );
                                }
                              },
                            );
                          },
                          icon: const Icon(Icons.download, size: 18),
                          label: const Text('Download Data', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                        ),
                      ),
                      const SizedBox(width: 10),

                      // Restore Data Button
                      Expanded(
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.teal[800],
                            side: BorderSide(color: Colors.teal[300]!),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                          onPressed: () {
                            ref.read(adNotifierProvider.notifier).runWithRewardedAd(
                              context,
                              featureName: 'Restore Local Data',
                              onRewardGranted: () async {
                                final localService = ref.read(localDataBackupServiceProvider);
                                final result = await localService.restoreFromSelectedFile(ref);
                                if (context.mounted) {
                                  showDialog(
                                    context: context,
                                    builder: (ctx) => AlertDialog(
                                      title: Row(
                                        children: [
                                          Icon(
                                            result.success ? Icons.check_circle : Icons.warning_amber,
                                            color: result.success ? Colors.green : Colors.orange,
                                          ),
                                          const SizedBox(width: 8),
                                          const Text('Restore Data'),
                                        ],
                                      ),
                                      content: Text(
                                        result.message,
                                        style: const TextStyle(fontSize: 13),
                                      ),
                                      actions: [
                                        ElevatedButton(
                                          onPressed: () => Navigator.pop(ctx),
                                          child: const Text('OK'),
                                        ),
                                      ],
                                    ),
                                  );
                                }
                              },
                            );
                          },
                          icon: const Icon(Icons.folder_open, size: 18),
                          label: const Text('Restore Data', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          Card(
            child: Column(
              children: [
                Consumer(
                  builder: (context, ref, _) {
                    final currState = ref.watch(currencyNotifierProvider);
                    final preset = currState.matchingPreset;
                    final display = preset != null
                        ? '${preset.flag}  ${preset.name} (${currState.symbol})'
                        : '${currState.code} (${currState.symbol})';
                    return ListTile(
                      leading: const Icon(Icons.currency_exchange, color: AppTheme.primaryColor),
                      title: const Text('Default Currency', style: TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: Text(
                        'Active: $display • Tap to change',
                        style: const TextStyle(fontSize: 12),
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => _showCurrencyPicker(context, ref),
                    );
                  },
                ),
                const Divider(height: 1),
                Consumer(
                  builder: (context, ref, _) {
                    final secState = ref.watch(securityNotifierProvider);
                    return SwitchListTile(
                      secondary: const Icon(Icons.fingerprint, color: AppTheme.primaryColor),
                      title: const Text('Fingerprint / Device Lock', style: TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: Text(
                        secState.isAppLockEnabled
                            ? '🔒 Active — Fingerprint, Face ID or PIN required to open app'
                            : '🔓 Disabled — Tap to enable Fingerprint / PIN security shield',
                        style: TextStyle(fontSize: 12, color: secState.isAppLockEnabled ? Colors.green[800] : Colors.grey[700]),
                      ),
                      value: secState.isAppLockEnabled,
                      onChanged: (bool value) async {
                        final ok = await ref.read(securityNotifierProvider.notifier).toggleAppLock(value);
                        if (!ok && value && context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('⚠️ Authentication failed or device security not set up.'),
                              backgroundColor: Colors.red,
                            ),
                          );
                        } else if (ok && context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(value ? '🔒 App Lock Enabled! Fingerprint/PIN required to open MyExpense.' : '🔓 App Lock Disabled.'),
                              backgroundColor: value ? Colors.green : Colors.grey[800],
                            ),
                          );
                        }
                      },
                    );
                  },
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.bug_report_outlined, color: Colors.deepOrange),
                  title: const Text('App Startup Diagnostic Logs', style: TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: const Text('View persistent runtime exception logs & diagnostic reports'),
                  onTap: () async {
                    final logs = await AppErrorLogger.getLogs();
                    if (context.mounted) {
                      showDialog(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          title: const Row(
                            children: [
                              Icon(Icons.bug_report, color: Colors.deepOrange),
                              SizedBox(width: 8),
                              Text('Diagnostic Logs'),
                            ],
                          ),
                          content: SizedBox(
                            width: double.maxFinite,
                            child: logs.isEmpty
                                ? const Text('✅ No startup error logs recorded. App running smoothly!')
                                : ListView.separated(
                                    shrinkWrap: true,
                                    itemCount: logs.length,
                                    separatorBuilder: (_, __) => const Divider(),
                                    itemBuilder: (context, index) {
                                      return SelectableText(
                                        logs[index],
                                        style: const TextStyle(fontSize: 11, fontFamily: 'monospace'),
                                      );
                                    },
                                  ),
                          ),
                          actions: [
                            if (logs.isNotEmpty)
                              TextButton(
                                onPressed: () async {
                                  await AppErrorLogger.clearLogs();
                                  if (ctx.mounted) Navigator.pop(ctx);
                                },
                                child: const Text('Clear Logs', style: TextStyle(color: Colors.red)),
                              ),
                            ElevatedButton(
                              onPressed: () => Navigator.pop(ctx),
                              child: const Text('Close'),
                            ),
                          ],
                        ),
                      );
                    }
                  },
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.info_outline, color: Colors.grey),
                  title: const Text('MyExpense Version'),
                  subtitle: const Text('1.3.3+38 (Multi-Currency & Subcategories Ready)'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showCurrencyPicker(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        String query = '';
        return StatefulBuilder(
          builder: (context, setModalState) {
            final activeCurr = ref.watch(currencyNotifierProvider);
            final filtered = famousCurrencies.where((c) {
              final q = query.toLowerCase();
              return c.name.toLowerCase().contains(q) ||
                  c.code.toLowerCase().contains(q) ||
                  c.symbol.toLowerCase().contains(q);
            }).toList();

            return DraggableScrollableSheet(
              initialChildSize: 0.8,
              minChildSize: 0.5,
              maxChildSize: 0.95,
              expand: false,
              builder: (_, scrollController) {
                return Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                      child: Row(
                        children: [
                          const Icon(Icons.currency_exchange, color: AppTheme.primaryColor),
                          const SizedBox(width: 8),
                          const Expanded(
                            child: Text(
                              'Select App Currency',
                              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close),
                            onPressed: () => Navigator.pop(ctx),
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                      child: TextField(
                        decoration: InputDecoration(
                          hintText: 'Search currency (e.g. USD, EUR, Rs, ₹)...',
                          prefixIcon: const Icon(Icons.search),
                          isDense: true,
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        onChanged: (val) => setModalState(() => query = val),
                      ),
                    ),
                    const Divider(),
                    Expanded(
                      child: ListView.separated(
                        controller: scrollController,
                        itemCount: filtered.length + 1,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (context, idx) {
                          if (idx == filtered.length) {
                            return ListTile(
                              leading: const CircleAvatar(
                                child: Icon(Icons.edit, size: 18),
                              ),
                              title: const Text('Custom Currency Symbol', style: TextStyle(fontWeight: FontWeight.bold)),
                              subtitle: const Text('Enter any custom currency code and symbol'),
                              onTap: () {
                                Navigator.pop(ctx);
                                _showCustomCurrencyDialog(context, ref);
                              },
                            );
                          }
                          final c = filtered[idx];
                          final isSelected = activeCurr.symbol == c.symbol || activeCurr.code == c.code;
                          return ListTile(
                            leading: Text(c.flag, style: const TextStyle(fontSize: 24)),
                            title: Text('${c.name} (${c.symbol})', style: const TextStyle(fontWeight: FontWeight.w600)),
                            subtitle: Text('Code: ${c.code}'),
                            trailing: isSelected
                                ? const Icon(Icons.check_circle, color: Colors.green)
                                : null,
                            selected: isSelected,
                            onTap: () async {
                              await ref.read(currencyNotifierProvider.notifier).setCurrency(c);
                              if (ctx.mounted) Navigator.pop(ctx);
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text('Currency updated to ${c.name} (${c.symbol})'),
                                    backgroundColor: Colors.green,
                                  ),
                                );
                              }
                            },
                          );
                        },
                      ),
                    ),
                  ],
                );
              },
            );
          },
        );
      },
    );
  }

  void _showCustomCurrencyDialog(BuildContext context, WidgetRef ref) {
    final codeCtrl = TextEditingController();
    final symbolCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Custom Currency'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: codeCtrl,
              decoration: const InputDecoration(
                labelText: 'Currency Code (e.g. SEK, CHF, KRW)',
                border: OutlineInputBorder(),
              ),
              textCapitalization: TextCapitalization.characters,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: symbolCtrl,
              decoration: const InputDecoration(
                labelText: 'Currency Symbol (e.g. kr, Fr, ₩)',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              final symbol = symbolCtrl.text.trim();
              final code = codeCtrl.text.trim();
              if (symbol.isEmpty) return;
              await ref.read(currencyNotifierProvider.notifier).setCustomCurrency(code: code, symbol: symbol);
              if (ctx.mounted) Navigator.pop(ctx);
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Currency updated to $code ($symbol)'),
                    backgroundColor: Colors.green,
                  ),
                );
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }
}
