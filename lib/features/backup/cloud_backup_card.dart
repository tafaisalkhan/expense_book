import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'backup_refresh.dart';
import 'backup_scheduler.dart';
import 'cloud_backup_service.dart';
import 'monthly_backup_billing.dart';

class CloudBackupCard extends ConsumerStatefulWidget {
  const CloudBackupCard({super.key});
  @override
  ConsumerState<CloudBackupCard> createState() => _CloudBackupCardState();
}

class _CloudBackupCardState extends ConsumerState<CloudBackupCard>
    with WidgetsBindingObserver {
  final service = CloudBackupService();
  bool busy = false, wifiOnly = true;
  String frequency = 'off';
  String? lastBackup, status, lastError;
  int? bytes;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) load();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState lifecycle) {
    if (lifecycle == AppLifecycleState.resumed && mounted) {
      ref.read(monthlyBackupBillingProvider.notifier).refresh();
      load();
    }
  }

  Future<void> load() async {
    if (!mounted || ref.read(monthlyBackupBillingProvider).preview) return;
    try {
      final uid = await service.signedInUid();
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();
      if (!mounted) return;
      setState(() {
        frequency = prefs.getString('cloud_schedule_owner') == uid
            ? prefs.getString('cloud_schedule') ?? 'off'
            : 'off';
        wifiOnly = prefs.getBool('cloud_wifi_only') ?? true;
        lastBackup = prefs.getString('cloud_last_success_$uid');
        lastError = prefs.getString('cloud_last_error_$uid');
      });
      if (ref.read(monthlyBackupBillingProvider).active) {
        final metadata = await service.metadata();
        if (mounted && metadata != null) {
          setState(() {
            lastBackup = metadata.exportedAt;
            bytes = metadata.sizeBytes;
          });
        }
      }
    } catch (_) {
      /* Keep the last known status; explicit operations show errors. */
    }
  }

  Future<void> run(Future<String> Function() action) async {
    if (busy) return;
    setState(() {
      busy = true;
      status = null;
    });
    try {
      final message = await action();
      if (mounted) setState(() => status = message);
    } on CloudSubscriptionRequired {
      await ref.read(monthlyBackupBillingProvider.notifier).refresh();
      if (mounted) subscribe();
    } catch (e) {
      if (mounted) {
        setState(() => status = e.toString().contains('object-not-found')
            ? 'No cloud backup is available yet. Save your first backup before restoring.'
            : e.toString().replaceFirst('Bad state: ', ''));
      }
    } finally {
      if (mounted) {
        setState(() => busy = false);
        await load();
      }
    }
  }

  void subscribe() {
    showDialog<void>(
        context: context, builder: (_) => const _CloudBackupPlanDialog());
  }

  Future<void> restore() async {
    final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
              title: const Text('Restore your cloud backup?'),
              content: const Text(
                  'This replaces the expenses, categories, people, budgets and receipts on this device with your latest Cloud ZIP backup.'),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('Cancel')),
                FilledButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text('Replace and restore'))
              ],
            ));
    if (confirmed != true || !mounted) return;
    await run(() async {
      final message = await service.restore();
      if (mounted) refreshAfterBackupRestore(ref);
      return message;
    });
  }

  @override
  Widget build(BuildContext context) {
    final billing = ref.watch(monthlyBackupBillingProvider);
    ref.listen<CloudBackupBillingState>(monthlyBackupBillingProvider,
        (before, after) {
      if (before?.active != after.active) load();
    });
    final colors = Theme.of(context).colorScheme;
    final date = DateTime.tryParse(lastBackup ?? '');
    return Card(
        child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Icon(Icons.cloud_done_outlined, color: colors.primary),
                  const SizedBox(width: 10),
                  const Expanded(
                      child: Text('Cloud backup & restore',
                          style: TextStyle(
                              fontWeight: FontWeight.w700, fontSize: 16))),
                  if (!billing.active)
                    Icon(Icons.lock_outline,
                        color: colors.onSurfaceVariant, size: 19)
                ]),
                const SizedBox(height: 10),
                Text(
                    'Sign in with Google for automatic daily 12:00 PM ZIP cloud backup and an ad-free experience. Free users can use local device backup above.',
                    style: TextStyle(
                        color: colors.onSurfaceVariant, height: 1.45)),
                const SizedBox(height: 10),
                Text(
                    billing.active
                        ? 'Cloud backup subscription active · Ad-free enabled'
                        : '7-Day Free Trial · then ${billing.displayMonthlyPrice}/month or ${billing.displayYearlyPrice}/year',
                    style: TextStyle(
                        color: colors.primary, fontWeight: FontWeight.w600)),
                if (!billing.active) ...[
                  const SizedBox(height: 6),
                  Text(
                    'Try free for 7 days (\$0 today, cancel anytime on Google Play) — unlocks daily cloud backup, 100% ad-free, unlimited OCR & 10 voice entries/day.',
                    style: TextStyle(
                        fontSize: 12,
                        color: colors.onSurfaceVariant,
                        height: 1.35),
                  ),
                  const SizedBox(height: 14),
                  SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                          onPressed: subscribe,
                          icon: const Icon(Icons.cloud_upload_outlined),
                          label: const Text('Unlock cloud backup (7-Day Free Trial)'))),
                ] else ...[
                  const SizedBox(height: 12),
                  Builder(builder: (context) {
                    final limitBytes = CloudBackupService.maxZipBytesForProduct(
                        billing.activeProductId);
                    final limitMb = CloudBackupService.maxZipMbForProduct(
                        billing.activeProductId);
                    final usedBytes = bytes ?? 0;
                    final usedMb = usedBytes / (1024 * 1024);
                    final ratio = (usedBytes / limitBytes).clamp(0.0, 1.0);
                    final isYearly = billing.activeProductId ==
                        CloudBackupService.yearlyProductId;
                    final barColor = ratio > 0.92
                        ? colors.error
                        : (ratio > 0.78 ? Colors.orange : colors.primary);
                    return Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: colors.surfaceContainerHighest
                            .withValues(alpha: 0.45),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                            color: colors.outlineVariant.withValues(alpha: 0.6)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                isYearly
                                    ? 'Cloud Storage (Yearly 600 MB Plan)'
                                    : 'Cloud Storage (Monthly 100 MB Plan)',
                                style: const TextStyle(
                                    fontWeight: FontWeight.w600, fontSize: 12.5),
                              ),
                              Text(
                                '${usedMb.toStringAsFixed(2)} MB / $limitMb MB',
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 12.5,
                                  color: barColor,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(6),
                            child: LinearProgressIndicator(
                              value: ratio,
                              minHeight: 8,
                              color: barColor,
                              backgroundColor:
                                  colors.outlineVariant.withValues(alpha: 0.35),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${(ratio * 100).toStringAsFixed(1)}% of your $limitMb MB ZIP limit used',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    );
                  }),
                  const SizedBox(height: 12),
                  Text(date == null
                      ? 'Last backup: not saved yet'
                      : 'Last backup: ${DateFormat.yMMMd().add_jm().format(date.toLocal())}'),
                  if (bytes != null)
                    Text(
                        '${(bytes! / (1024 * 1024)).toStringAsFixed(2)} MB · Cloud ZIP'),
                  const SizedBox(height: 12),
                  Wrap(spacing: 10, runSpacing: 8, children: [
                    FilledButton.icon(
                        onPressed:
                            busy ? null : () => run(() => service.backUp()),
                        icon: const Icon(Icons.backup_outlined),
                        label: const Text('Back up now')),
                    OutlinedButton.icon(
                        onPressed: busy ? null : restore,
                        icon: const Icon(Icons.restore),
                        label: const Text('Restore backup')),
                  ]),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                      key: ValueKey(frequency),
                      initialValue: frequency,
                      decoration: const InputDecoration(
                          labelText: 'Automatic backup',
                          border: OutlineInputBorder()),
                      items: const [
                        DropdownMenuItem(value: 'off', child: Text('Off')),
                        DropdownMenuItem(
                            value: 'daily',
                            child: Text('Every day at 12:00 PM')),
                        DropdownMenuItem(
                            value: 'weekly',
                            child: Text('Every week at 12:00 PM'))
                      ],
                      onChanged: busy || !Platform.isAndroid
                          ? null
                          : (value) {
                              if (value != null) {
                                run(() async {
                                  await BackupScheduler.set(value,
                                      wifiOnly: wifiOnly);
                                  return value == 'off'
                                      ? 'Automatic backup turned off.'
                                      : value == 'weekly'
                                          ? 'Scheduled weekly 12:00 PM ZIP cloud backup.'
                                          : 'Scheduled daily 12:00 PM ZIP cloud backup.';
                                });
                              }
                            }),
                  SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Wi-Fi only'),
                      value: wifiOnly,
                      onChanged: busy
                          ? null
                          : (value) => run(() async {
                                if (frequency == 'off') {
                                  await (await SharedPreferences.getInstance())
                                      .setBool('cloud_wifi_only', value);
                                } else {
                                  await BackupScheduler.set(frequency,
                                      wifiOnly: value);
                                }
                                return 'Network preference saved.';
                              })),
                  const Text(
                      'Runs automatically around 12:00 PM when Android allows.'),
                ],
                const SizedBox(height: 10),
                Text(
                    'One latest ZIP per account · Up to 100 MB (\$0.99/mo) or 600 MB (\$5.99/yr)',
                    style: Theme.of(context).textTheme.bodySmall),
                if (lastError != null)
                  Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(lastError!,
                          style: TextStyle(color: colors.error))),
                if (status != null)
                  Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(status!)),
                if (busy)
                  const Padding(
                      padding: EdgeInsets.only(top: 12),
                      child: LinearProgressIndicator()),
              ],
            )));
  }
}

