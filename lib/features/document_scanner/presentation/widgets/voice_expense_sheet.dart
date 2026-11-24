import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart' hide Category;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:myexpence/core/theme/app_theme.dart';
import 'package:myexpence/core/utils/currency_formatters.dart';
import 'package:myexpence/core/utils/date_formatters.dart';
import 'package:myexpence/features/backup/feature_quota_service.dart';
import 'package:myexpence/features/backup/monthly_backup_billing.dart';
import 'package:myexpence/features/categories/domain/models/category.dart';
import 'package:myexpence/features/categories/presentation/providers/category_providers.dart';
import 'package:myexpence/features/document_scanner/domain/services/ocr_scanner_service.dart';
import 'package:myexpence/features/document_scanner/domain/services/voice_expense_parser.dart';
import 'package:myexpence/features/expenses/domain/models/expense.dart';
import 'package:myexpence/features/expenses/presentation/providers/expense_providers.dart';
import 'package:uuid/uuid.dart';

Future<void> showVoiceExpenseSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (_) => const _VoiceExpenseSheet(),
  );
}

class _VoiceExpenseSheet extends ConsumerStatefulWidget {
  const _VoiceExpenseSheet();

  @override
  ConsumerState<_VoiceExpenseSheet> createState() => _VoiceExpenseSheetState();
}

class _VoiceExpenseSheetState extends ConsumerState<_VoiceExpenseSheet> {
  static const _voiceChannel = MethodChannel('com.myexpense.book/voice_expense');

  final _manualController = TextEditingController();
  bool _isListening = false;
  bool _isSaving = false;
  bool _showManualInput = false;
  int _secondsLeft = FeatureQuotaService.maxVoiceSeconds;
  int _remainingToday = 0;
  String _liveTranscript = '';
  String? _errorText;
  Timer? _countdownTimer;

  @override
  void initState() {
    super.initState();
    _voiceChannel.setMethodCallHandler(_handleNativeVoiceCallback);
    _refreshQuota();
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _voiceChannel.setMethodCallHandler(null);
    if (!kIsWeb && Platform.isAndroid) {
      unawaited(_voiceChannel
          .invokeMethod<void>('cancelListening')
          .catchError((_) {}));
    }
    _manualController.dispose();
    super.dispose();
  }

  Future<void> _refreshQuota() async {
    final isSubscribed = ref.read(monthlyBackupBillingProvider).active;
    final rem = await FeatureQuotaService.remainingVoiceToday(
      isSubscribed: isSubscribed,
    );
    if (mounted) setState(() => _remainingToday = rem);
  }

  Future<dynamic> _handleNativeVoiceCallback(MethodCall call) async {
    if (!mounted) return;
    switch (call.method) {
      case 'onPartialTranscript':
        setState(() {
          _liveTranscript = (call.arguments as String? ?? '').trim();
          _errorText = null;
        });
        break;
      case 'onFinalTranscript':
        _countdownTimer?.cancel();
        final text = (call.arguments as String? ?? '').trim();
        setState(() {
          _isListening = false;
          _liveTranscript = text;
        });
        if (text.isNotEmpty) {
          await _processAndAutoAddTranscript(text);
        } else {
          setState(() {
            _errorText =
                'Could not hear clearly. Tap the mic and speak e.g. "Milk 320 and Petrol 2000".';
          });
        }
        break;
      case 'onVoiceError':
        _countdownTimer?.cancel();
        final msg = (call.arguments as String? ?? '').trim();
        setState(() {
          _isListening = false;
          _errorText = msg.isNotEmpty
              ? msg
              : 'Voice recognition did not catch your words. Please try again.';
        });
        break;
    }
  }

