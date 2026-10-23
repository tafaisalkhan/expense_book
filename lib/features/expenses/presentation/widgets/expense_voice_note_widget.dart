import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:myexpence/core/theme/app_theme.dart';
import 'package:myexpence/features/expenses/domain/services/voice_note_service.dart';

class ExpenseVoiceNoteWidget extends ConsumerStatefulWidget {
  final String expenseUuid;
  final String? initialVoiceNotePath;
  final String? initialVoiceNoteBase64;
  final int? initialDurationSeconds;
  final void Function({
    required String? localPath,
    required String? base64Data,
    required int? durationSeconds,
  }) onVoiceNoteChanged;

  const ExpenseVoiceNoteWidget({
    super.key,
    required this.expenseUuid,
    this.initialVoiceNotePath,
    this.initialVoiceNoteBase64,
    this.initialDurationSeconds,
    required this.onVoiceNoteChanged,
  });

  @override
  ConsumerState<ExpenseVoiceNoteWidget> createState() => _ExpenseVoiceNoteWidgetState();
}

class _ExpenseVoiceNoteWidgetState extends ConsumerState<ExpenseVoiceNoteWidget> {
  late final AudioRecorder _audioRecorder;
  AudioPlayer? _audioPlayer;

  bool _isRecording = false;
  int _recordSeconds = 0;
  Timer? _recordTimer;

  String? _currentLocalPath;
  String? _currentBase64;
  int? _durationSeconds;

  bool _isPlaying = false;
  Duration _currentPosition = Duration.zero;
  Duration _totalDuration = Duration.zero;
  StreamSubscription? _playerStateSub;
  StreamSubscription? _positionSub;
  StreamSubscription? _durationSub;

  bool _isPreparingAudio = false;

  @override
  void initState() {
    super.initState();
    _audioRecorder = AudioRecorder();
    _currentLocalPath = widget.initialVoiceNotePath;
    _currentBase64 = widget.initialVoiceNoteBase64;
    _durationSeconds = widget.initialDurationSeconds;
    if (_durationSeconds != null && _durationSeconds! > 0) {
      _totalDuration = Duration(seconds: _durationSeconds!);
    }
  }

