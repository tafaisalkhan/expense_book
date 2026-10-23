import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:myexpence/core/theme/app_theme.dart';
import 'package:myexpence/core/utils/date_formatters.dart';
import 'package:myexpence/core/widgets/draggable_floating_action_button.dart';
import 'package:myexpence/features/ads/presentation/providers/ad_providers.dart';
import 'package:myexpence/features/categories/domain/models/category.dart';
import 'package:myexpence/features/categories/presentation/providers/category_providers.dart';
import 'package:myexpence/features/expenses/domain/models/expense.dart';
import 'package:myexpence/features/expenses/domain/models/expense_classification.dart';
import 'package:myexpence/features/expenses/domain/models/payment_method.dart';
import 'package:myexpence/features/expenses/domain/models/expense_allocation.dart';
import 'package:myexpence/features/expenses/domain/models/recurring_expense.dart';
import 'package:myexpence/core/providers/core_providers.dart';
import 'package:myexpence/core/utils/currency_formatters.dart';
import 'package:myexpence/features/expenses/presentation/providers/expense_providers.dart';
import 'package:myexpence/features/people/domain/models/person.dart';
import 'package:myexpence/features/people/presentation/providers/people_providers.dart';
import 'package:uuid/uuid.dart';
import 'package:myexpence/features/expenses/presentation/widgets/expense_voice_note_widget.dart';
import 'package:myexpence/features/expenses/presentation/widgets/multi_item_picker_sheet.dart';
import 'package:myexpence/features/settings/presentation/providers/settings_providers.dart';

class AddExpenseScreen extends ConsumerStatefulWidget {
  final Expense? expenseToEdit;

  const AddExpenseScreen({super.key, this.expenseToEdit});

  @override
  ConsumerState<AddExpenseScreen> createState() => _AddExpenseScreenState();
}

class _AddExpenseScreenState extends ConsumerState<AddExpenseScreen> {
  final _formKey = GlobalKey<FormState>();
  final _amountController = TextEditingController();
  final _merchantController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _notesController = TextEditingController();

  late final String _expenseUuid;
  String? _voiceNotePath;
  String? _voiceNoteBase64;
  int? _voiceDurationSeconds;

  DateTime _selectedDate = DateTime.now();
  TimeOfDay? _selectedTime;
  Category? _selectedCategory;
  Subcategory? _selectedSubcategory;
  Person? _selectedPerson; // null = Household
  ExpenseClassification _classification = ExpenseClassification.required;
  PaymentMethod _paymentMethod = PaymentMethod.cash;
  final Map<String, double> _memberShares = {};
  bool _splitByPercentage = true;
  bool _isRecurring = false;
  RecurrenceFrequency _recurrenceFrequency = RecurrenceFrequency.monthly;
  int _intervalDays = 2;

  bool _initializedEditFields = false;

  /// Items picked from the grocery multi-item popup. Each one is saved as a
  /// separate expense under its own subcategory.
  List<MultiItemLine> _multiItems = [];

  bool get _isMultiItemMode =>
      widget.expenseToEdit == null && _multiItems.isNotEmpty;

  double get _multiItemsTotal =>
      _multiItems.fold(0.0, (sum, i) => sum + i.amount);

  @override
  void initState() {
    super.initState();
    _expenseUuid = widget.expenseToEdit?.uuid ?? const Uuid().v4();
    if (widget.expenseToEdit != null) {
      final e = widget.expenseToEdit!;
      _amountController.text = e.amount.toString();
      _merchantController.text = e.merchant ?? '';
      _descriptionController.text = e.description ?? '';
      _notesController.text = e.notes ?? '';
      _classification = e.classification;
      _paymentMethod = e.paymentMethod;
      _isRecurring = e.recurringOccurrenceId != null;
      _voiceNotePath = e.voiceNotePath;
      _voiceNoteBase64 = e.voiceNoteBase64;
      _voiceDurationSeconds = e.voiceDurationSeconds;
      for (final allocation in e.allocations) {
        _memberShares[allocation.personId] = allocation.percentage;
      }
      try {
        _selectedDate = DateFormatters.parseDateIso(e.expenseDate);
      } catch (_) {}
      if (e.expenseTime != null && e.expenseTime!.contains(':')) {
        final parts = e.expenseTime!.split(':');
        _selectedTime = TimeOfDay(
          hour: int.tryParse(parts[0]) ?? 0,
          minute: int.tryParse(parts[1]) ?? 0,
        );
      }
    }
  }

