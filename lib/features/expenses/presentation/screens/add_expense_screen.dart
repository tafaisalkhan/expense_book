import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:myexpence/core/theme/app_theme.dart';
import 'package:myexpence/core/utils/date_formatters.dart';
import 'package:myexpence/core/widgets/draggable_floating_action_button.dart';
import 'package:myexpence/features/categories/domain/models/category.dart';
import 'package:myexpence/features/categories/presentation/providers/category_providers.dart';
import 'package:myexpence/features/expenses/domain/models/expense.dart';
import 'package:myexpence/features/expenses/domain/models/expense_classification.dart';
import 'package:myexpence/features/expenses/domain/models/payment_method.dart';
import 'package:myexpence/features/expenses/presentation/providers/expense_providers.dart';
import 'package:myexpence/features/people/domain/models/person.dart';
import 'package:myexpence/features/people/presentation/providers/people_providers.dart';
import 'package:uuid/uuid.dart';

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

  DateTime _selectedDate = DateTime.now();
  TimeOfDay? _selectedTime;
  Category? _selectedCategory;
  Subcategory? _selectedSubcategory;
  Person? _selectedPerson; // null = Household
  ExpenseClassification _classification = ExpenseClassification.required;
  PaymentMethod _paymentMethod = PaymentMethod.cash;

  bool _initializedEditFields = false;

  @override
  void initState() {
    super.initState();
    if (widget.expenseToEdit != null) {
      final e = widget.expenseToEdit!;
      _amountController.text = e.amount.toString();
      _merchantController.text = e.merchant ?? '';
      _descriptionController.text = e.description ?? '';
      _notesController.text = e.notes ?? '';
      _classification = e.classification;
      _paymentMethod = e.paymentMethod;
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

  void _initEditCategoryAndPerson(List<Category> categories, List<Person> people) {
    if (_initializedEditFields || widget.expenseToEdit == null) return;
    _initializedEditFields = true;

    final e = widget.expenseToEdit!;
    final catIndex = categories.indexWhere((c) => c.id == e.categoryId);
    if (catIndex != -1) {
      _selectedCategory = categories[catIndex];
      if (e.subcategoryId != null) {
        final subIndex = _selectedCategory!.subcategories.indexWhere((s) => s.id == e.subcategoryId);
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
      if (cat != null) {
        _classification = cat.defaultClassification;
      }
    });
  }

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
    final isEdit = widget.expenseToEdit != null;
    final nowStr = DateTime.now().toIso8601String();
    final dateIso = DateFormatters.formatDateIso(_selectedDate);
    final timeStr = _selectedTime != null
        ? '${_selectedTime!.hour.toString().padLeft(2, '0')}:${_selectedTime!.minute.toString().padLeft(2, '0')}'
        : null;

    final expense = Expense(
      uuid: isEdit ? widget.expenseToEdit!.uuid : const Uuid().v4(),
      amount: amount,
      categoryId: _selectedCategory!.id,
      subcategoryId: _selectedSubcategory?.id,
      personId: _selectedPerson?.uuid,
      classification: _classification,
      expenseDate: dateIso,
      expenseTime: timeStr,
      createdAt: isEdit ? widget.expenseToEdit!.createdAt : nowStr,
      updatedAt: nowStr,
      merchant: _merchantController.text.trim().isNotEmpty ? _merchantController.text.trim() : null,
      description: _descriptionController.text.trim().isNotEmpty ? _descriptionController.text.trim() : null,
      paymentMethod: _paymentMethod,
      notes: _notesController.text.trim().isNotEmpty ? _notesController.text.trim() : null,
      receiptId: isEdit ? widget.expenseToEdit!.receiptId : null,
      status: isEdit ? widget.expenseToEdit!.status : ExpenseStatus.paid,
    );

    if (isEdit) {
      await ref.read(expenseNotifierProvider.notifier).updateExpense(expense);
    } else {
      await ref.read(expenseNotifierProvider.notifier).addExpense(expense);
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(isEdit ? 'Expense updated successfully!' : 'Expense added successfully!')),
      );
      context.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final categoriesAsync = ref.watch(categoriesListProvider);
    final peopleAsync = ref.watch(peopleListProvider);

    _initEditCategoryAndPerson(
      categoriesAsync.valueOrNull ?? [],
      peopleAsync.valueOrNull ?? [],
    );

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.expenseToEdit != null ? 'Edit Expense' : 'Add Expense'),
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
            padding: const EdgeInsets.only(left: 16.0, right: 16.0, top: 16.0, bottom: 90.0),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
              // 1. Amount Field
              TextFormField(
                controller: _amountController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
                decoration: const InputDecoration(
                  labelText: 'Amount *',
                  prefixText: 'Rs ',
                  prefixStyle: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
                  border: OutlineInputBorder(),
                ),
                validator: (val) {
                  if (val == null || val.trim().isEmpty) return 'Enter amount';
                  if (double.tryParse(val) == null || double.parse(val) <= 0) return 'Enter valid positive amount';
                  return null;
                },
              ),
              const SizedBox(height: 20),

              // 2. Quick Date Buttons (TODAY, YESTERDAY, SELECT DATE)
              const Text('Transaction Date *', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        backgroundColor: DateFormatters.formatDateIso(_selectedDate) == DateFormatters.todayIso()
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
                        backgroundColor: DateFormatters.formatDateIso(_selectedDate) == DateFormatters.yesterdayIso()
                            ? AppTheme.primaryColor.withOpacity(0.15)
                            : null,
                      ),
                      onPressed: () {
                        setState(() => _selectedDate = DateTime.now().subtract(const Duration(days: 1)));
                      },
                      child: const Text('YESTERDAY'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.calendar_today, size: 16),
                      label: Text(DateFormatters.formatDateShort(_selectedDate)),
                      onPressed: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: _selectedDate,
                          firstDate: DateTime(2020),
                          lastDate: DateTime.now().add(const Duration(days: 365)),
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
                      if (_selectedCategory != null && _selectedCategory!.subcategories.isNotEmpty) ...[
                        const SizedBox(height: 16),
                        DropdownButtonFormField<Subcategory>(
                          value: _selectedSubcategory,
                          decoration: const InputDecoration(
                            labelText: 'Subcategory',
                            border: OutlineInputBorder(),
                          ),
                          items: _selectedCategory!.subcategories.map((sub) {
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
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
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
                          helperText: 'Select General Household if not for a specific person',
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
              const SizedBox(height: 20),

              // 5. Classification Picker (Required / Need / Optional)
              const Text('Classification *', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              SegmentedButton<ExpenseClassification>(
                segments: const [
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
              const SizedBox(height: 28),

                  const SizedBox(height: 30),
                ],
              ),
            ),
          ),
          DraggableSaveButton(
            onPressed: _submitForm,
            label: widget.expenseToEdit != null ? 'Update Expense' : 'Save Expense',
            icon: Icons.check_circle,
            initialBottom: 24,
            initialRight: 16,
          ),
        ],
      ),
    );
  }
}