  Future<void> _startVoiceCapture() async {
    if (_isListening || _isSaving) return;
    final isSubscribed = ref.read(monthlyBackupBillingProvider).active;
    final allowed = await FeatureQuotaService.canUseVoice(
      isSubscribed: isSubscribed,
    );
    if (!allowed) {
      if (mounted) _showQuotaLimitDialog(isSubscribed: isSubscribed);
      return;
    }

    if (kIsWeb || !Platform.isAndroid) {
      setState(() {
        _showManualInput = true;
        _errorText =
            'Live microphone speech-to-expense is available on Android. You can type a phrase below to test.';
      });
      return;
    }

    setState(() {
      _isListening = true;
      _secondsLeft = FeatureQuotaService.maxVoiceSeconds;
      _liveTranscript = '';
      _errorText = null;
    });

    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_secondsLeft <= 1) {
        timer.cancel();
        setState(() => _secondsLeft = 0);
        unawaited(_stopVoiceCapture());
      } else {
        setState(() => _secondsLeft--);
      }
    });

    try {
      await _voiceChannel.invokeMethod<void>('startListening', {
        'maxSeconds': FeatureQuotaService.maxVoiceSeconds,
      });
    } on PlatformException catch (e) {
      _countdownTimer?.cancel();
      if (mounted) {
        setState(() {
          _isListening = false;
          _errorText = e.message ??
              'Speech recognition unavailable. You can type your expense phrase below.';
          _showManualInput = true;
        });
      }
    }
  }

  Future<void> _stopVoiceCapture() async {
    _countdownTimer?.cancel();
    if (!kIsWeb && Platform.isAndroid) {
      try {
        await _voiceChannel.invokeMethod<void>('stopListening');
      } catch (_) {}
    }
  }

  Future<void> _processAndAutoAddTranscript(String transcript) async {
    if (_isSaving) return;
    final isSubscribed = ref.read(monthlyBackupBillingProvider).active;
    final allowed = await FeatureQuotaService.canUseVoice(
      isSubscribed: isSubscribed,
    );
    if (!allowed) {
      if (mounted) _showQuotaLimitDialog(isSubscribed: isSubscribed);
      return;
    }

    setState(() {
      _isSaving = true;
      _errorText = null;
    });

    try {
      final categories = await ref
          .read(categoriesListProvider.future)
          .catchError((_) => <Category>[]);

      final items = VoiceExpenseParser.parse(
        transcript,
        availableCategories: categories,
      );

      final now = DateTime.now();
      final nowStr = now.toIso8601String();
      final dateIso = DateFormatters.formatDateIso(now);
      final timeStr =
          '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
      final currency = CurrencyFormatters.defaultCurrency;
      final addedUuids = <String>[];

      for (final item in items) {
        final uuid = const Uuid().v4();
        final expense = Expense(
          uuid: uuid,
          amount: item.amount * item.quantity,
          currency: currency,
          categoryId: item.categoryId ?? 'cat_other',
          subcategoryId: item.subcategoryId,
          classification: item.classification,
          expenseDate: dateIso,
          expenseTime: timeStr,
          createdAt: nowStr,
          updatedAt: nowStr,
          merchant: item.name,
          paymentMethod: PaymentMethod.cash,
          notes: 'Voice Expense: "$transcript"',
        );
        await ref.read(expenseNotifierProvider.notifier).addExpense(expense);
        addedUuids.add(uuid);
      }

      await FeatureQuotaService.recordVoiceUsage();
      await _refreshQuota();

      if (mounted) {
        setState(() => _isSaving = false);
        await _showSuccessDialog(
          items: items,
          addedUuids: addedUuids,
          transcript: transcript,
        );
      }
    } on UnreadableVoiceException catch (e) {
      if (mounted) {
        setState(() {
          _isSaving = false;
          _errorText = e.message;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isSaving = false;
          _errorText = 'Could not save voice expense: $e';
        });
      }
    }
  }

  Future<void> _showSuccessDialog({
    required List<OcrLineItem> items,
    required List<String> addedUuids,
    required String transcript,
  }) async {
    final curr = CurrencyFormatters.defaultCurrency;
    final total =
        items.fold(0.0, (s, item) => s + (item.amount * item.quantity));
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.check_circle, color: Colors.green, size: 26),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                'Voice Expense Added',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Heard: "$transcript"',
                style: TextStyle(
                  fontSize: 12,
                  fontStyle: FontStyle.italic,
                  color: Colors.grey[700],
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'Added ${items.length} item(s) · Total $curr ${total.toStringAsFixed(2)}:',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              ...items.map((item) {
                final catLabel = item.subcategoryName != null
                    ? '${item.categoryName ?? item.categoryId} › ${item.subcategoryName}'
                    : (item.categoryName ?? item.categoryId ?? 'Other');
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(item.name,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w600, fontSize: 13)),
                            Text(catLabel,
                                style: TextStyle(
                                    fontSize: 11, color: Colors.grey[700])),
                          ],
                        ),
                      ),
                      Text(
                        '$curr ${(item.amount * item.quantity).toStringAsFixed(2)}',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.teal,
                        ),
                      ),
                    ],
                  ),
                );
              }),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              for (final id in addedUuids) {
                await ref
                    .read(expenseNotifierProvider.notifier)
                    .deleteExpense(id);
              }
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Voice expense undone.')),
                );
              }
            },
            child: const Text('Undo'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              if (mounted) Navigator.pop(context);
            },
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }

  Future<void> _showQuotaLimitDialog({required bool isSubscribed}) async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Icon(
              isSubscribed ? Icons.schedule : Icons.workspace_premium,
              color: isSubscribed ? Colors.orange : AppTheme.primaryColor,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                isSubscribed
                    ? 'Daily Voice Limit Reached'
                    : 'Upgrade to Unlock More Voice',
                style:
                    const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        content: Text(
          isSubscribed
              ? 'You have used all ${FeatureQuotaService.subscribedMaxVoicePerDay} voice entries (10s each) for today. Your daily limit resets tomorrow.'
              : 'Free accounts include 1 OCR receipt image and 1 voice entry (10s) per day.\n\nStart your 7-Day Free Trial (\$0.99/month or \$5.99/year after trial) to unlock:\n• 10 voice entries/day (10s each)\n• Unlimited OCR receipt scans\n• Daily 12:00 PM cloud backup\n• 100% Ad-Free experience',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
          if (!isSubscribed)
            FilledButton(
              onPressed: () {
                Navigator.pop(ctx);
                Navigator.pop(context);
                context.go('/more');
              },
              child: const Text('View Plans'),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isSubscribed =
        ref.watch(monthlyBackupBillingProvider.select((s) => s.active));
    final dailyLimit = isSubscribed
        ? FeatureQuotaService.subscribedMaxVoicePerDay
        : FeatureQuotaService.freeMaxVoicePerDay;

    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey[400],
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              const Icon(Icons.mic_rounded, color: AppTheme.primaryColor),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Voice to Expense (On-Device)',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                ),
              ),
              Chip(
                visualDensity: VisualDensity.compact,
                backgroundColor: isSubscribed
                    ? Colors.teal.withValues(alpha: 0.14)
                    : Colors.amber.withValues(alpha: 0.2),
                label: Text(
                  isSubscribed
                      ? 'Sub: $_remainingToday/$dailyLimit left · 10s'
                      : 'Free: $_remainingToday/$dailyLimit left · 10s',
                  style: const TextStyle(
                      fontSize: 11, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Speak up to 10 seconds, e.g. "Milk 320, Panadol 180, Petrol 3500". No AI API required — automatically adds each item to its category.',
            style: TextStyle(fontSize: 12, color: Colors.grey[700]),
          ),
          const SizedBox(height: 18),
          GestureDetector(
            onTap: _isListening ? _stopVoiceCapture : _startVoiceCapture,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 84,
              height: 84,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _isListening ? Colors.red : AppTheme.primaryColor,
                boxShadow: [
                  BoxShadow(
                    color: (_isListening ? Colors.red : AppTheme.primaryColor)
                        .withValues(alpha: 0.35),
                    blurRadius: _isListening ? 20 : 10,
                    spreadRadius: _isListening ? 4 : 1,
                  ),
                ],
              ),
              child: Icon(
                _isListening ? Icons.stop_rounded : Icons.mic_rounded,
                color: Colors.white,
                size: 40,
              ),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            _isListening
                ? 'Listening... 00:${_secondsLeft.toString().padLeft(2, '0')} left (Tap to finish)'
                : _isSaving
                    ? 'Adding to related expenses...'
                    : 'Tap mic to speak (10s max)',
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: _isListening ? Colors.red : AppTheme.primaryColor,
            ),
          ),
          if (_liveTranscript.isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.teal.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                '"$_liveTranscript"',
                style:
                    const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
              ),
            ),
          ],
          if (_errorText != null) ...[
            const SizedBox(height: 10),
            Text(
              _errorText!,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.red, fontSize: 12),
            ),
          ],
          if (_isSaving)
            const Padding(
              padding: EdgeInsets.only(top: 12),
              child: LinearProgressIndicator(),
            ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: () =>
                setState(() => _showManualInput = !_showManualInput),
            child: Text(
              _showManualInput
                  ? 'Hide text input'
                  : 'Or type spoken expense phrase',
              style: const TextStyle(fontSize: 12),
            ),
          ),
          if (_showManualInput) ...[
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _manualController,
                    decoration: const InputDecoration(
                      hintText: 'e.g. Milk 320 and Petrol 2000',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: _isSaving
                      ? null
                      : () {
                          final text = _manualController.text.trim();
                          if (text.isNotEmpty) {
                            _processAndAutoAddTranscript(text);
                          }
                        },
                  child: const Text('Add'),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
