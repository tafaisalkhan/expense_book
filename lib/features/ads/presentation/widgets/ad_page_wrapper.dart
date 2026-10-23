import 'package:flutter/material.dart';
import 'package:myexpence/features/ads/presentation/providers/ad_providers.dart';

/// Wraps a full-screen route (outside the main shell) with a top and bottom
/// banner ad so that every navigation destination shows ads.
///
/// - Top banner sits below the status bar; the child's top padding is removed
///   so its AppBar does not add a second status-bar gap.
/// - Bottom banner is hidden while the keyboard is open so forms stay usable.
class AdPageWrapper extends StatelessWidget {
  final Widget child;

  const AdPageWrapper({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final keyboardOpen = MediaQuery.of(context).viewInsets.bottom > 0;

    return Material(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: Column(
        children: [
          const SafeArea(bottom: false, child: AdBannerWidget(isTop: true)), // Top Banner
          Expanded(child: child),
          if (!keyboardOpen)
            const SafeArea(top: false, child: AdBannerWidget()), // Bottom Banner
        ],
      ),
    );
  }
}