  void _initEditCategoryAndPerson(
      List<Category> categories, List<Person> people) {
    if (_initializedEditFields || widget.expenseToEdit == null) return;
    _initializedEditFields = true;

    final e = widget.expenseToEdit!;
    final catIndex = categories.indexWhere((c) => c.id == e.categoryId);
    if (catIndex != -1) {
      _selectedCategory = categories[catIndex];
      if (e.subcategoryId != null) {
        final subIndex = _selectedCategory!.subcategories
            .indexWhere((s) => s.id == e.subcategoryId);
        if (subIndex != -1) {
          _selectedSubcategory = _selectedCategory!.subcategories[subIndex];
        }
      }
    }

    if (e.personId != null) {
      final pIndex = people.indexWhere((p) => p.uuid == e.personId);
      if (pIndex != -1) {
        _selectedPerson = people[pIndex];
      }
    }
  }

  @override
  void dispose() {
    _amountController.dispose();
    _merchantController.dispose();
    _descriptionController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  void _onCategoryChanged(Category? cat) {
    setState(() {
      _selectedCategory = cat;
      _selectedSubcategory = null;
      _multiItems = [];
      if (cat != null) {
        _classification = cat.defaultClassification;
      }
    });
    // For any category with subcategories: open the multi-item popup automatically (new expenses only)
    if (widget.expenseToEdit == null && cat != null && cat.subcategories.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _openMultiItemPicker());
    }
  }

  Future<void> _openMultiItemPicker() async {
    final cat = _selectedCategory;
    if (cat == null || !mounted) return;
    final currentAmount = double.tryParse(_amountController.text.trim());
    final result = await showMultiItemPickerSheet(
      context,
      category: cat,
      initial: _multiItems,
      targetTotal: currentAmount != null && currentAmount > 0 ? currentAmount : null,
    );
    if (result == null || !mounted) return;
    setState(() {
      _multiItems = result;
      if (result.isNotEmpty) {
        _selectedSubcategory = null;
        final t = _multiItemsTotal;
        _amountController.text =
            t == t.roundToDouble() ? t.toStringAsFixed(0) : t.toStringAsFixed(2);
      }
    });
  }

  /// Returns the subcategory id for [line], creating a new subcategory under
  /// the selected category when the item doesn't exist yet.
  Future<String> _ensureSubcategoryId(MultiItemLine line) async {
    final cat = _selectedCategory!;
    if (line.subcategoryId != null) return line.subcategoryId!;
    final existing = [...cat.subcategories, ..._createdSubs]
        .where((s) => s.name.trim().toLowerCase() == line.name.trim().toLowerCase())
        .firstOrNull;
    if (existing != null) return existing.id;

    final maxSort = [...cat.subcategories, ..._createdSubs].fold<int>(
        0, (m, s) => s.sortOrder > m ? s.sortOrder : m);
    final sub = Subcategory(
      id: 'sub_custom_${const Uuid().v4()}',
      categoryId: cat.id,
      name: line.name.trim(),
      defaultClassification: cat.defaultClassification,
      sortOrder: maxSort + 1,
    );
    await ref.read(categoryRepositoryProvider).addSubcategory(sub);
    _createdSubs.add(sub);
    return sub.id;
  }

  /// Subcategories auto-created during the current multi-item save.
  final List<Subcategory> _createdSubs = [];

  void _onSubcategoryChanged(Subcategory? sub) {
    setState(() {
      _selectedSubcategory = sub;
      if (sub != null) {
        _classification = sub.defaultClassification;
      }
    });
  }

