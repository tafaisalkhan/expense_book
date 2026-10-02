import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:myexpence/core/theme/app_theme.dart';
import 'package:myexpence/features/subscription/domain/models/subscription_plan.dart';
import 'package:myexpence/features/subscription/presentation/providers/subscription_providers.dart';

class PaywallScreen extends ConsumerStatefulWidget {
  final String? featureName;

  const PaywallScreen({super.key, this.featureName});

  @override
  ConsumerState<PaywallScreen> createState() => _PaywallScreenState();
}

class _PaywallScreenState extends ConsumerState<PaywallScreen> {
  SubscriptionTier _selectedPlan = SubscriptionTier.premiumYearly; // Default to Yearly best value
  final _promoController = TextEditingController(text: 'FREE3M');

  @override
  void dispose() {
    _promoController.dispose();
    super.dispose();
  }

  Future<void> _applyPromoCode(String code) async {
    final success = await ref.read(subscriptionProvider.notifier).redeemPromoCode(code);
    if (mounted) {
      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('🎉 Promo Code Applied! All features freely available for 3 Months (90 Days).'),
            backgroundColor: Colors.green,
          ),
        );
        context.pop();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please enter a valid promotional code.'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final sub = ref.watch(subscriptionProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('My Expence Book Premium'),
        actions: [
          IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => context.pop(),
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Gold Icon Header
              Center(
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.amber.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.workspace_premium, size: 56, color: Colors.amber),
                ),
              ),
              const SizedBox(height: 12),

              Text(
                widget.featureName != null
                    ? 'Unlock ${widget.featureName}'
                    : 'Upgrade to My Expence Book Premium',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 6),
              Text(
                'Automate receipt entry, location reminders, and encrypted cloud sync.',
                style: TextStyle(color: Colors.grey[600], fontSize: 13),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),

              // Premium Features List
              Card(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    children: [
                      _buildFeatureRow(
                        context,
                        Icons.document_scanner,
                        'Automatic OCR Receipt Scanner',
                        'Scan bills, receipts, and school vouchers with instant item parsing.',
                      ),
                      const Divider(height: 20),
                      _buildFeatureRow(
                        context,
                        Icons.location_on,
                        'Location & Geofencing Reminders',
                        'Receive spending log prompts when near saved supermarkets & stations.',
                      ),
                      const Divider(height: 20),
                      _buildFeatureRow(
                        context,
                        Icons.cloud_sync,
                        'Encrypted Cloud Backup & Sync',
                        'Keep your local database synchronized across your devices securely.',
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Plan Selectors: 1. YEARLY ($15.00/yr) - BEST VALUE
              GestureDetector(
                onTap: () => setState(() => _selectedPlan = SubscriptionTier.premiumYearly),
                child: Card(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                    side: BorderSide(
                      color: _selectedPlan == SubscriptionTier.premiumYearly ? AppTheme.primaryColor : Colors.transparent,
                      width: 2,
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      children: [
                        Radio<SubscriptionTier>(
                          value: SubscriptionTier.premiumYearly,
                          groupValue: _selectedPlan,
                          onChanged: (val) {
                            if (val != null) setState(() => _selectedPlan = val);
                          },
                          activeColor: AppTheme.primaryColor,
                        ),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Wrap(
                                crossAxisAlignment: WrapCrossAlignment.center,
                                spacing: 6,
                                runSpacing: 4,
                                children: [
                                  const Text(
                                    'Yearly Subscription',
                                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: Colors.green,
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: const Text(
                                      'SAVE 58% • BEST VALUE',
                                      style: TextStyle(fontSize: 9, color: Colors.white, fontWeight: FontWeight.bold),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text('\$15.00 / Year (\$1.25/mo) • Save \$20.88', style: TextStyle(color: Colors.grey[600], fontSize: 12)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),

              // Plan Selectors: 2. MONTHLY ($2.99/mo)
              GestureDetector(
                onTap: () => setState(() => _selectedPlan = SubscriptionTier.premiumMonthly),
                child: Card(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                    side: BorderSide(
                      color: _selectedPlan == SubscriptionTier.premiumMonthly ? AppTheme.primaryColor : Colors.transparent,
                      width: 2,
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      children: [
                        Radio<SubscriptionTier>(
                          value: SubscriptionTier.premiumMonthly,
                          groupValue: _selectedPlan,
                          onChanged: (val) {
                            if (val != null) setState(() => _selectedPlan = val);
                          },
                          activeColor: AppTheme.primaryColor,
                        ),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Wrap(
                                crossAxisAlignment: WrapCrossAlignment.center,
                                spacing: 6,
                                runSpacing: 4,
                                children: [
                                  const Text(
                                    'Monthly Subscription',
                                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: Colors.amber[800],
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: const Text(
                                      '7 DAYS FREE',
                                      style: TextStyle(fontSize: 9, color: Colors.white, fontWeight: FontWeight.bold),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text('\$2.99 / Month • Cancel anytime', style: TextStyle(color: Colors.grey[600], fontSize: 12)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Inline Promo / Access Code Card (Free Access)
              Card(
                color: Colors.amber.withValues(alpha: 0.08),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: BorderSide(color: Colors.amber.withValues(alpha: 0.5)),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(14.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.card_giftcard, color: Colors.amber, size: 20),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Have a Promo Code? (Free Access)',
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'Enter your promotional code below or tap to get 3 Months Free Premium access.',
                        style: TextStyle(fontSize: 12, color: Colors.black87),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _promoController,
                              decoration: const InputDecoration(
                                hintText: 'e.g. FREE3M',
                                isDense: true,
                                border: OutlineInputBorder(),
                                contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                              ),
                              textCapitalization: TextCapitalization.characters,
                            ),
                          ),
                          const SizedBox(width: 8),
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.amber[800],
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                            ),
                            onPressed: () => _applyPromoCode(_promoController.text),
                            child: const Text('Apply'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.amber[900],
                            side: BorderSide(color: Colors.amber[800]!),
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                          ),
                          onPressed: () => _applyPromoCode('FREE3M'),
                          icon: const Icon(Icons.bolt, size: 16),
                          label: const FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              '⚡ Claim 3-Month FREE Access (Code: FREE3M)',
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Active status or Action Buttons
              if (sub.isPremium) ...[
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.green.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.check_circle, color: Colors.green),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'You are subscribed to ${sub.tier.title}!',
                          style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.green),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.red[700],
                    side: BorderSide(color: Colors.red[300]!),
                  ),
                  onPressed: () async {
                    await ref.read(subscriptionProvider.notifier).cancelSubscription();
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Switched to Free Tier. Ads are now ENABLED.'),
                          backgroundColor: Colors.orange,
                        ),
                      );
                    }
                  },
                  icon: const Icon(Icons.block, size: 18),
                  label: const Text('Switch to Free Tier (Enable Ads for Testing)'),
                ),
              ] else ...[
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primaryColor,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: () async {
                      if (_selectedPlan == SubscriptionTier.premiumYearly) {
                        await ref.read(subscriptionProvider.notifier).subscribeYearly();
                      } else {
                        await ref.read(subscriptionProvider.notifier).subscribeMonthly();
                      }

                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('${_selectedPlan.title} (${_selectedPlan.formattedPrice}) Activated! Welcome to Premium.')),
                        );
                        context.pop();
                      }
                    },
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        _selectedPlan == SubscriptionTier.premiumYearly
                            ? 'SUBSCRIBE YEARLY (\$15.00/yr)'
                            : 'SUBSCRIBE MONTHLY (\$2.99/mo)',
                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Center(
                  child: TextButton(
                    onPressed: () async {
                      await ref.read(subscriptionProvider.notifier).startFreeTrial();
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('7-Day Free Trial Started! Enjoy Premium.')),
                        );
                        context.pop();
                      }
                    },
                    child: const Text('Start 7-Day Free Trial'),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFeatureRow(BuildContext context, IconData icon, String title, String subtitle) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: AppTheme.primaryColor, size: 22),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
              const SizedBox(height: 2),
              Text(subtitle, style: TextStyle(fontSize: 12, color: Colors.grey[600])),
            ],
          ),
        ),
      ],
    );
  }
}
