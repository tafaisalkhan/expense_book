import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:myexpence/core/theme/app_theme.dart';
import 'package:myexpence/core/utils/currency_formatters.dart';
import 'package:myexpence/core/utils/date_formatters.dart';
import 'package:myexpence/core/utils/network_helper.dart';
import 'package:myexpence/features/categories/domain/models/category.dart';
import 'package:myexpence/features/categories/presentation/providers/category_providers.dart';
import 'package:myexpence/features/expenses/domain/models/expense.dart';
import 'package:myexpence/features/expenses/domain/models/expense_classification.dart';
import 'package:myexpence/features/expenses/domain/models/payment_method.dart';
import 'package:myexpence/features/expenses/presentation/providers/expense_providers.dart';
import 'package:myexpence/features/people/domain/models/person.dart';
import 'package:myexpence/features/people/presentation/providers/people_providers.dart';
import 'package:myexpence/features/receipts/domain/models/receipt.dart';
import 'package:myexpence/core/providers/core_providers.dart';
import 'package:myexpence/features/document_scanner/domain/services/ocr_scanner_service.dart';
import 'package:myexpence/features/subscription/presentation/providers/subscription_providers.dart';
import 'package:uuid/uuid.dart';

class ShareDocumentReviewScreen extends ConsumerStatefulWidget {
  final String? sharedImagePath;

  const ShareDocumentReviewScreen({super.key, this.sharedImagePath});

  @override
  ConsumerState<ShareDocumentReviewScreen> createState() => _ShareDocumentReviewScreenState();
}

class _ShareDocumentReviewScreenState extends ConsumerState<ShareDocumentReviewScreen> {
  final _formKey = GlobalKey<FormState>();
  final _amountController = TextEditingController();
  final _merchantController = TextEditingController();
  final _notesController = TextEditingController();

  DateTime _selectedDate = DateTime.now();
  Category? _selectedCategory;
  Subcategory? _selectedSubcategory;
  Person? _selectedPerson;
  ExpenseClassification _classification = ExpenseClassification.required;
  PaymentMethod _paymentMethod = PaymentMethod.cash;

  List<String> _attachedFilePaths = ['assets/sample_receipt.png'];
  List<OcrLineItem> _extractedItems = [];
  Set<int> _selectedItemIndices = {};

  @override
  void initState() {
    super.initState();
    _selectedDate = DateTime.now();
    if (widget.sharedImagePath != null && widget.sharedImagePath!.isNotEmpty) {
      _attachedFilePaths = [widget.sharedImagePath!];
    } else {
      _attachedFilePaths = ['assets/sample_receipt.png'];
    }
  }

