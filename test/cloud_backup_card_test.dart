import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myexpence/features/backup/backup_scheduler.dart';
import 'package:myexpence/features/backup/cloud_backup_card.dart';
import 'package:myexpence/features/backup/monthly_backup_billing.dart';

void main() {
  testWidgets(
      'preview can review the cloud section without enabling live transfers or purchases',
      (tester) async {
    await tester.pumpWidget(ProviderScope(
        overrides: [
          monthlyBackupBillingProvider
              .overrideWith((ref) => CloudBackupBilling(preview: true)),
        ],
        child: const MaterialApp(
            home: Scaffold(
                body: SingleChildScrollView(child: CloudBackupCard())))));
    await tester.pumpAndSettle();
    expect(find.text('Cloud backup & restore'), findsOneWidget);
    expect(find.text('Back up now'), findsNothing);
    await tester.tap(find.text('Unlock cloud backup'));
    await tester.pumpAndSettle();
    expect(find.text('Cloud Backup Plans'), findsOneWidget);
    final monthlyBtn = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Monthly · \$0.99 / month'));
    expect(monthlyBtn.onPressed, isNull);
    expect(find.textContaining('Purchases and cloud access are disabled'),
        findsOneWidget);
    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  test('delayUntilNextNoon targets today 12:00 PM before noon and tomorrow after noon',
      () {
    final beforeNoon = DateTime(2026, 11, 23, 10, 30);
    expect(
        BackupScheduler.delayUntilNextNoon(beforeNoon),
        const Duration(hours: 1, minutes: 30));

    final afterNoon = DateTime(2026, 11, 23, 14, 0);
    expect(
        BackupScheduler.delayUntilNextNoon(afterNoon),
        const Duration(hours: 22));
  });
}
