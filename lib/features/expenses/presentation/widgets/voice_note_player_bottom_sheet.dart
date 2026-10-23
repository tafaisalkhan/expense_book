import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';
import 'package:myexpence/core/theme/app_theme.dart';
import 'package:myexpence/core/utils/currency_formatters.dart';
import 'package:myexpence/features/expenses/domain/models/expense.dart';
import 'package:myexpence/features/expenses/domain/services/voice_note_service.dart';

void showVoiceNoteBottomSheet(BuildContext context, WidgetRef ref, Expense expense) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) => VoiceNotePlayerBottomSheet(expense: expense),
  );
}

class VoiceNotePlayerBottomSheet extends ConsumerStatefulWidget {
  final Expense expense;

  const VoiceNotePlayerBottomSheet({super.key, required this.expense});

  @override
  ConsumerState<VoiceNotePlayerBottomSheet> createState() =>
      _VoiceNotePlayerBottomSheetState();
}

class _VoiceNotePlayerBottomSheetState
    extends ConsumerState<VoiceNotePlayerBottomSheet> {
  AudioPlayer? _player;
  bool _isLoading = true;
  String? _errorMessage;
  bool _isPlaying = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;

  StreamSubscription? _playerStateSub;
  StreamSubscription? _positionSub;
  StreamSubscription? _durationSub;

  @override
  void initState() {
    super.initState();
    _initAudio();
  }

  Future<void> _initAudio() async {
    try {
      final voiceService = ref.read(voiceNoteServiceProvider);
      // Ensures the audio file exists on the device, restoring from DB base64 if needed
      final devicePath = await voiceService.ensureLocalFileOnDevice(
        expenseUuid: widget.expense.uuid,
        localPath: widget.expense.voiceNotePath,
        base64Data: widget.expense.voiceNoteBase64,
      );

      if (devicePath == null) {
        if (mounted) {
          setState(() {
            _isLoading = false;
            _errorMessage = 'Voice recording not found on device or database.';
          });
        }
        return;
      }

      final player = AudioPlayer();
      _player = player;

      _playerStateSub = player.playerStateStream.listen((state) {
        if (!mounted) return;
        setState(() {
          _isPlaying = state.playing && state.processingState != ProcessingState.completed;
          if (state.processingState == ProcessingState.completed) {
            _position = Duration.zero;
          }
        });
      });

      _positionSub = player.positionStream.listen((pos) {
        if (!mounted) return;
        setState(() => _position = pos);
      });

      _durationSub = player.durationStream.listen((dur) {
        if (!mounted) return;
        if (dur != null && dur > Duration.zero) {
          setState(() => _duration = dur);
        }
      });

      await player.setFilePath(devicePath);

      if (mounted) {
        setState(() {
          _isLoading = false;
          if (widget.expense.voiceDurationSeconds != null &&
              widget.expense.voiceDurationSeconds! > 0) {
            _duration = Duration(seconds: widget.expense.voiceDurationSeconds!);
          }
        });
        // Auto-play when opened
        await player.play();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'Failed to load audio: $e';
        });
      }
    }
  }

  @override
  void dispose() {
    _playerStateSub?.cancel();
    _positionSub?.cancel();
    _durationSub?.cancel();
    _player?.dispose();
    super.dispose();
  }

  String _formatDuration(Duration d) {
    final m = d.inMinutes;
    final s = d.inSeconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final expense = widget.expense;
    final title = expense.merchant?.isNotEmpty == true
        ? expense.merchant!
        : (expense.description?.isNotEmpty == true
            ? expense.description!
            : 'Expense');

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: AppTheme.primaryColor.withValues(alpha: 0.12),
                  child: const Icon(Icons.mic, color: AppTheme.primaryColor),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        '${CurrencyFormatters.format(expense.amount)} • ${expense.expenseDate}',
                        style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const SizedBox(height: 20),

            if (_isLoading)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(24.0),
                  child: CircularProgressIndicator(),
                ),
              )
            else if (_errorMessage != null)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  _errorMessage!,
                  style: TextStyle(color: Colors.red.shade800),
                ),
              )
            else ...[
              SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackHeight: 4,
                  thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                  overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
                  activeTrackColor: AppTheme.primaryColor,
                  thumbColor: AppTheme.primaryColor,
                ),
                child: Slider(
                  min: 0,
                  max: _duration.inMilliseconds > 0
                      ? _duration.inMilliseconds.toDouble()
                      : 1.0,
                  value: _position.inMilliseconds
                      .clamp(0, _duration.inMilliseconds > 0 ? _duration.inMilliseconds : 1)
                      .toDouble(),
                  onChanged: (val) {
                    _player?.seek(Duration(milliseconds: val.toInt()));
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(_formatDuration(_position), style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                    Text(_formatDuration(_duration), style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Center(
                child: IconButton.filled(
                  iconSize: 32,
                  style: IconButton.styleFrom(
                    backgroundColor: AppTheme.primaryColor,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.all(14),
                  ),
                  icon: Icon(_isPlaying ? Icons.pause : Icons.play_arrow),
                  onPressed: () {
                    if (_isPlaying) {
                      _player?.pause();
                    } else {
                      _player?.play();
                    }
                  },
                ),
              ),
            ],
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}
