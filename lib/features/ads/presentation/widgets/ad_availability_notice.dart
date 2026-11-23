import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:myexpence/features/ads/presentation/providers/ad_providers.dart';
import 'ad_free_session_dialog.dart';

/// Lives above routes so navigation cannot reset the once-per-launch notice.
class AdAvailabilityNotice extends ConsumerStatefulWidget {
  final GlobalKey<NavigatorState> navigatorKey;
  final Widget child;
  const AdAvailabilityNotice(
      {super.key, required this.navigatorKey, required this.child});

  @override
  ConsumerState<AdAvailabilityNotice> createState() =>
      _AdAvailabilityNoticeState();
}

class _AdAvailabilityNoticeState extends ConsumerState<AdAvailabilityNotice> {
  bool _scheduled = false;

  void _checkNotice() {
    if (_scheduled) return;
    _scheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      if (!mounted) return;
      final navigator = widget.navigatorKey.currentState;
      if (navigator == null || !navigator.mounted) return;
      final notifier = ref.read(adNotifierProvider.notifier);
      if (!notifier.claimNoAdsNotice()) return;
      unawaited(showDialog<void>(
        context: navigator.context,
        barrierColor: Colors.black.withValues(alpha: .45),
        builder: (context) => const AdFreeSessionDialog(),
      ).whenComplete(notifier.finishNoAdsNotice));
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<AdState>(adNotifierProvider, (_, next) {
      if (next.noFillThisLaunch) _checkNotice();
    });
    if (ref.read(adNotifierProvider).noFillThisLaunch) _checkNotice();
    return widget.child;
  }
}
