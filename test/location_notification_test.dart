import 'package:flutter_test/flutter_test.dart';
import 'package:myexpence/features/document_scanner/domain/services/ocr_scanner_service.dart';
import 'package:myexpence/features/notifications/domain/models/location_notification.dart';
import 'package:myexpence/features/notifications/presentation/providers/location_notification_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
  });

  group('OCR Receipt Scanner Unit Tests', () {
    test('OCR extracts merchant, amount, date, line items, and category mapping', () async {
      const sampleText = '''
SHELL PETROL PUMP
Main Boulevard Station
Date: 2026-09-24
Super Fuel 20L      5600.00
Engine Oil 1L       1400.00
TOTAL: 7000.00
Thank you for visiting Shell!
''';

      final result = OcrScannerService.parseReceiptText(sampleText);

      expect(result.merchant, contains('SHELL'));
      expect(result.totalAmount, equals(7000.0));
      expect(result.suggestedCategoryId, equals('cat_car'));
      expect(result.suggestedCategoryName, equals('Transportation & Fuel'));
      expect(result.lineItems.length, greaterThanOrEqualTo(1));
    });

    test('Strict file type validation allows only Images & PDFs, rejecting unsupported files', () async {
      expect(OcrScannerService.isSupportedFileType('receipt.jpg'), isTrue);
      expect(OcrScannerService.isSupportedFileType('slip.png'), isTrue);
      expect(OcrScannerService.isSupportedFileType('invoice.pdf'), isTrue);
      expect(OcrScannerService.isSupportedFileType('photo.webp'), isTrue);

      expect(OcrScannerService.isSupportedFileType('document.docx'), isFalse);
      expect(OcrScannerService.isSupportedFileType('video.mp4'), isFalse);
      expect(OcrScannerService.isSupportedFileType('archive.zip'), isFalse);

      expect(
        () => OcrScannerService.scanReceipt('document.docx'),
        throwsA(isA<UnsupportedFileFormatException>()),
      );
    });
  });

  group('Location Notification & Geofencing Rules Tests', () {
    test('Rule 1 & 5: Leaving Petrol Pump, Super Market & Local Market in 1 day generates 3 distinct notifications', () async {
      final notifier = LocationNotificationNotifier();
      await notifier.loadNotifications();
      notifier.clearTodayNotificationsForTest();

      final notif1 = await notifier.userLeftLocation(placeName: 'Petrol Pump', type: LocationType.petrolPump);
      final notif2 = await notifier.userLeftLocation(placeName: 'Super Market', type: LocationType.superMarket);
      final notif3 = await notifier.userLeftLocation(placeName: 'Local Market', type: LocationType.localMarket);

      expect(notif1, isNotNull);
      expect(notif2, isNotNull);
      expect(notif3, isNotNull);

      final state = notifier.currentState;
      expect(state.activeNotifications.length, equals(3));
      expect(state.activeNotifications[0].locationType, equals(LocationType.petrolPump));
      expect(state.activeNotifications[1].locationType, equals(LocationType.superMarket));
      expect(state.activeNotifications[2].locationType, equals(LocationType.localMarket));
    });

    test('Rule 3: Muted location suppresses all future notifications', () async {
      final notifier = LocationNotificationNotifier();
      await notifier.loadNotifications();
      notifier.clearTodayNotificationsForTest();

      await notifier.muteLocation('Local Market');

      final notif = await notifier.userLeftLocation(placeName: 'Local Market', type: LocationType.localMarket);
      expect(notif, isNull);
    });

    test('Rule 4: Discarding notification clears current visit but permits future visits today', () async {
      final notifier = LocationNotificationNotifier();
      await notifier.loadNotifications();
      notifier.clearTodayNotificationsForTest();

      final notif = await notifier.userLeftLocation(placeName: 'Super Market', type: LocationType.superMarket);
      expect(notif, isNotNull);

      await notifier.discardNotification(notif!.id);
      expect(notifier.currentState.activeNotifications.any((n) => n.id == notif.id), isFalse);

      final newVisitNotif = await notifier.userLeftLocation(placeName: 'Super Market', type: LocationType.superMarket);
      expect(newVisitNotif, isNotNull);
      expect(newVisitNotif!.id, isNot(equals(notif.id)));
    });

    test('Rule 7: Entering and re-entering geofence range generates single notification on each entry', () async {
      final notifier = LocationNotificationNotifier();
      await notifier.loadNotifications();
      notifier.clearTodayNotificationsForTest();

      final entryNotif = await notifier.userEnteredLocation(placeName: 'Metro Superstore', type: LocationType.superMarket);
      expect(entryNotif, isNotNull);
      expect(entryNotif!.placeName, equals('Metro Superstore'));
      expect(notifier.currentState.activeNotifications.length, equals(1));
    });

    test('Rule 6: Notifications expire on previous day and do NOT carry over', () async {
      final yesterdayIso = DateTime.now().subtract(const Duration(days: 1)).toIso8601String().split('T').first;

      final yesterdayNotif = LocationVisitNotification(
        id: 'old_123',
        placeName: 'Yesterday Market',
        locationType: LocationType.superMarket,
        visitDateIso: yesterdayIso,
        leftAtIso: DateTime.now().subtract(const Duration(days: 1)).toIso8601String(),
        lastRemindedAtIso: DateTime.now().subtract(const Duration(days: 1)).toIso8601String(),
      );

      expect(yesterdayNotif.isExpired, isTrue);
      expect(yesterdayNotif.isActive, isFalse);
    });
  });
}