  void _addReceiptSection(String sourceName, String fileName) {
    if (!OcrScannerService.isSupportedFileType(fileName)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('⚠️ Unsupported file format ($fileName). Only Image files (JPG/PNG) and PDF documents are supported.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() {
      // If default asset placeholder is present, replace it with first real file
      if (_attachedFilePaths.length == 1 && _attachedFilePaths.first.startsWith('assets/')) {
        _attachedFilePaths = [fileName];
      } else {
        _attachedFilePaths.add(fileName);
      }
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Added Section ${_attachedFilePaths.length} ($sourceName). Tap "Run OCR Scan" when done.')),
    );
  }

  Future<void> _pickFromCamera() async {
    try {
      final picker = ImagePicker();
      final image = await picker.pickImage(source: ImageSource.camera);
      if (image != null) {
        _addReceiptSection('Camera Photo', image.path);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Camera error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _pickFromGallery() async {
    try {
      final picker = ImagePicker();
      final images = await picker.pickMultiImage();
      if (images.isNotEmpty) {
        for (final img in images) {
          _addReceiptSection('Gallery Image', img.path);
        }
      } else {
        // Fallback single pick if multi-pick returns empty
        final single = await picker.pickImage(source: ImageSource.gallery);
        if (single != null) {
          _addReceiptSection('Gallery Image', single.path);
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gallery error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _pickDocumentFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png', 'webp', 'heic'],
        allowMultiple: true,
      );
      if (result != null && result.files.isNotEmpty) {
        for (final file in result.files) {
          if (file.path != null) {
            _addReceiptSection('Document File', file.path!);
          }
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('File picker error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _removeSection(int index) {
    setState(() {
      _attachedFilePaths.removeAt(index);
      if (_attachedFilePaths.isEmpty) {
        _attachedFilePaths = ['assets/sample_receipt.png'];
      }
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
        const SnackBar(content: Text('Please select a category for this receipt')),
      );
      return;
    }

    final amount = double.tryParse(_amountController.text) ?? 0.0;
    final nowStr = DateTime.now().toIso8601String();
    final dateIso = DateFormatters.formatDateIso(_selectedDate);

    final primaryPath = _attachedFilePaths.isNotEmpty ? _attachedFilePaths.first : 'assets/sample_receipt.png';

    // Save Receipt entity to SQLite
    final receiptUuid = const Uuid().v4();
    final receipt = Receipt(
      uuid: receiptUuid,
      imagePath: primaryPath,
      merchant: _merchantController.text.trim().isNotEmpty ? _merchantController.text.trim() : null,
      detectedTotal: amount,
      scanDate: dateIso,
      createdAt: nowStr,
    );

    final savedReceipt = await ref.read(receiptRepositoryProvider).saveReceipt(receipt);

    // Create Expense linking receiptId
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
      receiptId: savedReceipt.uuid,
      notes: _notesController.text.trim().isNotEmpty ? _notesController.text.trim() : 'Attached receipt image(s)',
    );

    await ref.read(expenseNotifierProvider.notifier).addExpense(expense);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Receipt slip & single expense recorded successfully!')),
      );
      context.pop();
    }
  }

  Future<void> _showEditItemDialog(int index) async {
    final item = _extractedItems[index];
    final nameCtrl = TextEditingController(text: item.name);
    final amtCtrl = TextEditingController(text: item.amount.toStringAsFixed(2));
    final qtyCtrl = TextEditingController(text: item.quantity.toString());

    Category? chosenCat;
    ExpenseClassification chosenClass = item.classification;
    Person? chosenPerson;

    final categories = ref.read(categoriesListProvider).valueOrNull ?? [];
    if (item.categoryId != null) {
      chosenCat = categories.firstWhere(
        (c) => c.id == item.categoryId,
        orElse: () => _selectedCategory ?? (categories.isNotEmpty ? categories.first : const Category(id: 'cat_food', name: 'Food & Dining', icon: 'restaurant', sortOrder: 1)),
      );
    } else {
      chosenCat = _selectedCategory ?? (categories.isNotEmpty ? categories.first : null);
    }

    final people = ref.read(peopleListProvider).valueOrNull ?? [];
    if (item.personId != null && people.any((p) => p.uuid == item.personId)) {
      chosenPerson = people.firstWhere((p) => p.uuid == item.personId);
    } else {
      chosenPerson = _selectedPerson;
    }

    await showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Row(
                children: [
                  Icon(Icons.edit_note, color: AppTheme.primaryColor),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text('Edit Item Details', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
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
                      decoration: const InputDecoration(labelText: 'Item Name', border: OutlineInputBorder()),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: amtCtrl,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            decoration: const InputDecoration(labelText: 'Price (Rs)', border: OutlineInputBorder()),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            controller: qtyCtrl,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(labelText: 'Quantity', border: OutlineInputBorder()),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),

                    // Classification Selector (Urgent / Required / Optional)
                    const Text('Expense Classification:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      children: ExpenseClassification.values.map((cls) {
                        final isSelected = chosenClass == cls;
                        return ChoiceChip(
                          label: Text(
                            cls == ExpenseClassification.urgent
                                ? '⚠️ Urgent'
                                : cls == ExpenseClassification.required
                                ? '📌 Required (Need)'
                                : '🎉 Optional (Want)',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                              color: isSelected ? Colors.white : Colors.black87,
                            ),
                          ),
                          selected: isSelected,
                          selectedColor: cls == ExpenseClassification.urgent
                              ? Colors.deepOrange.shade700
                              : cls == ExpenseClassification.required
                              ? Colors.red.shade700
                              : Colors.amber.shade800,
                          onSelected: (val) {
                            if (val) setDialogState(() => chosenClass = cls);
                          },
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 14),

                    // Category Dropdown
                    if (categories.isNotEmpty) ...[
                      DropdownButtonFormField<Category>(
                        value: chosenCat,
                        decoration: const InputDecoration(labelText: 'Category for this item', border: OutlineInputBorder()),
                        items: categories.map((c) => DropdownMenuItem(value: c, child: Text(c.name))).toList(),
                        onChanged: (cat) {
                          setDialogState(() {
                            chosenCat = cat;
                            if (cat != null) chosenClass = cat.defaultClassification;
                          });
                        },
                      ),
                      const SizedBox(height: 12),
                    ],

                    // Person Dropdown
                    DropdownButtonFormField<Person?>(
                      value: chosenPerson,
                      decoration: const InputDecoration(labelText: 'Person / Family Member', border: OutlineInputBorder()),
                      items: [
                        const DropdownMenuItem<Person?>(value: null, child: Text('🏠 General Household')),
                        ...people.map((p) => DropdownMenuItem<Person?>(value: p, child: Text('👤 ${p.name}'))),
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
                  style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryColor, foregroundColor: Colors.white),
                  onPressed: () {
                    final newName = nameCtrl.text.trim();
                    final newAmt = double.tryParse(amtCtrl.text) ?? item.amount;
                    final newQty = double.tryParse(qtyCtrl.text) ?? item.quantity;
                    if (newName.isNotEmpty) {
                      setState(() {
                        _extractedItems[index] = item.copyWith(
                          name: newName,
                          amount: newAmt,
                          quantity: newQty,
                          categoryId: chosenCat?.id,
                          classification: chosenClass,
                          personId: chosenPerson?.uuid,
                        );
                      });
                    }
                    Navigator.pop(ctx);
                  },
                  icon: const Icon(Icons.check, size: 16),
                  label: const Text('Save Customization'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _saveBatchItemizedExpenses() async {
    if (_selectedCategory == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a category first.')),
      );
      return;
    }

    final selectedItems = _selectedItemIndices.map((idx) => _extractedItems[idx]).toList();
    if (selectedItems.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select at least 1 item for batch import.')),
      );
      return;
    }

    final nowStr = DateTime.now().toIso8601String();
    final dateIso = DateFormatters.formatDateIso(_selectedDate);
    final totalSum = selectedItems.fold(0.0, (sum, item) => sum + (item.amount * item.quantity));
    final primaryPath = _attachedFilePaths.isNotEmpty ? _attachedFilePaths.first : 'assets/sample_receipt.png';

    // Save Receipt entity to SQLite
    final receiptUuid = const Uuid().v4();
    final receipt = Receipt(
      uuid: receiptUuid,
      imagePath: primaryPath,
      merchant: _merchantController.text.trim().isNotEmpty ? _merchantController.text.trim() : null,
      detectedTotal: totalSum,
      scanDate: dateIso,
      createdAt: nowStr,
    );

    final savedReceipt = await ref.read(receiptRepositoryProvider).saveReceipt(receipt);

    // Create individual Expense for each selected item in batch
    for (final item in selectedItems) {
      final expense = Expense(
        uuid: const Uuid().v4(),
        amount: item.amount * item.quantity,
        categoryId: item.categoryId ?? _selectedCategory!.id,
        subcategoryId: item.subcategoryId ?? _selectedSubcategory?.id,
        personId: item.personId ?? _selectedPerson?.uuid,
        classification: item.classification,
        expenseDate: dateIso,
        createdAt: nowStr,
        updatedAt: nowStr,
        merchant: _merchantController.text.trim().isNotEmpty ? _merchantController.text.trim() : null,
        paymentMethod: _paymentMethod,
        receiptId: savedReceipt.uuid,
        notes: '${item.name} (Qty: ${item.quantity}) - Batch imported from receipt',
      );

      await ref.read(expenseNotifierProvider.notifier).addExpense(expense);
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('✅ Successfully imported ${selectedItems.length} expenses in batch! Total: Rs ${totalSum.toStringAsFixed(2)}'),
          backgroundColor: Colors.green,
        ),
      );
      context.pop();
    }
  }

  Future<void> _runOcrScan(BuildContext context) async {
    final isPremium = ref.read(isPremiumUserProvider);

    if (!isPremium) {
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        builder: (ctx) => Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.star, color: Colors.amber, size: 48),
              const SizedBox(height: 12),
              const Text(
                'OCR Receipt Scanning is a Paid Feature ⭐',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              const Text(
                'Upgrade to Premium or activate your 7-Day Free Trial to unlock automatic OCR scanning, merchant extraction, and batch receipt line item import.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryColor,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: () async {
                    Navigator.pop(ctx);
                    await ref.read(subscriptionProvider.notifier).startFreeTrial();
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('🎉 7-Day Free Trial Activated! Running OCR Scan now...'), backgroundColor: Colors.teal),
                      );
                      _runOcrScan(context);
                    }
                  },
                  icon: const Icon(Icons.flash_on),
                  label: const Text('Start 7-Day Free Trial (Free Instant Access)', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: OutlinedButton.icon(
                  onPressed: () {
                    Navigator.pop(ctx);
                    context.push('/paywall');
                  },
                  icon: const Icon(Icons.workspace_premium),
                  label: const Text('View Premium Plans & Upgrades', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ),
      );
      return;
    }

    final hasInternet = await NetworkHelper.hasInternetConnection();
    if (!hasInternet) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Internet not available right now. Please check your network connection and try again.'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    }

    try {
      final ocrResult = await OcrScannerService.scanMultipleReceipts(_attachedFilePaths);

      setState(() {
        _extractedItems = ocrResult.lineItems;
        _selectedItemIndices = Set.from(List.generate(ocrResult.lineItems.length, (i) => i));
        _amountController.text = ocrResult.totalAmount.toStringAsFixed(2);
        if (ocrResult.merchant != null && ocrResult.merchant!.isNotEmpty) {
          _merchantController.text = ocrResult.merchant!;
        }
        if (ocrResult.fullDateTime != null) {
          _selectedDate = ocrResult.fullDateTime!;
        }
        _notesController.text = 'OCR Items: ${ocrResult.lineItems.map((e) => e.name).join(', ')}';
      });

      final categories = ref.read(categoriesListProvider).valueOrNull ?? [];
      final matchingCat = categories.firstWhere(
        (c) => c.id == ocrResult.suggestedCategoryId,
        orElse: () => categories.isNotEmpty
            ? categories.first
            : const Category(id: 'cat_food', name: 'Food & Dining', icon: 'restaurant', sortOrder: 1),
      );

      setState(() {
        _selectedCategory = matchingCat;
        _classification = matchingCat.defaultClassification;
      });

      if (mounted) {
        final timeInfo = ocrResult.timeString != null ? ' Time: ${ocrResult.timeString}' : '';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('⚡ OCR Extracted (${ocrResult.pageCount} section[s]): Merchant "${ocrResult.merchant}", Total Rs ${ocrResult.totalAmount.toStringAsFixed(2)}, ${_extractedItems.length} items$timeInfo'),
            backgroundColor: Colors.teal,
          ),
        );
      }
    } on UnsupportedFileFormatException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('⚠️ ${e.message}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error scanning file: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isPremium = ref.watch(isPremiumUserProvider);
    final categoriesAsync = ref.watch(categoriesListProvider);
    final peopleAsync = ref.watch(peopleListProvider);

    final selectedItemsCount = _selectedItemIndices.length;
    final selectedItemsSum = _selectedItemIndices.fold(0.0, (sum, idx) {
      final item = _extractedItems[idx];
      return sum + (item.amount * item.quantity);
    });

    return Scaffold(
      appBar: AppBar(
        title: const Text('Share Receipt to MyExpense'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 1. Multi-Section Receipt Images Preview Box
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest.withOpacity(0.4),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppTheme.primaryColor.withOpacity(0.3)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          '📸 Receipt Image Section(s) (${_attachedFilePaths.length})',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                        ),
                        if (_attachedFilePaths.length > 1)
                          Chip(
                            visualDensity: VisualDensity.compact,
                            backgroundColor: Colors.teal.withOpacity(0.15),
                            label: Text('Long Slip (${_attachedFilePaths.length} Parts)', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.teal)),
                          ),
                      ],
                    ),
                    const SizedBox(height: 10),

                    // Horizontal List of Section Cards
                    SizedBox(
                      height: 140,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: _attachedFilePaths.length,
                        separatorBuilder: (_, __) => const SizedBox(width: 10),
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
                                              borderRadius: const BorderRadius.vertical(top: Radius.circular(9)),
                                              child: Image.file(
                                                File(path),
                                                width: double.infinity,
                                                fit: BoxFit.cover,
                                              ),
                                            )
                                          : Container(
                                              color: Colors.grey.shade100,
                                              child: const Center(child: Icon(Icons.receipt_long, color: AppTheme.primaryColor, size: 36)),
                                            ),
                                    ),
                                    Container(
                                      padding: const EdgeInsets.symmetric(vertical: 4),
                                      width: double.infinity,
                                      color: Colors.grey.shade100,
                                      child: Text(
                                        'Part ${index + 1}',
                                        textAlign: TextAlign.center,
                                        style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold),
                                      ),
                                    ),
                                  ],
                                ),
                                if (_attachedFilePaths.length > 1)
                                  Positioned(
                                    top: 4,
                                    right: 4,
                                    child: InkWell(
                                      onTap: () => _removeSection(index),
                                      child: CircleAvatar(
                                        radius: 11,
                                        backgroundColor: Colors.black.withOpacity(0.6),
                                        child: const Icon(Icons.close, size: 12, color: Colors.white),
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

                    // Non-Overflowing Multi-Section Attachment Buttons
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
                          onPressed: _pickFromCamera,
                          icon: const Icon(Icons.add_a_photo, size: 14),
                          label: const Text('+ Next Section (Camera)', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                        ),
                        OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(visualDensity: VisualDensity.compact),
                          onPressed: _pickFromGallery,
                          icon: const Icon(Icons.photo_library, size: 14),
                          label: const Text('+ Select Images'),
                        ),
                        OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(visualDensity: VisualDensity.compact),
                          onPressed: _pickDocumentFile,
                          icon: const Icon(Icons.picture_as_pdf, size: 14),
                          label: const Text('+ PDF File'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      '💡 Tip: For long receipts, take 2 or 3 photos (Top, Middle, Bottom). OCR will stitch all items and calculate total.',
                      style: TextStyle(fontSize: 10, color: AppTheme.primaryColor, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // 2. OCR Scan Action & Status Banner
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isPremium ? Colors.teal.withValues(alpha: 0.12) : Colors.amber.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: isPremium ? AppTheme.primaryColor : Colors.amber),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Icon(isPremium ? Icons.document_scanner : Icons.info_outline, color: isPremium ? AppTheme.primaryColor : Colors.amber),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            isPremium ? 'Intelligent OCR Text Parsing & Item Extractor' : 'Free Tier: Manual Details Entry',
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      isPremium
                          ? 'Tap "Run OCR Scan" to automatically extract total amount, merchant, and line items for batch or one-by-one import.'
                          : 'Your receipt photo is attached! Upgrade or enter details manually.',
                      style: const TextStyle(fontSize: 11),
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.primaryColor,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 10),
                        ),
                        onPressed: () => _runOcrScan(context),
                        icon: const Icon(Icons.bolt, size: 16),
                        label: const Text('Run OCR Scan', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // 3. Extracted Itemized Slip Items (Batch / One-by-One Selection)
              if (_extractedItems.isNotEmpty) ...[
                Card(
                  elevation: 2,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  child: Padding(
                    padding: const EdgeInsets.all(12.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              '🛒 Extracted Slip Items',
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: AppTheme.primaryColor),
                            ),
                            Row(
                              children: [
                                Checkbox(
                                  value: _selectedItemIndices.length == _extractedItems.length,
                                  onChanged: (val) {
                                    setState(() {
                                      if (val == true) {
                                        _selectedItemIndices = Set.from(List.generate(_extractedItems.length, (i) => i));
                                      } else {
                                        _selectedItemIndices.clear();
                                      }
                                    });
                                  },
                                ),
                                const Text('Select All', style: TextStyle(fontSize: 12)),
                              ],
                            ),
                          ],
                        ),
                        const Divider(),
                        ...List.generate(_extractedItems.length, (index) {
                          final item = _extractedItems[index];
                          final isSelected = _selectedItemIndices.contains(index);
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
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Expanded(
                                              child: Text(item.name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                                            ),
                                            const Icon(Icons.edit_outlined, size: 16, color: AppTheme.primaryColor),
                                          ],
                                        ),
                                        Text('Qty: ${item.quantity == item.quantity.roundToDouble() ? item.quantity.toInt() : item.quantity}  •  ${CurrencyFormatters.defaultCurrency} ${item.amount.toStringAsFixed(2)} each', style: const TextStyle(fontSize: 11, color: Colors.grey)),
                                        const SizedBox(height: 2),
                                        Wrap(
                                          spacing: 4,
                                          children: [
                                            Chip(
                                              visualDensity: VisualDensity.compact,
                                              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                              padding: EdgeInsets.zero,
                                              labelStyle: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold),
                                              backgroundColor: item.classification == ExpenseClassification.urgent
                                                  ? Colors.deepOrange.shade100
                                                  : item.classification == ExpenseClassification.required
                                                  ? Colors.red.shade100
                                                  : Colors.amber.shade100,
                                              label: Text(
                                                item.classification == ExpenseClassification.urgent
                                                    ? '⚠️ Urgent'
                                                    : item.classification == ExpenseClassification.required
                                                    ? '📌 Required'
                                                    : '🎉 Optional',
                                              ),
                                            ),
                                            if (item.categoryId != null)
                                              Chip(
                                                visualDensity: VisualDensity.compact,
                                                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                                padding: EdgeInsets.zero,
                                                labelStyle: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold),
                                                backgroundColor: Colors.teal.shade50,
                                                label: Text(item.categoryId!),
                                              ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    '${CurrencyFormatters.defaultCurrency} ${(item.amount * item.quantity).toStringAsFixed(2)}',
                                    style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.teal, fontSize: 13),
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
                            color: Colors.teal.withOpacity(0.08),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text('$selectedItemsCount items selected', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                              Text('Subtotal: Rs ${selectedItemsSum.toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.teal, fontSize: 13)),
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
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
                decoration: const InputDecoration(
                  labelText: 'Grand Total Amount *',
                  prefixText: 'Rs ',
                  prefixStyle: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
                  border: OutlineInputBorder(),
                ),
                validator: (val) {
                  if (val == null || val.trim().isEmpty) return 'Enter amount from receipt';
                  if (double.tryParse(val) == null || double.parse(val) <= 0) return 'Enter valid amount';
                  return null;
                },
              ),
              const SizedBox(height: 16),

              // 5. Category & Subcategory Selection
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
                            child: Text('Person / Family Member', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13), overflow: TextOverflow.ellipsis),
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

              // Import Buttons: Single Expense OR Batch Items Import
              if (_extractedItems.isNotEmpty) ...[
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.teal.shade700,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: _saveBatchItemizedExpenses,
                    icon: const Icon(Icons.dynamic_feed),
                    label: Text(
                      'BATCH IMPORT SELECTED $selectedItemsCount ITEMS AS EXPENSES',
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
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
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
