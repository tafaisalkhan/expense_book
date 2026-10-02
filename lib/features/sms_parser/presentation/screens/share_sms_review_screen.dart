import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:myexpence/core/theme/app_theme.dart';
import 'package:myexpence/core/utils/date_formatters.dart';
import 'package:myexpence/features/categories/domain/models/category.dart';
import 'package:myexpence/features/categories/presentation/providers/category_providers.dart';
import 'package:myexpence/features/expenses/domain/models/expense.dart';
import 'package:myexpence/features/expenses/domain/models/expense_classification.dart';
import 'package:myexpence/features/expenses/domain/models/payment_method.dart';
import 'package:myexpence/features/expenses/presentation/providers/expense_providers.dart';
import 'package:myexpence/features/people/domain/models/person.dart';
import 'package:myexpence/features/people/presentation/providers/people_providers.dart';
import 'package:myexpence/features/sms_parser/domain/services/sms_parser_service.dart';
import 'package:myexpence/features/sms_parser/presentation/providers/sms_whitelist_provider.dart';
import 'package:myexpence/features/sms_parser/domain/services/sms_listener_service.dart';
import 'package:uuid/uuid.dart';

class ShareSmsReviewScreen extends ConsumerStatefulWidget {
  final String? initialSmsText;

  const ShareSmsReviewScreen({super.key, this.initialSmsText});

  @override
  ConsumerState<ShareSmsReviewScreen> createState() => _ShareSmsReviewScreenState();
}

class _ShareSmsReviewScreenState extends ConsumerState<ShareSmsReviewScreen> {
  final _formKey = GlobalKey<FormState>();
  final _smsTextController = TextEditingController();
  final _senderController = TextEditingController();
  final _amountController = TextEditingController();
  final _merchantController = TextEditingController();
  final _notesController = TextEditingController();
  final _newWhitelistedNumberController = TextEditingController();

  DateTime _selectedDate = DateTime.now();
  Category? _selectedCategory;
  Subcategory? _selectedSubcategory;
  Person? _selectedPerson;
  ExpenseClassification _classification = ExpenseClassification.required;
  final PaymentMethod _paymentMethod = PaymentMethod.bankTransfer;

  bool _isParsed = false;
  String? _parseMessage;
  String? _senderValidationMsg;
  bool _isWhitelistedSender = false;
  bool _hasSmsPermission = false;

  static const List<Map<String, String>> _sampleSmsTemplates = [
    {
      'label': '⛽ Fuel / Shell',
      'sender': 'MeezanBank',
      'text': 'Your A/C 4589 debited by Rs 3,500.00 at POS SHELL PETROL PUMP on 24-SEP-26. Avail Bal: Rs 14,200.',
    },
    {
      'label': '🛒 Grocery / Metro',
      'sender': 'HBL',
      'text': 'Transaction of Rs 4,890.50 at METRO GROCERY SUPERMARKET on 24/09/2026. Ref: 887711',
    },
    {
      'label': '🍔 Food / KFC',
      'sender': 'Easypaisa',
      'text': 'Paid Rs 1,850.00 to KFC RESTAURANT via Bank Transfer on 24-09-2026. Avail Bal: Rs 12,350.',
    },
    {
      'label': '⚡ Utility Bill',
      'sender': '8257',
      'text': 'Paid Rs 6,400.00 for K-ELECTRIC UTILITY BILL payment on 24-SEP-26.',
    },
  ];

