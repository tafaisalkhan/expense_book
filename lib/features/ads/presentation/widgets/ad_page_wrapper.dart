import 'package:flutter/material.dart';
import 'package:myexpence/features/ads/presentation/providers/ad_providers.dart';

/// Wraps a full-screen route (outside the main shell) with a single bottom
/// banner ad (one per screen, away from controls, hidden while keyboard is open).
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
          Expanded(child: child),
          if (!keyboardOpen) const AdBannerWidget(),
        ],
      ),
    );
  }
}
