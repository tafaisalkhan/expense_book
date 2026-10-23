import 'dart:convert';
import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

final voiceNoteServiceProvider = Provider<VoiceNoteService>((ref) {
  return VoiceNoteService();
});

class VoiceNoteService {
  final Future<Directory> Function()? customDirectoryProvider;

  VoiceNoteService({this.customDirectoryProvider});

  /// Returns the local device directory where expense voice notes are stored
  Future<Directory> getVoiceDirectory() async {
    if (customDirectoryProvider != null) {
      final dir = await customDirectoryProvider!();
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      return dir;
    }
    final appDir = await getApplicationDocumentsDirectory();
    final voiceDir = Directory('${appDir.path}/voice_notes');
    if (!await voiceDir.exists()) {
      await voiceDir.create(recursive: true);
    }
    return voiceDir;
  }

  /// Processes a newly recorded audio file:
  /// - Copies it to permanent local app storage
  /// - Reads its bytes and converts to base64 for database backup/restore preservation
  Future<({String localPath, String base64Data})> processRecordedAudio({
    required String sourcePath,
    required String expenseUuid,
  }) async {
    final voiceDir = await getVoiceDirectory();
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final extension = sourcePath.contains('.')
        ? sourcePath.substring(sourcePath.lastIndexOf('.'))
        : '.m4a';
    final permanentFile = File('${voiceDir.path}/expense_${expenseUuid}_$timestamp$extension');

    final sourceFile = File(sourcePath);
    if (await sourceFile.exists()) {
      final bytes = await sourceFile.readAsBytes();
      await permanentFile.writeAsBytes(bytes, flush: true);
      final base64String = base64Encode(bytes);

      // Clean up temp recording file if different
      if (sourceFile.path != permanentFile.path) {
        try {
          await sourceFile.delete();
        } catch (_) {}
      }

      return (
        localPath: permanentFile.path,
        base64Data: base64String,
      );
    } else {
      throw Exception('Source recording file not found at: $sourcePath');
    }
  }

  /// Ensures that the voice note file exists on the local device filesystem:
  /// 1. If [localPath] exists on this device, it returns [localPath].
  /// 2. If [localPath] is missing or invalid (e.g. after database restore on a new device or cleared cache),
  ///    it creates the audio file on the device filesystem from [base64Data] stored in the DB,
  ///    and returns the local file path so audio always plays from device storage.
  Future<String?> ensureLocalFileOnDevice({
    required String expenseUuid,
    String? localPath,
    String? base64Data,
  }) async {
    // 1. Check if local device file already exists
    if (localPath != null && localPath.isNotEmpty) {
      final file = File(localPath);
      if (await file.exists()) {
        return localPath;
      }
    }

    // 2. If not on device, restore from database base64 data
    if (base64Data != null && base64Data.isNotEmpty) {
      try {
        final voiceDir = await getVoiceDirectory();
        final restoredFile = File('${voiceDir.path}/expense_${expenseUuid}.m4a');
        final bytes = base64Decode(base64Data);
        await restoredFile.writeAsBytes(bytes, flush: true);
        return restoredFile.path;
      } catch (e) {
        return null;
      }
    }

    return null;
  }

  /// Safely deletes the local audio file from device storage
  Future<void> deleteLocalVoiceFile(String? localPath) async {
    if (localPath == null || localPath.isEmpty) return;
    try {
      final file = File(localPath);
      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {}
  }
}