class _CloudBackupPlanDialog extends ConsumerWidget {
  const _CloudBackupPlanDialog();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(monthlyBackupBillingProvider);
    final controller = ref.read(monthlyBackupBillingProvider.notifier);
    final monthlyPrice = state.displayMonthlyPrice;
    final yearlyPrice = state.displayYearlyPrice;
    final colors = Theme.of(context).colorScheme;
    return AlertDialog(
      title: Row(children: [
        const Expanded(child: Text('Cloud Backup Plans')),
        IconButton(
            tooltip: 'Close',
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.close))
      ]),
      content: SingleChildScrollView(
          child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: colors.primaryContainer.withValues(alpha: 0.55),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                Icon(Icons.verified_outlined, size: 18, color: colors.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '7-Day Free Trial Included · \$0 today, cancel anytime on Google Play',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: colors.onPrimaryContainer,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          const Text(
              'Automatically zip and save your expenses, images & voice notes to the cloud every day at 12:00 PM — plus enjoy 100% ad-free, unlimited receipt OCR, and 10 voice entries/day. Local device ZIP download stays free.'),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: state.monthlyProduct != null &&
                      !state.pending &&
                      !state.preview
                  ? () => controller.buy(state.monthlyProduct)
                  : null,
              child: Text('7-Day Free Trial · then $monthlyPrice / month (100 MB)'),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: FilledButton.tonal(
              onPressed: state.yearlyProduct != null &&
                      !state.pending &&
                      !state.preview
                  ? () => controller.buy(state.yearlyProduct)
                  : null,
              child: Text('7-Day Free Trial · then $yearlyPrice / year (600 MB · Save 50%)'),
            ),
          ),
          if (state.preview)
            const Padding(
                padding: EdgeInsets.only(top: 12),
                child: Text(
                    'Purchases and cloud access are disabled in this local preview.')),
          if (state.message != null)
            Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(state.message!)),
          if (state.pending || state.checking)
            const Padding(
                padding: EdgeInsets.only(top: 12),
                child: LinearProgressIndicator()),
        ],
      )),
      actions: [
        TextButton(
            onPressed: state.pending || state.preview
                ? null
                : controller.restorePurchases,
            child: const Text('Restore purchase')),
      ],
    );
  }
}
