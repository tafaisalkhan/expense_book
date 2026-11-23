import 'package:flutter/material.dart';

class AdFreeSessionDialog extends StatelessWidget {
  const AdFreeSessionDialog({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final dark = theme.brightness == Brightness.dark;
    void close() => Navigator.of(context).pop();

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
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        color:
                            colors.primary.withValues(alpha: dark ? .18 : .08),
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: Icon(Icons.spa_outlined,
                          size: 29, color: colors.primary),
                    ),
                    IconButton(
                      tooltip: 'Close',
                      onPressed: close,
                      style: IconButton.styleFrom(
                        backgroundColor:
                            colors.onSurface.withValues(alpha: .05),
                        foregroundColor: colors.onSurfaceVariant,
                        minimumSize: const Size(44, 44),
                      ),
                      icon: const Icon(Icons.close_rounded, size: 21),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                Text(
                  'NO ADS TODAY — AD-FREE',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: colors.primary,
                    fontWeight: FontWeight.w700,
                    letterSpacing: .8,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  'Enjoy your\nad-free session.',
                  style: theme.textTheme.headlineMedium?.copyWith(
                    fontSize: 28,
                    height: 1.18,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -.6,
                    color: colors.onSurface,
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  'Ads are unavailable right now. Keep tracking your expenses without interruptions.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colors.onSurfaceVariant,
                    height: 1.55,
                  ),
                ),
                const SizedBox(height: 22),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: colors.primary.withValues(alpha: dark ? .12 : .045),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                        color: colors.primary.withValues(alpha: .10)),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.backup_outlined,
                          color: colors.primary, size: 22),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Local backup & restore',
                                style: theme.textTheme.titleSmall?.copyWith(
                                    fontWeight: FontWeight.w600,
                                    color: colors.onSurface)),
                            const SizedBox(height: 4),
                            Text('Ready to use. No video required.',
                                style: theme.textTheme.bodySmall?.copyWith(
                                    height: 1.4,
                                    color: colors.onSurfaceVariant)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: close,
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(0, 52),
                      backgroundColor: colors.primary,
                      foregroundColor: colors.onPrimary,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                      textStyle: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w600),
                    ),
                    child: const Text('Continue'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
