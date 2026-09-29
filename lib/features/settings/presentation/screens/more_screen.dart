import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:myexpence/core/theme/app_theme.dart';
import 'package:myexpence/features/ads/presentation/providers/ad_providers.dart';
import 'package:myexpence/features/auth/presentation/providers/auth_providers.dart';
import 'package:myexpence/features/security/presentation/providers/security_providers.dart';
import 'package:myexpence/features/sms_parser/domain/services/sms_listener_service.dart';
import 'package:myexpence/features/sms_parser/presentation/providers/sms_whitelist_provider.dart';
import 'package:myexpence/features/sms_parser/presentation/widgets/sms_approval_dialog.dart';
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
                              authUser.displayName ?? 'Google User',
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              authUser.email ?? 'Not logged in',
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
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('🎉 Ads Removed permanently (`remove_ads`)! Unrestricted access unlocked.'),
                                    backgroundColor: Colors.green,
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
                  leading: const Icon(Icons.account_balance_wallet, color: AppTheme.primaryColor),
                  title: const Text('Monthly & Category Budgets', style: TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: const Text('Set monthly limits and receive alert warnings'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push('/budgets'),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.calendar_month, color: AppTheme.primaryColor),
                  title: const Text('Expense Calendar', style: TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: const Text('View daily spending grid, missing days, and zero-spend log'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push('/calendar'),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.people, color: AppTheme.primaryColor),
                  title: const Text('Family Members & Profiles', style: TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: const Text('Manage household members and student profiles'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push('/people'),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.category, color: AppTheme.primaryColor),
                  title: const Text('Categories & Subcategories', style: TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: const Text('View and configure default spending taxonomy'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push('/categories'),
                ),
                const Divider(height: 1),

                // Location Reminders & Geofencing (Requires Rewarded Ad unless remove_ads purchased)
                ListTile(
                  leading: const Icon(Icons.location_on, color: AppTheme.primaryColor),
                  title: Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Location Reminders & Geofencing',
                          style: TextStyle(fontWeight: FontWeight.bold),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 6),
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
                  subtitle: const Text('Marts, Petrol Pumps & Hospital post-visit prompts (Runs after Rewarded Ad)'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    ref.read(adNotifierProvider.notifier).runWithRewardedAd(
                      context,
                      featureName: 'Location Reminders & Geofencing',
                      onRewardGranted: () => context.push('/location-notifications'),
                    );
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
                  leading: const Icon(Icons.security, color: Colors.blue),
                  title: const Text('Offline-First Security'),
                  subtitle: const Text('All financial records remain local to your device by default'),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.info_outline, color: Colors.grey),
                  title: const Text('MyExpense Version'),
                  subtitle: const Text('1.4.0 (Ad-Supported & Remove Ads Product Ready)'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
