import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:myexpence/features/expenses/domain/models/expense.dart';
import 'package:myexpence/features/expenses/domain/models/expense_classification.dart';
import 'package:myexpence/features/expenses/domain/services/voice_note_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Expense Model Voice Note Tests', () {
    test('Expense preserves voice note fields in toMap and fromMap', () {
      final sampleBase64 = base64Encode(utf8.encode('dummy-audio-bytes-for-test'));
      const samplePath = '/mock/path/to/voice.m4a';
      const sampleDuration = 12;

      final expense = Expense(
        uuid: 'test-voice-uuid-1',
        amount: 250.0,
        categoryId: 'food',
        classification: ExpenseClassification.required,
        expenseDate: '2026-10-16',
        createdAt: '2026-10-16T10:00:00Z',
        updatedAt: '2026-10-16T10:00:00Z',
        voiceNotePath: samplePath,
        voiceNoteBase64: sampleBase64,
        voiceDurationSeconds: sampleDuration,
      );

      expect(expense.hasVoiceNote, isTrue);
      expect(expense.voiceNotePath, equals(samplePath));
      expect(expense.voiceNoteBase64, equals(sampleBase64));
      expect(expense.voiceDurationSeconds, equals(sampleDuration));

      final map = expense.toMap();
      expect(map['voiceNotePath'], equals(samplePath));
      expect(map['voiceNoteBase64'], equals(sampleBase64));
      expect(map['voiceDurationSeconds'], equals(sampleDuration));

      final restored = Expense.fromMap(map);
      expect(restored.uuid, equals(expense.uuid));
      expect(restored.voiceNotePath, equals(samplePath));
      expect(restored.voiceNoteBase64, equals(sampleBase64));
      expect(restored.voiceDurationSeconds, equals(sampleDuration));
      expect(restored.hasVoiceNote, isTrue);
    });

    test('Expense without voice note returns hasVoiceNote as false', () {
      final expense = Expense(
        uuid: 'test-no-voice-uuid',
        amount: 50.0,
        categoryId: 'transport',
        classification: ExpenseClassification.required,
        expenseDate: '2026-10-16',
        createdAt: '2026-10-16T10:00:00Z',
        updatedAt: '2026-10-16T10:00:00Z',
      );

      expect(expense.hasVoiceNote, isFalse);
      expect(expense.voiceNotePath, isNull);
      expect(expense.voiceNoteBase64, isNull);
    });
  });

  group('VoiceNoteService On-Device Recovery Tests', () {
    late Directory tempDir;
    late VoiceNoteService service;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('voice_test_');
      service = VoiceNoteService(customDirectoryProvider: () async => tempDir);
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('ensureLocalFileOnDevice returns existing local file directly', () async {
      final existingFile = File('${tempDir.path}/existing_voice.m4a');
      await existingFile.writeAsString('audio-content');

      final result = await service.ensureLocalFileOnDevice(
        expenseUuid: 'uuid-123',
        localPath: existingFile.path,
        base64Data: null,
      );

      expect(result, equals(existingFile.path));
    });

    test('ensureLocalFileOnDevice recreates file on device from DB base64 when local file is missing', () async {
      final originalData = 'audio-restored-from-db-bytes';
      final base64String = base64Encode(utf8.encode(originalData));
      const missingPath = '/non/existent/device/path/voice.m4a';

      // When the local path does not exist (like after DB restore on new phone),
      // ensureLocalFileOnDevice must write bytes to device and return the new path
      final resultPath = await service.ensureLocalFileOnDevice(
        expenseUuid: 'uuid-restore-test',
        localPath: missingPath,
        base64Data: base64String,
      );

      expect(resultPath, isNotNull);
      final restoredFile = File(resultPath!);
      expect(await restoredFile.exists(), isTrue);

      final readData = utf8.decode(await restoredFile.readAsBytes());
      expect(readData, equals(originalData));

      // Cleanup
      await service.deleteLocalVoiceFile(resultPath);
      expect(await restoredFile.exists(), isFalse);
    });
  });
}