  @override
  void didUpdateWidget(covariant ExpenseVoiceNoteWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialVoiceNotePath != oldWidget.initialVoiceNotePath ||
        widget.initialVoiceNoteBase64 != oldWidget.initialVoiceNoteBase64) {
      _currentLocalPath = widget.initialVoiceNotePath;
      _currentBase64 = widget.initialVoiceNoteBase64;
      _durationSeconds = widget.initialDurationSeconds;
      if (_durationSeconds != null && _durationSeconds! > 0) {
        _totalDuration = Duration(seconds: _durationSeconds!);
      }
    }
  }

  @override
  void dispose() {
    _recordTimer?.cancel();
    _audioRecorder.dispose();
    _playerStateSub?.cancel();
    _positionSub?.cancel();
    _durationSub?.cancel();
    _audioPlayer?.dispose();
    super.dispose();
  }

  bool get _hasVoiceNote =>
      (_currentLocalPath != null && _currentLocalPath!.isNotEmpty) ||
      (_currentBase64 != null && _currentBase64!.isNotEmpty);

  Future<void> _startRecording() async {
    try {
      if (!await _audioRecorder.hasPermission()) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Microphone permission is required to record voice notes.')),
          );
        }
        return;
      }

      // Stop any active playback
      await _stopPlayback();

      final tempDir = await getTemporaryDirectory();
      final tempPath = '${tempDir.path}/temp_rec_${DateTime.now().millisecondsSinceEpoch}.m4a';

      await _audioRecorder.start(
        const RecordConfig(
          encoder: AudioEncoder.aacLc,
          bitRate: 64000,
          sampleRate: 44100,
        ),
        path: tempPath,
      );

      setState(() {
        _isRecording = true;
        _recordSeconds = 0;
      });

      _recordTimer?.cancel();
      _recordTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (!mounted) {
          timer.cancel();
          return;
        }
        setState(() {
          _recordSeconds++;
        });
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error starting recording: $e')),
        );
      }
    }
  }

  Future<void> _stopRecording() async {
    _recordTimer?.cancel();
    try {
      final recordedPath = await _audioRecorder.stop();
      setState(() {
        _isRecording = false;
      });

      if (recordedPath == null || recordedPath.isEmpty) return;

      final recordedDuration = _recordSeconds;

      // Process and save both to device file and base64 for DB
      final voiceService = ref.read(voiceNoteServiceProvider);
      final result = await voiceService.processRecordedAudio(
        sourcePath: recordedPath,
        expenseUuid: widget.expenseUuid,
      );

      setState(() {
        _currentLocalPath = result.localPath;
        _currentBase64 = result.base64Data;
        _durationSeconds = recordedDuration > 0 ? recordedDuration : 1;
        _totalDuration = Duration(seconds: _durationSeconds!);
        _currentPosition = Duration.zero;
      });

      widget.onVoiceNoteChanged(
        localPath: _currentLocalPath,
        base64Data: _currentBase64,
        durationSeconds: _durationSeconds,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error saving recording: $e')),
        );
      }
    }
  }

  Future<void> _cancelRecording() async {
    _recordTimer?.cancel();
    try {
      await _audioRecorder.stop();
    } catch (_) {}
    setState(() {
      _isRecording = false;
      _recordSeconds = 0;
    });
  }

  Future<void> _initAudioPlayer(String filePath) async {
    if (_audioPlayer != null) {
      await _audioPlayer!.dispose();
      _audioPlayer = null;
    }

    final player = AudioPlayer();
    _audioPlayer = player;

    _playerStateSub = player.playerStateStream.listen((state) {
      if (!mounted) return;
      setState(() {
        _isPlaying = state.playing && state.processingState != ProcessingState.completed;
        if (state.processingState == ProcessingState.completed) {
          _currentPosition = Duration.zero;
        }
      });
    });

    _positionSub = player.positionStream.listen((pos) {
      if (!mounted) return;
      setState(() {
        _currentPosition = pos;
      });
    });

    _durationSub = player.durationStream.listen((dur) {
      if (!mounted) return;
      if (dur != null && dur > Duration.zero) {
        setState(() {
          _totalDuration = dur;
          _durationSeconds = dur.inSeconds;
        });
      }
    });

    await player.setFilePath(filePath);
  }

  Future<void> _playVoiceNote() async {
    if (_isPreparingAudio) return;

    if (_audioPlayer != null && _audioPlayer!.processingState == ProcessingState.ready) {
      await _audioPlayer!.play();
      return;
    }

    setState(() => _isPreparingAudio = true);

    try {
      final voiceService = ref.read(voiceNoteServiceProvider);
      // Ensures the audio file exists on the local device, recreating it from DB base64 if needed
      final validDevicePath = await voiceService.ensureLocalFileOnDevice(
        expenseUuid: widget.expenseUuid,
        localPath: _currentLocalPath,
        base64Data: _currentBase64,
      );

      if (validDevicePath == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Voice note audio could not be found.')),
          );
        }
        return;
      }

      if (_currentLocalPath != validDevicePath) {
        _currentLocalPath = validDevicePath;
        widget.onVoiceNoteChanged(
          localPath: _currentLocalPath,
          base64Data: _currentBase64,
          durationSeconds: _durationSeconds,
        );
      }

      await _initAudioPlayer(validDevicePath);
      await _audioPlayer?.play();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error playing audio: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isPreparingAudio = false);
      }
    }
  }

  Future<void> _pauseVoiceNote() async {
    await _audioPlayer?.pause();
  }

  Future<void> _stopPlayback() async {
    await _audioPlayer?.stop();
    setState(() {
      _isPlaying = false;
      _currentPosition = Duration.zero;
    });
  }

  Future<void> _deleteVoiceNote() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Voice Note?'),
        content: const Text('Are you sure you want to remove this voice recording from the expense?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await _stopPlayback();
      final voiceService = ref.read(voiceNoteServiceProvider);
      await voiceService.deleteLocalVoiceFile(_currentLocalPath);

      setState(() {
        _currentLocalPath = null;
        _currentBase64 = null;
        _durationSeconds = null;
        _totalDuration = Duration.zero;
        _currentPosition = Duration.zero;
      });

      widget.onVoiceNoteChanged(
        localPath: null,
        base64Data: null,
        durationSeconds: null,
      );
    }
  }

  String _formatTimer(int seconds) {
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  String _formatDuration(Duration d) {
    final m = d.inMinutes;
    final s = d.inSeconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // 1. Currently Recording View
    if (_isRecording) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: Colors.red.shade50,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.red.shade300, width: 1.5),
        ),
        child: Row(
          children: [
            Container(
              width: 14,
              height: 14,
              decoration: const BoxDecoration(
                color: Colors.red,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 12),
            Text(
              'Recording: ${_formatTimer(_recordSeconds)}',
              style: TextStyle(
                color: Colors.red.shade900,
                fontWeight: FontWeight.bold,
                fontSize: 15,
              ),
            ),
            const Spacer(),
            IconButton(
              icon: const Icon(Icons.close, color: Colors.grey),
              tooltip: 'Cancel',
              onPressed: _cancelRecording,
            ),
            const SizedBox(width: 4),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              ),
              icon: const Icon(Icons.stop, size: 18),
              label: const Text('Done'),
              onPressed: _stopRecording,
            ),
          ],
        ),
      );
    }

    // 2. Has Recorded Voice Note View
    if (_hasVoiceNote) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppTheme.primaryColor.withValues(alpha: 0.3)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.mic, color: AppTheme.primaryColor, size: 20),
                const SizedBox(width: 6),
                const Text(
                  'Expense Voice Note',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.refresh, size: 18, color: Colors.blueGrey),
                  tooltip: 'Re-record',
                  onPressed: () async {
                    await _stopPlayback();
                    _startRecording();
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline, size: 18, color: Colors.redAccent),
                  tooltip: 'Delete Voice Note',
                  onPressed: _deleteVoiceNote,
                ),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                IconButton.filled(
                  iconSize: 22,
                  style: IconButton.styleFrom(
                    backgroundColor: AppTheme.primaryColor,
                    foregroundColor: Colors.white,
                  ),
                  icon: _isPreparingAudio
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : Icon(_isPlaying ? Icons.pause : Icons.play_arrow),
                  onPressed: _isPreparingAudio
                      ? null
                      : (_isPlaying ? _pauseVoiceNote : _playVoiceNote),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    children: [
                      SliderTheme(
                        data: SliderTheme.of(context).copyWith(
                          trackHeight: 3.5,
                          thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                          overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
                          activeTrackColor: AppTheme.primaryColor,
                          inactiveTrackColor: Colors.grey.shade300,
                          thumbColor: AppTheme.primaryColor,
                        ),
                        child: Slider(
                          min: 0,
                          max: _totalDuration.inMilliseconds > 0
                              ? _totalDuration.inMilliseconds.toDouble()
                              : 1.0,
                          value: _currentPosition.inMilliseconds
                              .clamp(0, _totalDuration.inMilliseconds > 0 ? _totalDuration.inMilliseconds : 1)
                              .toDouble(),
                          onChanged: (val) {
                            if (_audioPlayer != null) {
                              _audioPlayer!.seek(Duration(milliseconds: val.toInt()));
                            }
                          },
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8.0),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              _formatDuration(_currentPosition),
                              style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                            ),
                            Text(
                              _formatDuration(_totalDuration),
                              style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      );
    }

    // 3. No Voice Note Recorded - Empty State Button
    return OutlinedButton.icon(
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        side: BorderSide(color: AppTheme.primaryColor.withValues(alpha: 0.6)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      icon: const Icon(Icons.mic, color: AppTheme.primaryColor),
      label: const Text(
        'Add Voice Note (Tap to record)',
        style: TextStyle(color: AppTheme.primaryColor, fontWeight: FontWeight.w600),
      ),
      onPressed: _startRecording,
    );
  }
}
