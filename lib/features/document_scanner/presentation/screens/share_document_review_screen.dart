import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:myexpence/core/providers/core_providers.dart';
import 'package:myexpence/core/theme/app_theme.dart';
import 'package:myexpence/core/utils/currency_formatters.dart';
import 'package:myexpence/core/utils/date_formatters.dart';
import 'package:myexpence/features/backup/feature_quota_service.dart';
import 'package:myexpence/features/backup/monthly_backup_billing.dart';
import 'package:myexpence/features/categories/domain/models/category.dart';
import 'package:myexpence/features/categories/presentation/providers/category_providers.dart';
import 'package:myexpence/features/document_scanner/domain/services/ocr_scanner_service.dart';
import 'package:myexpence/features/document_scanner/presentation/widgets/voice_expense_sheet.dart';
import 'package:myexpence/features/expenses/domain/models/expense.dart';
import 'package:myexpence/features/expenses/domain/models/expense_classification.dart';
import 'package:myexpence/features/expenses/presentation/providers/expense_providers.dart';
import 'package:myexpence/features/people/domain/models/person.dart';
import 'package:myexpence/features/people/presentation/providers/people_providers.dart';
import 'package:myexpence/features/receipts/domain/models/receipt.dart';
import 'package:uuid/uuid.dart';

class ShareDocumentReviewScreen extends ConsumerStatefulWidget {
  final String? sharedImagePath;

  const ShareDocumentReviewScreen({super.key, this.sharedImagePath});

  @override
  ConsumerState<ShareDocumentReviewScreen> createState() =>
      _ShareDocumentReviewScreenState();
}

