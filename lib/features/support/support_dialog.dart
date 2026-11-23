import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:myexpence/features/ads/presentation/providers/ad_providers.dart';
import 'support_actions.dart';

class SupportDialog extends ConsumerStatefulWidget {
  final SupportAction action;
  const SupportDialog({super.key, required this.action});
  @override
  ConsumerState<SupportDialog> createState() => _SupportDialogState();
}

class _SupportDialogState extends ConsumerState<SupportDialog> {
  bool _opening = false;
  String? _error;

  Future<void> act() async {
    final actions = ref.read(supportActionsProvider.notifier);
    if (widget.action == SupportAction.coffee) {
      if (ref.read(supportActionsProvider).preview) {
        setState(() => _error =
            'Purchases are disabled in this local preview. No payment will be taken.');
      } else {
        await actions.buyCoffee();
      }
      return;
    }
    setState(() {
      _opening = true;
      _error = null;
    });
    try {
      if (widget.action == SupportAction.rate) {
        await actions.rate();
      } else {
        await actions.share();
      }
      if (mounted) Navigator.pop(context);
    } catch (_) {
      if (mounted) {
        setState(() {
          _opening = false;
          _error = widget.action == SupportAction.rate
              ? 'Could not open Google Play. Please try again later.'
              : 'Could not open sharing. Please try again.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final noAds =
        ref.watch(adNotifierProvider.select((s) => s.noFillThisLaunch));
    final coffee = ref.watch(supportActionsProvider);
    final isCoffee = widget.action == SupportAction.coffee;
    final purchased = isCoffee && coffee.status == CoffeeStatus.purchased;
    final pending = isCoffee && coffee.status == CoffeeStatus.pending;
    final price = coffee.product?.price ?? (coffee.preview ? '\$1.99' : '');
    final icon = switch (widget.action) {
      SupportAction.rate => Icons.star_rounded,
      SupportAction.share => Icons.ios_share_rounded,
      SupportAction.coffee => Icons.coffee_outlined,
    };
    final title = purchased
        ? 'Thank you for\nyour support.'
        : switch (widget.action) {
            SupportAction.rate => 'Enjoying\nMy Expence Book?',
            SupportAction.share => 'Good habits\nare better shared.',
            SupportAction.coffee => 'A little coffee.\nA lot of support.',
          };
    final description = purchased
        ? 'Your coffee helps support the app. We appreciate it.'
        : switch (widget.action) {
            SupportAction.rate =>
              'Leave an honest review on Google Play. Your feedback helps us make everyday expense tracking better.',
            SupportAction.share =>
              'Know someone who wants to keep spending organized? Send them a link to the app.',
            SupportAction.coffee =>
              'Help support the work behind My Expence Book with a one-time coffee. Completely optional.',
          };
    final label = purchased
        ? 'You’re welcome'
        : switch (widget.action) {
            SupportAction.rate => 'Rate on Google Play',
            SupportAction.share => 'Share the app',
            SupportAction.coffee => pending
                ? 'Payment pending…'
                : coffee.status == CoffeeStatus.loading
                    ? 'Checking availability…'
                    : price.isNotEmpty
                        ? 'Buy a coffee · $price'
                        : 'Currently unavailable',
          };
    final canAct = !_opening &&
        !pending &&
        (!isCoffee || purchased || coffee.preview || coffee.product != null);

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
      backgroundColor: colors.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: SingleChildScrollView(
            child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                        color: colors.primary.withValues(alpha: .09),
                        borderRadius: BorderRadius.circular(18)),
                    child: Icon(purchased ? Icons.favorite_outline : icon,
                        color: colors.primary, size: 29)),
                IconButton(
                    tooltip: 'Close',
                    onPressed: () => Navigator.pop(context),
                    style: IconButton.styleFrom(
                        backgroundColor:
                            colors.onSurface.withValues(alpha: .05),
                        foregroundColor: colors.onSurfaceVariant,
                        minimumSize: const Size(44, 44)),
                    icon: const Icon(Icons.close_rounded, size: 21)),
              ]),
              const SizedBox(height: 24),
              Text(noAds ? 'NO ADS TODAY — AD-FREE' : 'A SMALL WAY TO SUPPORT',
                  style: theme.textTheme.labelSmall?.copyWith(
                      color: colors.primary,
                      fontWeight: FontWeight.w700,
                      letterSpacing: .8)),
              const SizedBox(height: 10),
              Text(title,
                  style: theme.textTheme.headlineMedium?.copyWith(
                      fontSize: 28,
                      height: 1.18,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -.6)),
              const SizedBox(height: 14),
              Text(description,
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: colors.onSurfaceVariant, height: 1.55)),
              if (isCoffee && !purchased) ...[
                const SizedBox(height: 14),
                Text(
                    coffee.preview
                        ? 'Preview price. Checkout is disabled here.'
                        : coffee.product != null
                            ? 'One-time purchase through Google Play. No subscription.'
                            : 'Coffee support is not available right now. You can keep using the app.',
                    style: theme.textTheme.bodySmall?.copyWith(
                        color: colors.onSurfaceVariant, height: 1.4)),
              ],
              if (_error != null || (isCoffee && coffee.message != null)) ...[
                const SizedBox(height: 12),
                Text(_error ?? coffee.message!,
                    style: TextStyle(color: colors.error, height: 1.4)),
              ],
              const SizedBox(height: 24),
              SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                      onPressed: canAct
                          ? purchased
                              ? () => Navigator.pop(context)
                              : act
                          : null,
                      style: FilledButton.styleFrom(
                          minimumSize: const Size(0, 52),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14)),
                          textStyle: const TextStyle(
                              fontSize: 15, fontWeight: FontWeight.w600)),
                      child: Text(_opening ? 'Opening…' : label))),
              const SizedBox(height: 8),
              Center(
                  child: TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Maybe later'))),
            ],
          ),
        )),
      ),
    );
  }
}