  Future<void> _submitForm() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedCategory == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a category')),
      );
      return;
    }

    final amount = double.tryParse(_amountController.text) ?? 0.0;
    final people = ref.read(peopleListProvider).valueOrNull ?? [];
    final allocations = _buildAllocations(amount, people);
    if (allocations == null) return;
    final isEdit = widget.expenseToEdit != null;
    final nowStr = DateTime.now().toIso8601String();
    final dateIso = DateFormatters.formatDateIso(_selectedDate);
    final timeStr = _selectedTime != null
        ? '${_selectedTime!.hour.toString().padLeft(2, '0')}:${_selectedTime!.minute.toString().padLeft(2, '0')}'
        : null;

    if (_isMultiItemMode) {
      final diff = (amount - _multiItemsTotal).abs();
      if (diff > 0.01) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Total amount above (Rs ${amount.toStringAsFixed(0)}) must match the sum of subcategories (Rs ${_multiItemsTotal.toStringAsFixed(0)}).',
            ),
            backgroundColor: Colors.red[800],
          ),
        );
        return;
      }
      await _saveMultiItems(allocations, dateIso, timeStr, nowStr);
      return;
    }

    final expense = Expense(
      uuid: _expenseUuid,
      amount: amount,
      categoryId: _selectedCategory!.id,
      subcategoryId: _selectedSubcategory?.id,
      personId: allocations.isEmpty
          ? _selectedPerson?.uuid
          : (allocations.length == 1 ? allocations.first.personId : null),
      classification: _classification,
      expenseDate: dateIso,
      expenseTime: timeStr,
      createdAt: isEdit ? widget.expenseToEdit!.createdAt : nowStr,
      updatedAt: nowStr,
      merchant: _merchantController.text.trim().isNotEmpty
          ? _merchantController.text.trim()
          : null,
      description: _descriptionController.text.trim().isNotEmpty
          ? _descriptionController.text.trim()
          : null,
      paymentMethod: _paymentMethod,
      notes: _notesController.text.trim().isNotEmpty
          ? _notesController.text.trim()
          : null,
      receiptId: isEdit ? widget.expenseToEdit!.receiptId : null,
      status: isEdit ? widget.expenseToEdit!.status : ExpenseStatus.paid,
      currency: CurrencyFormatters.defaultCurrency,
      allocations: allocations,
      voiceNotePath: _voiceNotePath,
      voiceNoteBase64: _voiceNoteBase64,
      voiceDurationSeconds: _voiceDurationSeconds,
    );

    if (isEdit) {
      await ref.read(expenseNotifierProvider.notifier).updateExpense(expense);
    } else {
      await ref.read(expenseNotifierProvider.notifier).addExpense(expense);
    }

    if (_isRecurring) {
      await ref.read(recurringExpenseServiceProvider).saveSchedule(
            template: expense,
            frequency: _recurrenceFrequency,
            intervalDays: _intervalDays,
            existingScheduleId:
                widget.expenseToEdit?.recurringOccurrenceId?.split(':').first,
          );
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(isEdit
                ? 'Expense updated successfully!'
                : 'Expense added successfully!')),
      );
      ref.read(adNotifierProvider.notifier).recordNavigation(context);
      context.pop();
    }
  }

  /// Saves every selected grocery item as its own expense row (own
  /// subcategory, own amount). Shared fields (date, person, payment, notes)
  /// are copied to each row; the voice note is attached to the first row.
  Future<void> _saveMultiItems(
    List<ExpenseAllocation> allocations,
    String dateIso,
    String? timeStr,
    String nowStr,
  ) async {
    final notifier = ref.read(expenseNotifierProvider.notifier);
    final merchant = _merchantController.text.trim();
    final notes = _notesController.text.trim();
    var first = true;

    for (final item in _multiItems) {
      final subId = await _ensureSubcategoryId(item);
      final sub = [..._selectedCategory!.subcategories, ..._createdSubs]
          .where((s) => s.id == subId)
          .firstOrNull;
      // Scale member split to this item's amount (percentages stay the same)
      final itemAllocations = allocations
          .map((a) => ExpenseAllocation(
                personId: a.personId,
                personName: a.personName,
                percentage: a.percentage,
                amount: item.amount * a.percentage / 100,
              ))
          .toList();

      final expense = Expense(
        uuid: first ? _expenseUuid : const Uuid().v4(),
        amount: item.amount,
        categoryId: _selectedCategory!.id,
        subcategoryId: subId,
        personId: itemAllocations.isEmpty
            ? _selectedPerson?.uuid
            : (itemAllocations.length == 1 ? itemAllocations.first.personId : null),
        classification: sub?.defaultClassification ?? _classification,
        expenseDate: dateIso,
        expenseTime: timeStr,
        createdAt: nowStr,
        updatedAt: nowStr,
        merchant: merchant.isNotEmpty ? merchant : null,
        description: item.displayName,
        paymentMethod: _paymentMethod,
        currency: CurrencyFormatters.defaultCurrency,
        notes: notes.isNotEmpty ? notes : null,
        status: ExpenseStatus.paid,
        allocations: itemAllocations,
        voiceNotePath: first ? _voiceNotePath : null,
        voiceNoteBase64: first ? _voiceNoteBase64 : null,
        voiceDurationSeconds: first ? _voiceDurationSeconds : null,
      );
      await notifier.addExpense(expense);

      if (_isRecurring) {
        await ref.read(recurringExpenseServiceProvider).saveSchedule(
              template: expense,
              frequency: _recurrenceFrequency,
              intervalDays: _intervalDays,
            );
      }
      first = false;
    }

    if (!mounted) return;
    final container = ProviderScope.containerOf(context, listen: false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
          content:
              Text('${_multiItems.length} items saved as separate expenses!')),
    );
    ref.read(adNotifierProvider.notifier).recordNavigation(context);
    context.pop();
    // Refresh categories (new custom subcategories) after leaving this screen
    if (_createdSubs.isNotEmpty) container.invalidate(categoriesListProvider);
  }

  List<ExpenseAllocation>? _buildAllocations(
      double total, List<Person> people) {
    if (_memberShares.isEmpty) return const [];
    final shareTotal =
        _memberShares.values.fold<double>(0, (sum, value) => sum + value);
    final expected = _splitByPercentage ? 100.0 : total;
    if ((shareTotal - expected).abs() > 0.01) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(_splitByPercentage
            ? 'Member percentages must total 100%.'
            : 'Member amounts must total ${CurrencyFormatters.defaultCurrency} ${total.toStringAsFixed(2)}.'),
      ));
      return null;
    }
    return _memberShares.entries.map((entry) {
      final person = people.where((p) => p.uuid == entry.key).firstOrNull;
      final percentage = _splitByPercentage
          ? entry.value
          : (total == 0 ? 0.0 : entry.value / total * 100);
      final allocatedAmount =
          _splitByPercentage ? total * entry.value / 100 : entry.value;
      return ExpenseAllocation(
        personId: entry.key,
        personName: person?.name ?? 'Family member',
        percentage: percentage,
        amount: allocatedAmount,
      );
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(currencyNotifierProvider);
    final categoriesAsync = ref.watch(categoriesListProvider);
    final peopleAsync = ref.watch(peopleListProvider);

    _initEditCategoryAndPerson(
      categoriesAsync.valueOrNull ?? [],
      peopleAsync.valueOrNull ?? [],
    );

    return Scaffold(
      appBar: AppBar(
        title:
            Text(widget.expenseToEdit != null ? 'Edit Expense' : 'Add Expense'),
        actions: [
          IconButton(
            icon: const Icon(Icons.receipt_long),
            tooltip: 'Share / Attach Receipt Slip',
            onPressed: () => context.push('/share-receipt'),
          ),
        ],
      ),
      body: Stack(
        children: [
          SingleChildScrollView(
            padding: const EdgeInsets.only(
                left: 16.0, right: 16.0, top: 16.0, bottom: 90.0),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 1. Amount Field
                  TextFormField(
                    controller: _amountController,
                    readOnly: _isMultiItemMode,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    style: const TextStyle(
                        fontSize: 28, fontWeight: FontWeight.bold),
                    decoration: InputDecoration(
                      labelText: _isMultiItemMode
                          ? 'Total of ${_multiItems.length} items'
                          : 'Amount *',
                      prefixText: 'Rs ',
                      prefixStyle: const TextStyle(
                          fontSize: 28, fontWeight: FontWeight.bold),
                      border: const OutlineInputBorder(),
                    ),
                    validator: (val) {
                      if (val == null || val.trim().isEmpty) {
                        return 'Enter amount';
                      }
                      final amt = double.tryParse(val);
                      if (amt == null || amt <= 0) {
                        return 'Enter valid positive amount';
                      }
                      if (_isMultiItemMode) {
                        final diff = (amt - _multiItemsTotal).abs();
                        if (diff > 0.01) {
                          return 'Amount must match subcategories total (Rs ${_multiItemsTotal.toStringAsFixed(0)})';
                        }
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 20),

                  // 2. Quick Date Buttons (TODAY, YESTERDAY, SELECT DATE)
                  const Text('Transaction Date *',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            backgroundColor:
                                DateFormatters.formatDateIso(_selectedDate) ==
                                        DateFormatters.todayIso()
                                    ? AppTheme.primaryColor.withOpacity(0.15)
                                    : null,
                          ),
                          onPressed: () {
                            setState(() => _selectedDate = DateTime.now());
                          },
                          child: const Text('TODAY'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            backgroundColor:
                                DateFormatters.formatDateIso(_selectedDate) ==
                                        DateFormatters.yesterdayIso()
                                    ? AppTheme.primaryColor.withOpacity(0.15)
                                    : null,
                          ),
                          onPressed: () {
                            setState(() => _selectedDate = DateTime.now()
                                .subtract(const Duration(days: 1)));
                          },
                          child: const Text('YESTERDAY'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.calendar_today, size: 16),
                          label: Text(
                              DateFormatters.formatDateShort(_selectedDate)),
                          onPressed: () async {
                            final picked = await showDatePicker(
                              context: context,
                              initialDate: _selectedDate,
                              firstDate: DateTime(2020),
                              lastDate:
                                  DateTime.now().add(const Duration(days: 365)),
                            );
                            if (picked != null) {
                              setState(() => _selectedDate = picked);
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),

                  // 3. Category & Subcategory Selection
                  categoriesAsync.when(
                    loading: () => const CircularProgressIndicator(),
                    error: (e, _) => Text('Error loading categories: $e'),
                    data: (categories) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          DropdownButtonFormField<Category>(
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
                            onChanged: _onCategoryChanged,
                          ),
                          if (widget.expenseToEdit == null &&
                              _selectedCategory != null &&
                              _selectedCategory!.subcategories.isNotEmpty) ...[
                            const SizedBox(height: 12),
                            _buildMultiItemSection(),
                          ],
                          if (!_isMultiItemMode &&
                              _selectedCategory != null &&
                              _selectedCategory!.subcategories.isNotEmpty) ...[
                            const SizedBox(height: 16),
                            DropdownButtonFormField<Subcategory>(
                              value: _selectedSubcategory,
                              decoration: const InputDecoration(
                                labelText: 'Subcategory',
                                border: OutlineInputBorder(),
                              ),
                              items:
                                  _selectedCategory!.subcategories.map((sub) {
                                return DropdownMenuItem<Subcategory>(
                                  value: sub,
                                  child: Text(sub.name),
                                );
                              }).toList(),
                              onChanged: _onSubcategoryChanged,
                            ),
                          ],
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 20),

                  // 4. Person / Household Selector
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
                              const Expanded(
                                child: Text(
                                  'Family Member / Profile',
                                  style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              TextButton.icon(
                                style: TextButton.styleFrom(
                                    visualDensity: VisualDensity.compact),
                                onPressed: () async {
                                  final created =
                                      await showAddPersonDialog(context, ref);
                                  if (created != null) {
                                    setState(() => _selectedPerson = created);
                                  }
                                },
                                icon: const Icon(Icons.person_add, size: 16),
                                label: const Text('+ Add New Member',
                                    style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold)),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          DropdownButtonFormField<Person?>(
                            value: _selectedPerson,
                            decoration: const InputDecoration(
                              hintText: 'Select Family Member',
                              border: OutlineInputBorder(),
                              helperText:
                                  'Select General Household if not for a specific person',
                            ),
                            items: [
                              const DropdownMenuItem<Person?>(
                                value: null,
                                child: Text('🏠 General Household'),
                              ),
                              ...people.map((p) {
                                return DropdownMenuItem<Person?>(
                                  value: p,
                                  child: Text(
                                      '👤 ${p.name} ${p.relationship != null ? '(${p.relationship})' : ''}'),
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
                  const SizedBox(height: 20),

                  peopleAsync.when(
                    loading: () => const SizedBox.shrink(),
                    error: (_, __) => const SizedBox.shrink(),
                    data: (people) => _buildAllocationSection(people),
                  ),
                  const SizedBox(height: 20),

                  _buildRecurringSection(),
                  const SizedBox(height: 20),

                  // 5. Classification Picker (Urgent / Required / Optional)
                  const Text('Classification *',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  SegmentedButton<ExpenseClassification>(
                    segments: const [
                      ButtonSegment(
                        value: ExpenseClassification.urgent,
                        label: Text('Urgent'),
                        icon: Icon(Icons.priority_high),
                      ),
                      ButtonSegment(
                        value: ExpenseClassification.required,
                        label: Text('Required'),
                        icon: Icon(Icons.lock_clock),
                      ),
                      ButtonSegment(
                        value: ExpenseClassification.optional,
                        label: Text('Optional'),
                        icon: Icon(Icons.local_activity),
                      ),
                      ButtonSegment(
                        value: ExpenseClassification.lost,
                        label: Text('Lost'),
                        icon: Icon(Icons.money_off),
                      ),
                    ],
                    selected: {_classification},
                    onSelectionChanged: (set) {
                      setState(() => _classification = set.first);
                    },
                  ),
                  const SizedBox(height: 20),

                  // 6. Payment Method
                  DropdownButtonFormField<PaymentMethod>(
                    value: _paymentMethod,
                    decoration: const InputDecoration(
                      labelText: 'Payment Method',
                      border: OutlineInputBorder(),
                    ),
                    items: PaymentMethod.values.map((method) {
                      return DropdownMenuItem<PaymentMethod>(
                        value: method,
                        child: Text(method.label),
                      );
                    }).toList(),
                    onChanged: (val) {
                      if (val != null) setState(() => _paymentMethod = val);
                    },
                  ),
                  const SizedBox(height: 16),

                  // 7. Merchant & Description
                  TextFormField(
                    controller: _merchantController,
                    decoration: const InputDecoration(
                      labelText: 'Merchant / Store / Payee',
                      border: OutlineInputBorder(),
                      hintText: 'e.g. Metro Cash & Carry, Shell, ABC School',
                    ),
                  ),
                  const SizedBox(height: 16),

                  TextFormField(
                    controller: _notesController,
                    decoration: const InputDecoration(
                      labelText: 'Notes / Description',
                      border: OutlineInputBorder(),
                      hintText: 'e.g. Exam fee payment for 1st term',
                    ),
                    maxLines: 2,
                  ),
                  const SizedBox(height: 20),

                  // 8. Voice Note
                  ExpenseVoiceNoteWidget(
                    expenseUuid: _expenseUuid,
                    initialVoiceNotePath: _voiceNotePath,
                    initialVoiceNoteBase64: _voiceNoteBase64,
                    initialDurationSeconds: _voiceDurationSeconds,
                    onVoiceNoteChanged: ({localPath, base64Data, durationSeconds}) {
                      setState(() {
                        _voiceNotePath = localPath;
                        _voiceNoteBase64 = base64Data;
                        _voiceDurationSeconds = durationSeconds;
                      });
                    },
                  ),
                  const SizedBox(height: 28),
                ],
              ),
            ),
          ),
          DraggableSaveButton(
            onPressed: _submitForm,
            label: widget.expenseToEdit != null
                ? 'Update Expense'
                : 'Save Expense',
            icon: Icons.check_circle,
            initialBottom: 24,
            initialRight: 16,
          ),
        ],
      ),
    );
  }

  Widget _buildMultiItemSection() {
    String fmt(double v) =>
        v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(2);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.green.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.green.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.playlist_add_check, color: Colors.green, size: 22),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _multiItems.isEmpty
                      ? 'Select multiple ${_selectedCategory?.name ?? "sub-items"}'
                      : '${_multiItems.length} items (saved separately)',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
              TextButton.icon(
                onPressed: _openMultiItemPicker,
                icon: Icon(_multiItems.isEmpty ? Icons.add : Icons.edit, size: 18),
                label: Text(_multiItems.isEmpty ? 'Select' : 'Edit'),
              ),
            ],
          ),
          if (_multiItems.isEmpty)
            Text(
              'Select multiple items above, or pick a single subcategory below.',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
          ..._multiItems.map((item) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  children: [
                    const Icon(Icons.check_circle, size: 16, color: Colors.green),
                    const SizedBox(width: 8),
                    Expanded(child: Text(item.displayName)),
                    Text('${CurrencyFormatters.defaultCurrency} ${fmt(item.amount)}',
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      icon: const Icon(Icons.close, size: 16),
                      onPressed: () => setState(() {
                        _multiItems = [..._multiItems]..remove(item);
                        _amountController.text =
                            _multiItems.isEmpty ? '' : fmt(_multiItemsTotal);
                      }),
                    ),
                  ],
                ),
              )),
          if (_multiItems.isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.green.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Subcategories Total:',
                      style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                  Text('${CurrencyFormatters.defaultCurrency} ${fmt(_multiItemsTotal)}',
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 14, color: Colors.green)),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildAllocationSection(List<Person> people) {
    return ExpansionTile(
      tilePadding: EdgeInsets.zero,
      title: const Text('Split between family members',
          style: TextStyle(fontWeight: FontWeight.bold)),
      subtitle: Text(_memberShares.isEmpty
          ? 'Optional'
          : '${_memberShares.length} members selected'),
      children: [
        SegmentedButton<bool>(
          segments: const [
            ButtonSegment(value: true, label: Text('Percentage')),
            ButtonSegment(value: false, label: Text('Amount')),
          ],
          selected: {_splitByPercentage},
          onSelectionChanged: (value) => setState(() {
            _splitByPercentage = value.first;
            _memberShares.clear();
          }),
        ),
        const SizedBox(height: 8),
        ...people.map((person) {
          final selected = _memberShares.containsKey(person.uuid);
          return Row(
            children: [
              Checkbox(
                value: selected,
                onChanged: (checked) => setState(() {
                  if (checked == true) {
                    _memberShares[person.uuid] = 0;
                  } else {
                    _memberShares.remove(person.uuid);
                  }
                }),
              ),
              Expanded(child: Text(person.name)),
              if (selected)
                SizedBox(
                  width: 110,
                  child: TextFormField(
                    initialValue:
                        _memberShares[person.uuid]?.toStringAsFixed(2),
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                      suffixText: _splitByPercentage ? '%' : CurrencyFormatters.defaultCurrency,
                      isDense: true,
                    ),
                    onChanged: (value) => _memberShares[person.uuid] =
                        double.tryParse(value) ?? 0,
                  ),
                ),
            ],
          );
        }),
      ],
    );
  }

  Widget _buildRecurringSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Recurring expense',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              subtitle: const Text(
                  'Create pending expenses automatically for your approval'),
              value: _isRecurring,
              onChanged: (value) => setState(() => _isRecurring = value),
            ),
            if (_isRecurring) ...[
              DropdownButtonFormField<RecurrenceFrequency>(
                initialValue: _recurrenceFrequency,
                decoration: const InputDecoration(
                    labelText: 'Repeat', border: OutlineInputBorder()),
                items: const [
                  DropdownMenuItem(
                      value: RecurrenceFrequency.daily,
                      child: Text('Every day')),
                  DropdownMenuItem(
                      value: RecurrenceFrequency.everyNDays,
                      child: Text('Every number of days')),
                  DropdownMenuItem(
                      value: RecurrenceFrequency.monthly,
                      child: Text('Every month')),
                ],
                onChanged: (value) =>
                    setState(() => _recurrenceFrequency = value!),
              ),
              if (_recurrenceFrequency == RecurrenceFrequency.everyNDays) ...[
                const SizedBox(height: 12),
                TextFormField(
                  initialValue: _intervalDays.toString(),
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Repeat every how many days?',
                    helperText: 'For example: 2 or 3 days',
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) {
                    if (!_isRecurring ||
                        _recurrenceFrequency != RecurrenceFrequency.everyNDays)
                      return null;
                    final days = int.tryParse(value ?? '');
                    return days == null || days < 1
                        ? 'Enter at least 1 day'
                        : null;
                  },
                  onChanged: (value) =>
                      _intervalDays = int.tryParse(value) ?? 1,
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}