  @override
  void initState() {
    super.initState();
    final defaultSms = widget.initialSmsText ?? _sampleSmsTemplates.first['text']!;
    final defaultSender = _sampleSmsTemplates.first['sender']!;
    _smsTextController.text = defaultSms;
    _senderController.text = defaultSender;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _runParseSms(defaultSms, sender: defaultSender);
      _checkPermissionsAndStartListener();
    });
  }

  Future<void> _checkPermissionsAndStartListener() async {
    final granted = await SmsListenerService.checkPermission();
    setState(() => _hasSmsPermission = granted);
    if (granted) {
      _startSmsListener();
    }
  }

  void _startSmsListener() {
    final smsListener = ref.read(smsListenerServiceProvider);
    smsListener.startListening(
      ref,
      onWhitelistedSmsReceived: (parsed) {
        if (!mounted) return;
        setState(() {
          _smsTextController.text = parsed.rawSms;
          _senderController.text = parsed.sender ?? '';
          _runParseSms(parsed.rawSms, sender: parsed.sender);
        });
      },
    );
  }

  Future<void> _requestSmsPermission() async {
    final ok = await SmsListenerService.requestPermission();
    setState(() => _hasSmsPermission = ok);
    if (ok) {
      _startSmsListener();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('🟢 SMS Permission Granted! App is listening for whitelisted bank SMS.'), backgroundColor: Colors.teal),
        );
      }
    }
  }

  void _runParseSms(String text, {String? sender}) {
    if (text.trim().isEmpty) return;

    final userWhitelist = ref.read(smsWhitelistProvider);
    final currentSender = sender ?? _senderController.text.trim();
    final result = SmsParserService.parseSmsText(
      text,
      sender: currentSender.isNotEmpty ? currentSender : null,
      customAllowedSenders: userWhitelist,
    );

    setState(() {
      if (result.sender != null && result.sender!.isNotEmpty) {
        _senderController.text = result.sender!;
      }
      _senderValidationMsg = result.senderValidationMessage;
      _isWhitelistedSender = result.isKnownSender;

      _amountController.text = result.amount > 0 ? result.amount.toStringAsFixed(2) : '';
      _merchantController.text = result.merchant ?? '';
      _selectedDate = result.detectedDate;
      _classification = result.classification;
      _notesController.text = 'Parsed SMS (${result.sender ?? "Unknown Sender"}): "${result.rawSms}"';
      _isParsed = true;
      _parseMessage = 'Parsed SMS: Rs ${result.amount.toStringAsFixed(2)} at "${result.merchant ?? 'Unknown Merchant'}"';
    });

    final categories = ref.read(categoriesListProvider).valueOrNull ?? [];
    if (categories.isNotEmpty) {
      final matching = categories.firstWhere(
        (c) => c.id == result.suggestedCategoryId,
        orElse: () => categories.first,
      );
      setState(() {
        _selectedCategory = matching;
      });
    }
  }

  @override
  void dispose() {
    _smsTextController.dispose();
    _senderController.dispose();
    _amountController.dispose();
    _merchantController.dispose();
    _notesController.dispose();
    _newWhitelistedNumberController.dispose();
    super.dispose();
  }

  Future<void> _saveSmsExpense() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedCategory == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a category for this SMS expense')),
      );
      return;
    }

    final amount = double.tryParse(_amountController.text) ?? 0.0;
    final nowStr = DateTime.now().toIso8601String();
    final dateIso = DateFormatters.formatDateIso(_selectedDate);

    final expense = Expense(
      uuid: const Uuid().v4(),
      amount: amount,
      categoryId: _selectedCategory!.id,
      subcategoryId: _selectedSubcategory?.id,
      personId: _selectedPerson?.uuid,
      classification: _classification,
      expenseDate: dateIso,
      createdAt: nowStr,
      updatedAt: nowStr,
      merchant: _merchantController.text.trim().isNotEmpty ? _merchantController.text.trim() : null,
      paymentMethod: _paymentMethod,
      notes: _notesController.text.trim(),
    );

    await ref.read(expenseNotifierProvider.notifier).addExpense(expense);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('✅ Added expense Rs ${amount.toStringAsFixed(2)} from SMS!'),
          backgroundColor: Colors.green,
        ),
      );
      context.pop();
    }
  }

  void _discardSms() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('🚫 SMS Notification Discarded / Ignored.'),
        backgroundColor: Colors.grey,
      ),
    );
    context.pop();
  }

  @override
  Widget build(BuildContext context) {
    final categoriesAsync = ref.watch(categoriesListProvider);
    final peopleAsync = ref.watch(peopleListProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Parse Shared SMS'),
        actions: [
          IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => context.pop(),
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16.0),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // 1. Shared SMS Input Card
                Card(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  child: Padding(
                    padding: const EdgeInsets.all(14.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Row(
                          children: [
                            Icon(Icons.sms, color: AppTheme.primaryColor),
                            SizedBox(width: 8),
                            Text(
                              'Shared Transaction SMS',
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: _smsTextController,
                          maxLines: 3,
                          decoration: const InputDecoration(
                            hintText: 'Paste or share bank transaction SMS text here...',
                            border: OutlineInputBorder(),
                            contentPadding: EdgeInsets.all(10),
                          ),
                        ),
                        const SizedBox(height: 8),

                        // Sender ID Input & Whitelist Badge
                        Row(
                          children: [
                            Expanded(
                              flex: 2,
                              child: TextField(
                                controller: _senderController,
                                decoration: const InputDecoration(
                                  labelText: 'Sender ID / Bank Number',
                                  hintText: 'e.g. MeezanBank, 8257, HBL',
                                  isDense: true,
                                  border: OutlineInputBorder(),
                                  contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                ),
                                style: const TextStyle(fontSize: 12),
                                onChanged: (val) => _runParseSms(_smsTextController.text, sender: val),
                              ),
                            ),
                            const SizedBox(width: 8),
                            if (_senderValidationMsg != null)
                              Expanded(
                                flex: 2,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: _isWhitelistedSender ? Colors.green.withValues(alpha: 0.1) : Colors.orange.withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(color: _isWhitelistedSender ? Colors.green : Colors.orange),
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(
                                        _isWhitelistedSender ? Icons.verified : Icons.warning_amber_rounded,
                                        size: 14,
                                        color: _isWhitelistedSender ? Colors.green[700] : Colors.orange[800],
                                      ),
                                      const SizedBox(width: 4),
                                      Expanded(
                                        child: Text(
                                          _isWhitelistedSender ? 'Whitelisted Bank' : 'Unverified Sender',
                                          style: TextStyle(
                                            fontSize: 10,
                                            fontWeight: FontWeight.bold,
                                            color: _isWhitelistedSender ? Colors.green[800] : Colors.orange[900],
                                          ),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        if (!_isWhitelistedSender && _senderController.text.trim().isNotEmpty) ...[
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: Colors.amber.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.amber.shade400),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.info_outline, size: 16, color: Colors.orange),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    '"${_senderController.text.trim()}" is not in your Whitelist. Add it to automatically verify future SMS.',
                                    style: const TextStyle(fontSize: 11),
                                  ),
                                ),
                                const SizedBox(width: 6),
                                ElevatedButton.icon(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.teal,
                                    foregroundColor: Colors.white,
                                    visualDensity: VisualDensity.compact,
                                  ),
                                  onPressed: () {
                                    final sender = _senderController.text.trim();
                                    ref.read(smsWhitelistProvider.notifier).addSender(sender);
                                    _runParseSms(_smsTextController.text, sender: sender);
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(content: Text('✅ Added "$sender" to your SMS Whitelist!')),
                                    );
                                  },
                                  icon: const Icon(Icons.add, size: 14),
                                  label: const Text('Add Sender', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 8),
                        ],

                        // Quick Sample SMS Chips
                        const Text('Quick Test Templates:', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey)),
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          children: _sampleSmsTemplates.map((template) {
                            return ActionChip(
                              label: Text(template['label']!, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                              visualDensity: VisualDensity.compact,
                              padding: EdgeInsets.zero,
                              onPressed: () {
                                _smsTextController.text = template['text']!;
                                _senderController.text = template['sender']!;
                                _runParseSms(template['text']!, sender: template['sender']!);
                              },
                            );
                          }).toList(),
                        ),
                        const SizedBox(height: 8),

                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Text(
                                'Privacy First: App processes SMS shared by you.',
                                style: TextStyle(fontSize: 10, color: Colors.grey[600]),
                              ),
                            ),
                            ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppTheme.primaryColor,
                                foregroundColor: Colors.white,
                                visualDensity: VisualDensity.compact,
                              ),
                              onPressed: () => _runParseSms(_smsTextController.text),
                              icon: const Icon(Icons.bolt, size: 14),
                              label: const Text('Parse SMS'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // 2. Notification / Decision Card (Add or Discard)
                if (_isParsed) ...[
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.amber.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.amber[700]!),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.notifications_active, color: Colors.amber),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _parseMessage ?? 'Transaction SMS Received!',
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          'Would you like to log this as an expense or discard this transaction notification?',
                          style: TextStyle(fontSize: 12),
                        ),
                        const SizedBox(height: 12),

                        Row(
                          children: [
                            Expanded(
                              child: ElevatedButton.icon(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.green,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(vertical: 12),
                                ),
                                onPressed: _saveSmsExpense,
                                icon: const Icon(Icons.add_task, size: 18),
                                label: const Text('⚡ Add as Expense', style: TextStyle(fontWeight: FontWeight.bold)),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: OutlinedButton.icon(
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: Colors.red[700],
                                  side: BorderSide(color: Colors.red[300]!),
                                  padding: const EdgeInsets.symmetric(vertical: 12),
                                ),
                                onPressed: _discardSms,
                                icon: const Icon(Icons.cancel, size: 18),
                                label: const Text('🚫 Leave / Discard', style: TextStyle(fontWeight: FontWeight.bold)),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                ],

                // 3. Amount Field
                TextFormField(
                  controller: _amountController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  decoration: const InputDecoration(
                    labelText: 'Detected Amount *',
                    prefixText: 'Rs ',
                    prefixStyle: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  ),
                  validator: (val) {
                    if (val == null || val.trim().isEmpty) return 'Enter amount';
                    if (double.tryParse(val) == null || double.parse(val) <= 0) return 'Enter valid amount';
                    return null;
                  },
                ),
                const SizedBox(height: 14),

                // 4. Merchant / Vendor Field
                TextFormField(
                  controller: _merchantController,
                  decoration: const InputDecoration(
                    labelText: 'Merchant / Vendor Name',
                    hintText: 'e.g. Shell Petrol, Supermarket, Uber',
                    prefixIcon: Icon(Icons.store),
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 14),

                // 5. Category Selection
                categoriesAsync.when(
                  loading: () => const CircularProgressIndicator(),
                  error: (e, _) => Text('Error: $e'),
                  data: (categories) {
                    return DropdownButtonFormField<Category>(
                      value: _selectedCategory,
                      decoration: const InputDecoration(
                        labelText: 'Category *',
                        border: OutlineInputBorder(),
                      ),
                      items: categories.map((cat) {
                        return DropdownMenuItem<Category>(
                          value: cat,
                          child: Text(cat.name),
                        );
                      }).toList(),
                      onChanged: (cat) {
                        setState(() {
                          _selectedCategory = cat;
                          if (cat != null) _classification = cat.defaultClassification;
                        });
                      },
                    );
                  },
                ),
                const SizedBox(height: 14),

                // 6. Family Member / Person Selector
                peopleAsync.when(
                  loading: () => const SizedBox.shrink(),
                  error: (_, __) => const SizedBox.shrink(),
                  data: (people) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('Person / Family Member', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                            TextButton.icon(
                              style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                              onPressed: () async {
                                final created = await showAddPersonDialog(context, ref);
                                if (created != null) {
                                  setState(() => _selectedPerson = created);
                                }
                              },
                              icon: const Icon(Icons.person_add, size: 16),
                              label: const Text('+ Add New Member', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        DropdownButtonFormField<Person?>(
                          value: _selectedPerson,
                          decoration: const InputDecoration(
                            hintText: 'Select Family Member',
                            border: OutlineInputBorder(),
                          ),
                          items: [
                            const DropdownMenuItem<Person?>(
                              value: null,
                              child: Text('🏠 General Household'),
                            ),
                            ...people.map((p) {
                              return DropdownMenuItem<Person?>(
                                value: p,
                                child: Text('👤 ${p.name} ${p.relationship != null ? '(${p.relationship})' : ''}'),
                              );
                            }),
                          ],
                          onChanged: (val) {
                            setState(() => _selectedPerson = val);
                          },
                        ),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 14),

                // 7. Expense Classification (2 Options: Required vs Optional)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Expense Type (Classification):', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Expanded(
                              child: RadioListTile<ExpenseClassification>(
                                title: const Text('Required', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                                value: ExpenseClassification.required,
                                groupValue: _classification,
                                onChanged: (val) {
                                  if (val != null) setState(() => _classification = val);
                                },
                              ),
                            ),
                            Expanded(
                              child: RadioListTile<ExpenseClassification>(
                                title: const Text('Optional', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                                value: ExpenseClassification.optional,
                                groupValue: _classification,
                                onChanged: (val) {
                                  if (val != null) setState(() => _classification = val);
                                },
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // 8. Whitelisted Senders & Live SMS Receiver Manager
                Card(
                  elevation: 2,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  child: Padding(
                    padding: const EdgeInsets.all(14.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.security, color: AppTheme.primaryColor),
                            const SizedBox(width: 8),
                            const Expanded(
                              child: Text('Whitelisted Sender Numbers & Auto-Catch', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                            ),
                            Chip(
                              visualDensity: VisualDensity.compact,
                              backgroundColor: _hasSmsPermission ? Colors.green.shade100 : Colors.amber.shade100,
                              label: Text(
                                _hasSmsPermission ? '🟢 Active' : '🟡 Permission Required',
                                style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: _hasSmsPermission ? Colors.green.shade900 : Colors.amber.shade900),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'When an SMS arrives from any of your Whitelisted Numbers below, My Expence Book will automatically capture the SMS and prompt you to log the expense.',
                          style: TextStyle(fontSize: 11, color: Colors.grey),
                        ),
                        const SizedBox(height: 12),

                        if (!_hasSmsPermission) ...[
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(backgroundColor: Colors.teal, foregroundColor: Colors.white),
                              onPressed: _requestSmsPermission,
                              icon: const Icon(Icons.phonelink_ring, size: 16),
                              label: const Text('Enable Automatic SMS Receiver', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                            ),
                          ),
                          const SizedBox(height: 12),
                        ],

                        // Input field to add ANY number
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _newWhitelistedNumberController,
                                decoration: const InputDecoration(
                                  hintText: 'Enter phone no. or sender (e.g. 03001234567, MeezanBank)',
                                  border: OutlineInputBorder(),
                                  isDense: true,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryColor, foregroundColor: Colors.white),
                              onPressed: () {
                                final text = _newWhitelistedNumberController.text.trim();
                                if (text.isNotEmpty) {
                                  ref.read(smsWhitelistProvider.notifier).addSender(text);
                                  _newWhitelistedNumberController.clear();
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text('✅ Whitelisted "$text"! App will auto-catch incoming SMS from this sender.')),
                                  );
                                }
                              },
                              icon: const Icon(Icons.add, size: 14),
                              label: const Text('+ Add', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),

                        // Display list of active whitelisted senders
                        Consumer(
                          builder: (context, ref, _) {
                            final whitelist = ref.watch(smsWhitelistProvider);
                            if (whitelist.isEmpty) {
                              return const Padding(
                                padding: EdgeInsets.symmetric(vertical: 4.0),
                                child: Text(
                                  'No whitelisted numbers added yet. Enter a phone number or sender above to enable auto-catching.',
                                  style: TextStyle(fontSize: 11, fontStyle: FontStyle.italic, color: Colors.grey),
                                ),
                              );
                            }
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Wrap(
                                  spacing: 6,
                                  runSpacing: 6,
                                  children: whitelist.map((sender) {
                                    return Chip(
                                      avatar: const Icon(Icons.verified, size: 14, color: Colors.teal),
                                      label: Text(sender, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                                      onDeleted: () {
                                        ref.read(smsWhitelistProvider.notifier).removeSender(sender);
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          SnackBar(content: Text('Removed "$sender" from Whitelist.')),
                                        );
                                      },
                                    );
                                  }).toList(),
                                ),
                                const SizedBox(height: 4),
                                Align(
                                  alignment: Alignment.centerRight,
                                  child: TextButton.icon(
                                    style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                                    onPressed: () {
                                      ref.read(smsWhitelistProvider.notifier).clearAll();
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(content: Text('Cleared all whitelisted senders.')),
                                      );
                                    },
                                    icon: const Icon(Icons.delete_sweep, size: 14, color: Colors.red),
                                    label: const Text('Clear All', style: TextStyle(fontSize: 11, color: Colors.red)),
                                  ),
                                ),
                              ],
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // Bottom action button
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryColor,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  onPressed: _saveSmsExpense,
                  icon: const Icon(Icons.check_circle),
                  label: const Text('Save Parsed SMS Expense', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