class _ShareDocumentReviewScreenState
    extends ConsumerState<ShareDocumentReviewScreen> {
  final _formKey = GlobalKey<FormState>();
  final _amountController = TextEditingController();
  final _merchantController = TextEditingController();
  final _notesController = TextEditingController();

  DateTime _selectedDate = DateTime.now();
  String? _selectedTime;
  Category? _selectedCategory;
  Subcategory? _selectedSubcategory;
  Person? _selectedPerson;
  ExpenseClassification _classification = ExpenseClassification.required;
  final PaymentMethod _paymentMethod = PaymentMethod.cash;

  List<String> _attachedFilePaths = [];
  List<OcrLineItem> _extractedItems = [];
  Set<int> _selectedItemIndices = {};
  bool _isScanning = false;
  bool _autoAddExpenses = true;
  int _remainingOcrToday = FeatureQuotaService.freeMaxOcrImagesPerDay;
  String? _rejectionMessage;
  String? _lastRawOcrText;

  @override
  void initState() {
    super.initState();
    _selectedDate = DateTime.now();
    _refreshOcrQuota();
    if (widget.sharedImagePath != null && widget.sharedImagePath!.isNotEmpty) {
      _attachedFilePaths = [widget.sharedImagePath!];
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _runOcrScan();
      });
    }
  }

  Future<void> _refreshOcrQuota() async {
    final isSubscribed = ref.read(monthlyBackupBillingProvider).active;
    final rem = await FeatureQuotaService.remainingOcrToday(
      isSubscribed: isSubscribed,
    );
    if (mounted) {
      setState(
        () => _remainingOcrToday =
            rem ?? FeatureQuotaService.freeMaxOcrImagesPerDay,
      );
    }
  }

  Future<void> _showOcrQuotaLimitDialog() async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.workspace_premium, color: Colors.amber),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                'Daily OCR Limit Reached',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        content: const Text(
          'Free accounts include 1 receipt image scan and 1 voice expense (10 sec) per day.\n\n'
          'Subscribe to unlock Unlimited receipt OCR scans, 10 voice expenses/day (10 sec each), Daily Cloud Backup, and an Ad-Free experience.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Not Now'),
          ),
          FilledButton.icon(
            onPressed: () {
              Navigator.pop(ctx);
              context.go('/more');
            },
            icon: const Icon(Icons.star, size: 16),
            label: const Text('Subscribe'),
          ),
        ],
      ),
    );
  }

  Future<void> _addReceiptSection(
    String sourceName,
    String fileName, {
    bool triggerAutoScan = false,
  }) async {
    if (!OcrScannerService.isSupportedFileType(fileName)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Unsupported file format ($fileName). Only JPG, PNG, WEBP, HEIC, or PDF files are supported.',
          ),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() {
      _rejectionMessage = null;
      _attachedFilePaths.add(fileName);
    });

    if (triggerAutoScan) {
      await _runOcrScan();
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Added Section ${_attachedFilePaths.length} ($sourceName). Tap "Run OCR Scan" when done.',
          ),
        ),
      );
    }
  }

  Future<void> _pickFromCamera({bool forceAutoScan = false}) async {
    if (_isScanning) return;
    try {
      final picker = ImagePicker();
      final image = await picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 92,
      );
      if (image != null && mounted) {
        final shouldScan = forceAutoScan || _attachedFilePaths.isEmpty;
        await _addReceiptSection(
          'Camera Photo',
          image.path,
          triggerAutoScan: shouldScan,
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Camera error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _pickFromGallery() async {
    if (_isScanning) return;
    try {
      final wasEmpty = _attachedFilePaths.isEmpty;
      final picker = ImagePicker();
      final images = await picker.pickMultiImage(imageQuality: 92);
      if (images.isNotEmpty && mounted) {
        for (final img in images) {
          await _addReceiptSection('Gallery Image', img.path);
        }
        if (wasEmpty && mounted) {
          await _runOcrScan();
        }
      } else {
        final single = await picker.pickImage(
          source: ImageSource.gallery,
          imageQuality: 92,
        );
        if (single != null && mounted) {
          await _addReceiptSection(
            'Gallery Image',
            single.path,
            triggerAutoScan: wasEmpty,
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Gallery error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _pickDocumentFile() async {
    if (_isScanning) return;
    try {
      final wasEmpty = _attachedFilePaths.isEmpty;
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png', 'webp', 'heic'],
        allowMultiple: true,
      );
      if (result != null && result.files.isNotEmpty && mounted) {
        var added = 0;
        for (final file in result.files) {
          if (file.path != null) {
            await _addReceiptSection('Document File', file.path!);
            added++;
          }
        }
        if (wasEmpty && added > 0 && mounted) {
          await _runOcrScan();
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('File picker error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _removeSection(int index) {
    setState(() {
      _attachedFilePaths.removeAt(index);
      if (_attachedFilePaths.isEmpty) {
        _extractedItems = [];
        _selectedItemIndices.clear();
        _lastRawOcrText = null;
      }
    });
  }

  void _resetForNewScan() {
    setState(() {
      _attachedFilePaths = [];
      _extractedItems = [];
      _selectedItemIndices.clear();
      _amountController.clear();
      _merchantController.clear();
      _notesController.clear();
      _selectedTime = null;
      _rejectionMessage = null;
      _lastRawOcrText = null;
    });
  }

  @override
  void dispose() {
    _amountController.dispose();
    _merchantController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _saveSingleExpense() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedCategory == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select a category for this receipt'),
        ),
      );
      return;
    }

    final amount = double.tryParse(_amountController.text) ?? 0.0;
    final nowStr = DateTime.now().toIso8601String();
    final dateIso = DateFormatters.formatDateIso(_selectedDate);
    final primaryPath =
        _attachedFilePaths.isNotEmpty ? _attachedFilePaths.first : '';

    final receiptUuid = const Uuid().v4();
    final receipt = Receipt(
      uuid: receiptUuid,
      imagePath: primaryPath,
      rawOcrText: _lastRawOcrText,
      merchant: _merchantController.text.trim().isNotEmpty
          ? _merchantController.text.trim()
          : null,
      detectedTotal: amount,
      detectedDate: dateIso,
      scanDate: dateIso,
      createdAt: nowStr,
    );

    final savedReceipt =
        await ref.read(receiptRepositoryProvider).saveReceipt(receipt);

    final expense = Expense(
      uuid: const Uuid().v4(),
      amount: amount,
      currency: CurrencyFormatters.defaultCurrency,
      categoryId: _selectedCategory!.id,
      subcategoryId: _selectedSubcategory?.id,
      personId: _selectedPerson?.uuid,
      classification: _classification,
      expenseDate: dateIso,
      expenseTime: _selectedTime,
      createdAt: nowStr,
      updatedAt: nowStr,
      merchant: _merchantController.text.trim().isNotEmpty
          ? _merchantController.text.trim()
          : null,
      paymentMethod: _paymentMethod,
      receiptId: savedReceipt.uuid,
      notes: _notesController.text.trim().isNotEmpty
          ? _notesController.text.trim()
          : 'Attached receipt image(s)',
    );

    await ref.read(expenseNotifierProvider.notifier).addExpense(expense);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Receipt slip & expense saved successfully!'),
          backgroundColor: Colors.green,
        ),
      );
      context.pop();
    }
  }

  Future<void> _showEditItemDialog(int index) async {
    final item = _extractedItems[index];
    final nameCtrl = TextEditingController(text: item.name);
    final amtCtrl = TextEditingController(text: item.amount.toStringAsFixed(2));
    final qtyCtrl = TextEditingController(text: item.quantity.toString());

    final categories = ref.read(categoriesListProvider).valueOrNull ?? [];
    Category? chosenCat;
    if (categories.isNotEmpty) {
      if (item.categoryId != null &&
          categories.any((c) => c.id == item.categoryId)) {
        chosenCat = categories.firstWhere((c) => c.id == item.categoryId);
      } else {
        chosenCat = _selectedCategory ?? categories.first;
      }
    }

    Subcategory? chosenSub;
    if (chosenCat != null && item.subcategoryId != null) {
      for (final s in chosenCat.subcategories) {
        if (s.id == item.subcategoryId) {
          chosenSub = s;
          break;
        }
      }
    }

    ExpenseClassification chosenClass = item.classification;
    final people = ref.read(peopleListProvider).valueOrNull ?? [];
    Person? chosenPerson;
    if (item.personId != null && people.any((p) => p.uuid == item.personId)) {
      chosenPerson = people.firstWhere((p) => p.uuid == item.personId);
    } else {
      chosenPerson = _selectedPerson;
    }

    await showDialog<void>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final subs = chosenCat?.subcategories ?? const <Subcategory>[];
            return AlertDialog(
              title: const Row(
                children: [
                  Icon(Icons.edit_note, color: AppTheme.primaryColor),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Edit Item Details',
                      style:
                          TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      controller: nameCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Item Name',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: amtCtrl,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            decoration: InputDecoration(
                              labelText:
                                  'Price (${CurrencyFormatters.defaultCurrency})',
                              border: const OutlineInputBorder(),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            controller: qtyCtrl,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: 'Quantity',
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    const Text(
                      'Expense Classification:',
                      style:
                          TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      children: ExpenseClassification.values.map((cls) {
                        final isSelected = chosenClass == cls;
                        return ChoiceChip(
                          label: Text(
                            cls == ExpenseClassification.urgent
                                ? 'Urgent'
                                : cls == ExpenseClassification.required
                                    ? 'Required'
                                    : cls == ExpenseClassification.optional
                                        ? 'Optional'
                                        : 'Lost',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: isSelected
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                              color: isSelected ? Colors.white : Colors.black87,
                            ),
                          ),
                          selected: isSelected,
                          selectedColor: cls == ExpenseClassification.urgent
                              ? Colors.deepOrange.shade700
                              : cls == ExpenseClassification.required
                                  ? Colors.red.shade700
                                  : cls == ExpenseClassification.optional
                                      ? Colors.amber.shade800
                                      : Colors.purple.shade700,
                          onSelected: (val) {
                            if (val) setDialogState(() => chosenClass = cls);
                          },
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 14),
                    if (categories.isNotEmpty) ...[
                      DropdownButtonFormField<Category>(
                        key: ValueKey('dlg_cat_${chosenCat?.id}'),
                        initialValue: chosenCat,
                        decoration: const InputDecoration(
                          labelText: 'Category for this item',
                          border: OutlineInputBorder(),
                        ),
                        items: categories
                            .map((c) =>
                                DropdownMenuItem(value: c, child: Text(c.name)))
                            .toList(),
                        onChanged: (cat) {
                          setDialogState(() {
                            chosenCat = cat;
                            chosenSub = null;
                            if (cat != null) {
                              chosenClass = cat.defaultClassification;
                            }
                          });
                        },
                      ),
                      const SizedBox(height: 12),
                    ],
                    if (subs.isNotEmpty) ...[
                      DropdownButtonFormField<Subcategory?>(
                        key: ValueKey('dlg_sub_${chosenCat?.id}_${chosenSub?.id}'),
                        initialValue: chosenSub,
                        decoration: const InputDecoration(
                          labelText: 'Subcategory',
                          border: OutlineInputBorder(),
                        ),
                        items: [
                          const DropdownMenuItem<Subcategory?>(
                            value: null,
                            child: Text('General'),
                          ),
                          ...subs.map((s) => DropdownMenuItem<Subcategory?>(
                                value: s,
                                child: Text(s.name),
                              )),
                        ],
                        onChanged: (sub) {
                          setDialogState(() {
                            chosenSub = sub;
                            if (sub != null) {
                              chosenClass = sub.defaultClassification;
                            }
                          });
                        },
                      ),
                      const SizedBox(height: 12),
                    ],
                    DropdownButtonFormField<Person?>(
                      key: ValueKey('dlg_person_${chosenPerson?.uuid}'),
                      initialValue: chosenPerson,
                      decoration: const InputDecoration(
                        labelText: 'Person / Family Member',
                        border: OutlineInputBorder(),
                      ),
                      items: [
                        const DropdownMenuItem<Person?>(
                          value: null,
                          child: Text('General Household'),
                        ),
                        ...people.map(
                          (p) => DropdownMenuItem<Person?>(
                            value: p,
                            child: Text(p.name),
                          ),
                        ),
                      ],
                      onChanged: (p) {
                        setDialogState(() => chosenPerson = p);
                      },
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Cancel'),
                ),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryColor,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: () {
                    final newName = nameCtrl.text.trim();
                    final newAmt = double.tryParse(amtCtrl.text) ?? item.amount;
                    final newQty =
                        double.tryParse(qtyCtrl.text) ?? item.quantity;
                    if (newName.isNotEmpty) {
                      setState(() {
                        _extractedItems[index] = item.copyWith(
                          name: newName,
                          amount: newAmt,
                          quantity: newQty,
                          categoryId: chosenCat?.id,
                          categoryName: chosenCat?.name,
                          subcategoryId: chosenSub?.id,
                          subcategoryName: chosenSub?.name,
                          classification: chosenClass,
                          personId: chosenPerson?.uuid,
                        );
                      });
                    }
                    Navigator.pop(ctx);
                  },
                  icon: const Icon(Icons.check, size: 16),
                  label: const Text('Save Changes'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<List<String>> _persistItemsAsExpenses(
    List<OcrLineItem> items, {
    required List<Category> categories,
    String? timeString,
  }) async {
    final nowStr = DateTime.now().toIso8601String();
    final dateIso = DateFormatters.formatDateIso(_selectedDate);
    final totalSum =
        items.fold(0.0, (sum, item) => sum + (item.amount * item.quantity));
    final primaryPath =
        _attachedFilePaths.isNotEmpty ? _attachedFilePaths.first : '';

    final receipt = Receipt(
      uuid: const Uuid().v4(),
      imagePath: primaryPath,
      rawOcrText: _lastRawOcrText,
      merchant: _merchantController.text.trim().isNotEmpty
          ? _merchantController.text.trim()
          : null,
      detectedTotal: totalSum,
      detectedDate: dateIso,
      scanDate: dateIso,
      createdAt: nowStr,
    );

    final savedReceipt =
        await ref.read(receiptRepositoryProvider).saveReceipt(receipt);

    final fallbackCategoryId = _selectedCategory?.id ??
        (categories.isNotEmpty ? categories.first.id : 'cat_other');
    final currency = CurrencyFormatters.defaultCurrency;
    final addedUuids = <String>[];

    for (final item in items) {
      final uuid = const Uuid().v4();
      final expense = Expense(
        uuid: uuid,
        amount: item.amount * item.quantity,
        currency: currency,
        categoryId: item.categoryId ?? fallbackCategoryId,
        subcategoryId: item.subcategoryId ?? _selectedSubcategory?.id,
        personId: item.personId ?? _selectedPerson?.uuid,
        classification: item.classification,
        expenseDate: dateIso,
        expenseTime: timeString ?? _selectedTime,
        createdAt: nowStr,
        updatedAt: nowStr,
        merchant: _merchantController.text.trim().isNotEmpty
            ? _merchantController.text.trim()
            : null,
        paymentMethod: _paymentMethod,
        receiptId: savedReceipt.uuid,
        notes: '${item.name} (Qty: ${item.quantity}) - OCR Receipt Item',
      );
      await ref.read(expenseNotifierProvider.notifier).addExpense(expense);
      addedUuids.add(uuid);
    }

    return addedUuids;
  }

  Future<void> _saveBatchItemizedExpenses() async {
    if (_selectedCategory == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a category first.')),
      );
      return;
    }

    final selectedItems =
        _selectedItemIndices.map((idx) => _extractedItems[idx]).toList();
    if (selectedItems.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select at least 1 item for batch import.'),
        ),
      );
      return;
    }

    final categories = ref.read(categoriesListProvider).valueOrNull ?? [];
    final totalSum = selectedItems.fold(
      0.0,
      (sum, item) => sum + (item.amount * item.quantity),
    );
    await _persistItemsAsExpenses(selectedItems, categories: categories);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Added ${selectedItems.length} item(s) to related expenses (${CurrencyFormatters.defaultCurrency} ${totalSum.toStringAsFixed(2)})!',
          ),
          backgroundColor: Colors.green,
        ),
      );
      context.pop();
    }
  }

  Future<void> _showRejectedImageDialog(UnreadableReceiptException error) async {
    setState(() {
      _attachedFilePaths = [];
      _extractedItems = [];
      _selectedItemIndices.clear();
      _amountController.clear();
      _rejectionMessage = error.message;
      _lastRawOcrText = null;
    });

    if (!mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.error_outline, color: Colors.red, size: 28),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'Image Rejected — Not Clear Enough',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              error.message,
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
            ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.orange.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.lightbulb_outline,
                      color: Colors.orange, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      error.tip,
                      style: const TextStyle(fontSize: 12, height: 1.4),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          OutlinedButton.icon(
            onPressed: () {
              Navigator.pop(ctx);
              _pickFromGallery();
            },
            icon: const Icon(Icons.photo_library, size: 16),
            label: const Text('Gallery'),
          ),
          FilledButton.icon(
            onPressed: () {
              Navigator.pop(ctx);
              _pickFromCamera(forceAutoScan: true);
            },
            icon: const Icon(Icons.camera_alt, size: 16),
            label: const Text('Retake Photo'),
          ),
        ],
      ),
    );
  }

  Future<void> _showAutoAddedDialog({
    required List<OcrLineItem> addedItems,
    required List<String> addedUuids,
    required double totalSum,
  }) async {
    if (!mounted) return;
    final curr = CurrencyFormatters.defaultCurrency;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.check_circle, color: Colors.green, size: 28),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'Auto-Added to Expenses',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${addedItems.length} item(s) matched & saved ($curr ${totalSum.toStringAsFixed(2)}):',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 10),
                ...addedItems.map((item) {
                  final catLabel = item.subcategoryName != null
                      ? '${item.categoryName ?? item.categoryId} › ${item.subcategoryName}'
                      : (item.categoryName ?? item.categoryId ?? 'Other');
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                item.name,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13,
                                ),
                              ),
                              Text(
                                catLabel,
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.grey[700],
                                ),
                              ),
                            ],
                          ),
                        ),
                        Text(
                          '$curr ${(item.amount * item.quantity).toStringAsFixed(2)}',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.teal,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  );
                }),
              ],
            ),
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
                setState(() => _autoAddExpenses = false);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(
                      'Undone — edit items below and tap Import when ready.',
                    ),
                  ),
                );
              }
            },
            child: const Text('Undo & Edit'),
          ),
          OutlinedButton.icon(
            onPressed: () {
              Navigator.pop(ctx);
              _resetForNewScan();
              _pickFromCamera(forceAutoScan: true);
            },
            icon: const Icon(Icons.camera_alt, size: 16),
            label: const Text('Scan Another'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              if (mounted) context.pop();
            },
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }

  Future<void> _runOcrScan() async {
    if (_isScanning) return;
    if (_attachedFilePaths.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please take a receipt photo or pick an image first.'),
        ),
      );
      return;
    }

    final isSubscribed = ref.read(monthlyBackupBillingProvider).active;
    final allowed = await FeatureQuotaService.canUseOcr(
      isSubscribed: isSubscribed,
    );
    if (!allowed) {
      if (mounted) await _showOcrQuotaLimitDialog();
      return;
    }

    setState(() {
      _isScanning = true;
      _rejectionMessage = null;
    });

    try {
      final categories = await ref
          .read(categoriesListProvider.future)
          .catchError((_) => <Category>[]);

      final ocrResult = await OcrScannerService.scanMultipleReceipts(
        _attachedFilePaths,
        availableCategories: categories,
      );

      // Count OCR usage only after a clear, valid receipt is parsed
      await FeatureQuotaService.recordOcrUsage();
      await _refreshOcrQuota();

      if (!mounted) return;

      Category? matchingCat;
      if (categories.isNotEmpty) {
        matchingCat = categories.firstWhere(
          (c) => c.id == ocrResult.suggestedCategoryId,
          orElse: () => categories.first,
        );
      }

      Subcategory? matchingSub;
      if (matchingCat != null && ocrResult.suggestedSubcategoryId != null) {
        for (final s in matchingCat.subcategories) {
          if (s.id == ocrResult.suggestedSubcategoryId) {
            matchingSub = s;
            break;
          }
        }
      }

      setState(() {
        _extractedItems = ocrResult.lineItems;
        _selectedItemIndices = Set.from(
          List.generate(ocrResult.lineItems.length, (i) => i),
        );
        _amountController.text = ocrResult.totalAmount.toStringAsFixed(2);
        if (ocrResult.merchant != null && ocrResult.merchant!.isNotEmpty) {
          _merchantController.text = ocrResult.merchant!;
        }
        if (ocrResult.fullDateTime != null) {
          _selectedDate = ocrResult.fullDateTime!;
        }
        _selectedTime = ocrResult.timeString;
        _notesController.text =
            'OCR Items: ${ocrResult.lineItems.map((e) => e.name).join(', ')}';
        _lastRawOcrText = ocrResult.rawText;
        _selectedCategory = matchingCat;
        _selectedSubcategory = matchingSub;
        if (matchingSub != null) {
          _classification = matchingSub.defaultClassification;
        } else if (matchingCat != null) {
          _classification = matchingCat.defaultClassification;
        }
      });

      if (_autoAddExpenses && ocrResult.lineItems.isNotEmpty) {
        final totalSum = ocrResult.lineItems.fold(
          0.0,
          (sum, item) => sum + (item.amount * item.quantity),
        );
        final addedUuids = await _persistItemsAsExpenses(
          ocrResult.lineItems,
          categories: categories,
          timeString: ocrResult.timeString,
        );
        if (mounted) {
          setState(() => _isScanning = false);
          await _showAutoAddedDialog(
            addedItems: ocrResult.lineItems,
            addedUuids: addedUuids,
            totalSum: totalSum,
          );
        }
        return;
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'OCR Extracted ${ocrResult.lineItems.length} item(s) · Total ${CurrencyFormatters.defaultCurrency} ${ocrResult.totalAmount.toStringAsFixed(2)}',
            ),
            backgroundColor: Colors.teal,
          ),
        );
      }
    } on UnreadableReceiptException catch (e) {
      if (mounted) {
        await _showRejectedImageDialog(e);
      }
    } on UnsupportedFileFormatException catch (e) {
      if (mounted) {
        setState(() => _rejectionMessage = e.message);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.message),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error scanning receipt: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isScanning = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final categoriesAsync = ref.watch(categoriesListProvider);
    final peopleAsync = ref.watch(peopleListProvider);
    final isSubscribed =
        ref.watch(monthlyBackupBillingProvider.select((s) => s.active));
    final curr = CurrencyFormatters.defaultCurrency;

    final selectedItemsCount = _selectedItemIndices.length;
    final selectedItemsSum = _selectedItemIndices.fold(0.0, (sum, idx) {
      final item = _extractedItems[idx];
      return sum + (item.amount * item.quantity);
    });

    return Scaffold(
      appBar: AppBar(
        title: const Text('Scan Receipt to Expenses'),
        actions: [
          IconButton(
            icon: const Icon(Icons.mic_rounded),
            tooltip: 'Voice to Expense (10s)',
            onPressed: () => showVoiceExpenseSheet(context),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 1. Receipt Image Preview / Capture Box
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Theme.of(context)
                      .colorScheme
                      .surfaceContainerHighest
                      .withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: AppTheme.primaryColor.withValues(alpha: 0.3),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Receipt Image(s) (${_attachedFilePaths.length})',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: isSubscribed
                                ? Colors.green.withValues(alpha: 0.14)
                                : Colors.orange.withValues(alpha: 0.14),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            isSubscribed
                                ? 'Subscribed: Unlimited OCR'
                                : 'Free: $_remainingOcrToday/1 scan left today',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: isSubscribed
                                  ? Colors.green.shade800
                                  : Colors.orange.shade900,
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (_attachedFilePaths.length > 1)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Chip(
                          visualDensity: VisualDensity.compact,
                          backgroundColor: Colors.teal.withValues(alpha: 0.15),
                          label: Text(
                            'Long Slip (${_attachedFilePaths.length} Parts)',
                            style: const TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: Colors.teal,
                            ),
                          ),
                        ),
                      ),
                    const SizedBox(height: 10),
                    if (_attachedFilePaths.isEmpty)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                          vertical: 20,
                          horizontal: 12,
                        ),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.surface,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: Colors.grey.withValues(alpha: 0.3),
                          ),
                        ),
                        child: const Column(
                          children: [
                            Icon(
                              Icons.document_scanner_outlined,
                              size: 40,
                              color: AppTheme.primaryColor,
                            ),
                            SizedBox(height: 8),
                            Text(
                              'Take a clear receipt photo to auto-scan and add items to your related expenses.',
                              textAlign: TextAlign.center,
                              style: TextStyle(fontSize: 12),
                            ),
                          ],
                        ),
                      )
                    else
                      SizedBox(
                        height: 140,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          itemCount: _attachedFilePaths.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(width: 10),
                          itemBuilder: (context, index) {
                            final path = _attachedFilePaths[index];
                            final fileExists = File(path).existsSync();
                            return Container(
                              width: 110,
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: Colors.grey.shade300),
                              ),
                              child: Stack(
                                children: [
                                  Column(
                                    children: [
                                      Expanded(
                                        child: fileExists
                                            ? ClipRRect(
                                                borderRadius:
                                                    const BorderRadius.vertical(
                                                  top: Radius.circular(9),
                                                ),
                                                child: Image.file(
                                                  File(path),
                                                  width: double.infinity,
                                                  fit: BoxFit.cover,
                                                ),
                                              )
                                            : Container(
                                                color: Colors.grey.shade100,
                                                child: const Center(
                                                  child: Icon(
                                                    Icons.receipt_long,
                                                    color:
                                                        AppTheme.primaryColor,
                                                    size: 36,
                                                  ),
                                                ),
                                              ),
                                      ),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          vertical: 4,
                                        ),
                                        width: double.infinity,
                                        color: Colors.grey.shade100,
                                        child: Text(
                                          'Part ${index + 1}',
                                          textAlign: TextAlign.center,
                                          style: const TextStyle(
                                            fontSize: 10,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  Positioned(
                                    top: 4,
                                    right: 4,
                                    child: InkWell(
                                      onTap: () => _removeSection(index),
                                      child: CircleAvatar(
                                        radius: 11,
                                        backgroundColor:
                                            Colors.black.withValues(alpha: 0.6),
                                        child: const Icon(
                                          Icons.close,
                                          size: 12,
                                          color: Colors.white,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ),
                    const SizedBox(height: 12),
                    Wrap(
                      alignment: WrapAlignment.center,
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            visualDensity: VisualDensity.compact,
                            backgroundColor: Colors.teal,
                            foregroundColor: Colors.white,
                          ),
                          onPressed: _isScanning
                              ? null
                              : () => _pickFromCamera(forceAutoScan: false),
                          icon: const Icon(Icons.add_a_photo, size: 14),
                          label: Text(
                            _attachedFilePaths.isEmpty
                                ? 'Scan Camera Photo'
                                : '+ Next Section (Camera)',
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            visualDensity: VisualDensity.compact,
                          ),
                          onPressed: _isScanning ? null : _pickFromGallery,
                          icon: const Icon(Icons.photo_library, size: 14),
                          label: const Text('Gallery'),
                        ),
                        OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            visualDensity: VisualDensity.compact,
                          ),
                          onPressed: _isScanning ? null : _pickDocumentFile,
                          icon: const Icon(Icons.picture_as_pdf, size: 14),
                          label: const Text('PDF File'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Tip: Place receipt flat in good light so all items and total are clearly visible. Blurry or cut-off photos are automatically rejected.',
                      style: TextStyle(
                        fontSize: 10,
                        color: AppTheme.primaryColor,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),

              if (_rejectionMessage != null) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.red.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.red.shade300),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.warning_amber_rounded,
                          color: Colors.red),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          _rejectionMessage!,
                          style: const TextStyle(
                            color: Colors.red,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed: () => _pickFromCamera(forceAutoScan: true),
                        child: const Text('Retake'),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 16),

              // 2. OCR Controls & Auto-Add Switch
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.teal.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppTheme.primaryColor),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Row(
                      children: [
                        Icon(
                          Icons.document_scanner,
                          color: AppTheme.primaryColor,
                        ),
                        SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Smart Receipt OCR & Auto-Categorization',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ],
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      title: const Text(
                        'Auto-add items to related expenses',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      subtitle: const Text(
                        'Automatically saves clear items under matching categories & subcategories.',
                        style: TextStyle(fontSize: 11),
                      ),
                      value: _autoAddExpenses,
                      onChanged: _isScanning
                          ? null
                          : (val) => setState(() => _autoAddExpenses = val),
                    ),
                    if (_isScanning)
                      const Padding(
                        padding: EdgeInsets.only(bottom: 10),
                        child: LinearProgressIndicator(),
                      ),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.primaryColor,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 10),
                        ),
                        onPressed: _isScanning ? null : _runOcrScan,
                        icon: const Icon(Icons.bolt, size: 16),
                        label: Text(
                          _isScanning ? 'Scanning Receipt...' : 'Run OCR Scan',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // 3. Extracted Itemized Slip Items
              if (_extractedItems.isNotEmpty) ...[
                Card(
                  elevation: 2,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(12.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              'Extracted Receipt Items',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                                color: AppTheme.primaryColor,
                              ),
                            ),
                            Row(
                              children: [
                                Checkbox(
                                  value: _selectedItemIndices.length ==
                                      _extractedItems.length,
                                  onChanged: (val) {
                                    setState(() {
                                      if (val == true) {
                                        _selectedItemIndices = Set.from(
                                          List.generate(
                                            _extractedItems.length,
                                            (i) => i,
                                          ),
                                        );
                                      } else {
                                        _selectedItemIndices.clear();
                                      }
                                    });
                                  },
                                ),
                                const Text(
                                  'Select All',
                                  style: TextStyle(fontSize: 12),
                                ),
                              ],
                            ),
                          ],
                        ),
                        const Divider(),
                        ...List.generate(_extractedItems.length, (index) {
                          final item = _extractedItems[index];
                          final isSelected =
                              _selectedItemIndices.contains(index);
                          final qtyText =
                              item.quantity == item.quantity.roundToDouble()
                                  ? item.quantity.toInt().toString()
                                  : item.quantity.toString();
                          final catChipLabel = item.subcategoryName != null
                              ? '${item.categoryName ?? item.categoryId} › ${item.subcategoryName}'
                              : (item.categoryName ?? item.categoryId);
                          return InkWell(
                            onTap: () => _showEditItemDialog(index),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 4.0),
                              child: Row(
                                children: [
                                  Checkbox(
                                    value: isSelected,
                                    onChanged: (bool? val) {
                                      setState(() {
                                        if (val == true) {
                                          _selectedItemIndices.add(index);
                                        } else {
                                          _selectedItemIndices.remove(index);
                                        }
                                      });
                                    },
                                  ),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Expanded(
                                              child: Text(
                                                item.name,
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.w600,
                                                  fontSize: 13,
                                                ),
                                              ),
                                            ),
                                            const Icon(
                                              Icons.edit_outlined,
                                              size: 16,
                                              color: AppTheme.primaryColor,
                                            ),
                                          ],
                                        ),
                                        Text(
                                          'Qty: $qtyText  •  $curr ${item.amount.toStringAsFixed(2)} each',
                                          style: const TextStyle(
                                            fontSize: 11,
                                            color: Colors.grey,
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Wrap(
                                          spacing: 4,
                                          children: [
                                            Chip(
                                              visualDensity:
                                                  VisualDensity.compact,
                                              materialTapTargetSize:
                                                  MaterialTapTargetSize
                                                      .shrinkWrap,
                                              padding: EdgeInsets.zero,
                                              labelStyle: const TextStyle(
                                                fontSize: 9,
                                                fontWeight: FontWeight.bold,
                                              ),
                                              backgroundColor: item
                                                          .classification ==
                                                      ExpenseClassification
                                                          .urgent
                                                  ? Colors.deepOrange.shade100
                                                  : item.classification ==
                                                          ExpenseClassification
                                                              .required
                                                      ? Colors.red.shade100
                                                      : Colors.amber.shade100,
                                              label: Text(
                                                item.classification ==
                                                        ExpenseClassification
                                                            .urgent
                                                    ? 'Urgent'
                                                    : item.classification ==
                                                            ExpenseClassification
                                                                .required
                                                        ? 'Required'
                                                        : 'Optional',
                                              ),
                                            ),
                                            if (catChipLabel != null)
                                              Chip(
                                                visualDensity:
                                                    VisualDensity.compact,
                                                materialTapTargetSize:
                                                    MaterialTapTargetSize
                                                        .shrinkWrap,
                                                padding: EdgeInsets.zero,
                                                labelStyle: const TextStyle(
                                                  fontSize: 9,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                                backgroundColor:
                                                    Colors.teal.shade50,
                                                label: Text(catChipLabel),
                                              ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    '$curr ${(item.amount * item.quantity).toStringAsFixed(2)}',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: Colors.teal,
                                      fontSize: 13,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        }),
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.teal.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                '$selectedItemsCount items selected',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                ),
                              ),
                              Text(
                                'Subtotal: $curr ${selectedItemsSum.toStringAsFixed(2)}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Colors.teal,
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),
              ],

              // 4. Amount Field (For Total Single Expense)
              TextFormField(
                controller: _amountController,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                style:
                    const TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
                decoration: InputDecoration(
                  labelText: 'Grand Total Amount *',
                  prefixText: '$curr ',
                  prefixStyle: const TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                  ),
                  border: const OutlineInputBorder(),
                ),
                validator: (val) {
                  if (val == null || val.trim().isEmpty) {
                    return 'Enter amount from receipt';
                  }
                  final parsed = double.tryParse(val);
                  if (parsed == null || parsed <= 0) {
                    return 'Enter valid amount';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),

              // 5. Category & Subcategory Selection
              categoriesAsync.when(
                loading: () => const CircularProgressIndicator(),
                error: (e, _) => Text('Error: $e'),
                data: (categories) {
                  return Column(
                    children: [
                      DropdownButtonFormField<Category>(
                        key: ValueKey('main_cat_${_selectedCategory?.id}'),
                        initialValue: _selectedCategory,
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
                            _selectedSubcategory = null;
                            if (cat != null) {
                              _classification = cat.defaultClassification;
                            }
                          });
                        },
                      ),
                      if (_selectedCategory != null &&
                          _selectedCategory!.subcategories.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        DropdownButtonFormField<Subcategory?>(
                          key: ValueKey(
                            'main_sub_${_selectedCategory?.id}_${_selectedSubcategory?.id}',
                          ),
                          initialValue: _selectedSubcategory,
                          decoration: const InputDecoration(
                            labelText: 'Subcategory',
                            border: OutlineInputBorder(),
                          ),
                          items: [
                            const DropdownMenuItem<Subcategory?>(
                              value: null,
                              child: Text('General'),
                            ),
                            ..._selectedCategory!.subcategories.map((sub) {
                              return DropdownMenuItem<Subcategory?>(
                                value: sub,
                                child: Text(sub.name),
                              );
                            }),
                          ],
                          onChanged: (sub) {
                            setState(() {
                              _selectedSubcategory = sub;
                              if (sub != null) {
                                _classification = sub.defaultClassification;
                              }
                            });
                          },
                        ),
                      ],
                    ],
                  );
                },
              ),
              const SizedBox(height: 16),

              // 6. Person / Family Member Selector
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
                          const Flexible(
                            child: Text(
                              'Person / Family Member',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          TextButton.icon(
                            style: TextButton.styleFrom(
                              visualDensity: VisualDensity.compact,
                            ),
                            onPressed: () async {
                              final created =
                                  await showAddPersonDialog(context, ref);
                              if (created != null) {
                                setState(() => _selectedPerson = created);
                              }
                            },
                            icon: const Icon(Icons.person_add, size: 16),
                            label: const Text(
                              '+ Add New Member',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      DropdownButtonFormField<Person?>(
                        key: ValueKey('main_person_${_selectedPerson?.uuid}'),
                        initialValue: _selectedPerson,
                        decoration: const InputDecoration(
                          hintText: 'Select Family Member',
                          border: OutlineInputBorder(),
                        ),
                        items: [
                          const DropdownMenuItem<Person?>(
                            value: null,
                            child: Text('General Household'),
                          ),
                          ...people.map((p) {
                            return DropdownMenuItem<Person?>(
                              value: p,
                              child: Text(
                                '${p.name}${p.relationship != null ? ' (${p.relationship})' : ''}',
                              ),
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
              const SizedBox(height: 16),

              // Merchant Field
              TextFormField(
                controller: _merchantController,
                decoration: const InputDecoration(
                  labelText: 'Merchant / Institution Name',
                  border: OutlineInputBorder(),
                  hintText: 'e.g. Metro Cash & Carry, ABC School, Shell',
                ),
              ),
              const SizedBox(height: 24),

              if (_extractedItems.isNotEmpty) ...[
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.teal.shade700,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onPressed: _saveBatchItemizedExpenses,
                    icon: const Icon(Icons.dynamic_feed),
                    label: Text(
                      'BATCH IMPORT SELECTED $selectedItemsCount ITEMS AS EXPENSES',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
              ],

              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryColor,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: _saveSingleExpense,
                  icon: const Icon(Icons.check_circle_outline),
                  label: const Text(
                    'SAVE AS 1 TOTAL EXPENSE',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
