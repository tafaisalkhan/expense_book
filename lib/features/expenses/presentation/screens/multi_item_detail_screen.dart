import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:myexpence/core/theme/app_theme.dart';
import 'package:myexpence/core/utils/category_icon_helper.dart';
import 'package:myexpence/core/utils/currency_formatters.dart';
import 'package:myexpence/core/utils/math_evaluator.dart';
import 'package:myexpence/features/categories/domain/models/category.dart';
import 'package:myexpence/features/expenses/domain/models/expense_classification.dart';
import 'package:myexpence/features/people/domain/models/person.dart';
import 'package:myexpence/features/people/presentation/providers/people_providers.dart';

/// One selected item (e.g. "Flour", Rs 1200, "10 kg", unitPrice: 120,
/// classification: Required, person: Ahmed) that will be saved as its own expense row.
class MultiItemLine {
  final String name;
  final String? subcategoryId;
  final double amount;
  final String? quantity;
  final double? unitPrice;
  final ExpenseClassification classification;
  final String? personId;
  final String? personName;

  const MultiItemLine({
    required this.name,
    required this.subcategoryId,
    required this.amount,
    this.quantity,
    this.unitPrice,
    this.classification = ExpenseClassification.required,
    this.personId,
    this.personName,
  });

  String get displayName {
    final qty = quantity?.trim();
    String base;
    if (qty != null && qty.isNotEmpty && unitPrice != null && unitPrice! > 0) {
      final sym = CurrencyFormatters.defaultCurrency;
      final upStr = unitPrice == unitPrice!.roundToDouble()
          ? unitPrice!.toStringAsFixed(0)
          : unitPrice!.toStringAsFixed(2);
      base = '$name ($qty @ $sym $upStr)';
    } else if (qty != null && qty.isNotEmpty) {
      base = '$name ($qty)';
    } else {
      base = name;
    }

    if (personName != null && personName!.trim().isNotEmpty) {
      base = '$base • for ${personName!.trim()}';
    }
    return base;
  }
}

/// The result returned from [MultiItemDetailScreen] containing the selected
/// items and any updated target amount set by the user.
class MultiItemResult {
  final List<MultiItemLine> items;
  final double? targetTotal;

  const MultiItemResult({
    required this.items,
    this.targetTotal,
  });
}

/// Default grocery subcategory items.
const List<String> _defaultGroceryItems = [
  'Flour',
  'Rice',
  'Tea',
  'Sugar',
  'Dal / Pulses',
  'Salt',
  'Ghee',
  'Butter',
  'Cooking Oil',
  'Gram Flour (Besan)',
  'Chickpeas (Chana)',
  'Macaroni',
  'Noodles',
  'Biscuits',
  'Ketchup / Sauces',
  'Juice',
  'Mineral Water',
  'Surf / Detergent',
  'Soap',
  'Dishwash',
  'Shampoo',
  'Toothpaste',
  'Tissue',
];

/// Default daily food items.
const List<String> _defaultFoodItems = [
  'Milk',
  'Yogurt',
  'Bread',
  'Eggs',
  'Vegetables',
  'Fruits',
  'Meat',
  'Chicken',
  'Mutton & Fish',
  'Roti / Naan',
  'Snacks',
  'Tea & Coffee',
  'Restaurant & Fast Food',
  'Cold Drink / Beverage',
];

/// Standard units for item quantities.
const List<String> _commonUnits = [
  '',
  'kg',
  'g',
  'pcs',
  'pack',
  'liter',
  'ml',
  'box',
  'dozen',
  'bag',
  'meter',
];

bool isGroceryOnlyCategory(Category? c) {
  if (c == null) return false;
  final id = c.id.toLowerCase();
  final name = c.name.toLowerCase();
  return id.contains('grocer') || name.contains('grocer');
}

bool isFoodCategory(Category? c) {
  if (c == null) return false;
  final id = c.id.toLowerCase();
  final name = c.name.toLowerCase();
  return id.contains('food') || name.contains('food');
}

bool isMultiItemCategory(Category? c) {
  if (c == null) return false;
  return c.subcategories.isNotEmpty;
}

bool isGroceryCategory(Category? c) => isMultiItemCategory(c);

/// Helper to navigate to [MultiItemDetailScreen].
Future<MultiItemResult?> showMultiItemDetailScreen(
  BuildContext context, {
  required Category category,
  List<MultiItemLine> initial = const [],
  double? targetTotal,
}) {
  return Navigator.of(context).push<MultiItemResult>(
    MaterialPageRoute(
      builder: (_) => MultiItemDetailScreen(
        category: category,
        initial: initial,
        targetTotal: targetTotal,
      ),
    ),
  );
}

class MultiItemDetailScreen extends ConsumerStatefulWidget {
  final Category category;
  final List<MultiItemLine> initial;
  final double? targetTotal;

  const MultiItemDetailScreen({
    super.key,
    required this.category,
    this.initial = const [],
    this.targetTotal,
  });

  @override
  ConsumerState<MultiItemDetailScreen> createState() => _MultiItemDetailScreenState();
}

class _ItemEntry {
  final String name;
  final String? subcategoryId;
  bool isSelected;

  final TextEditingController qtyController = TextEditingController();
  final TextEditingController unitPriceController = TextEditingController();
  final TextEditingController totalController = TextEditingController();

  String selectedUnit = '';
  ExpenseClassification classification;
  String? personId;
  String? personName;

  _ItemEntry({
    required this.name,
    this.subcategoryId,
    this.isSelected = false,
    double? initialAmount,
    String? initialQuantity,
    double? initialUnitPrice,
    this.classification = ExpenseClassification.required,
    this.personId,
    this.personName,
  }) {
    if (initialAmount != null && initialAmount > 0) {
      totalController.text = _formatNum(initialAmount);
    }
    if (initialQuantity != null && initialQuantity.trim().isNotEmpty) {
      final parsed = _parseQuantity(initialQuantity);
      if (parsed.numStr.isNotEmpty) {
        qtyController.text = parsed.numStr;
      }
      selectedUnit = parsed.unit;
    }
    if (initialUnitPrice != null && initialUnitPrice > 0) {
      unitPriceController.text = _formatNum(initialUnitPrice);
    } else if (initialAmount != null && initialAmount > 0) {
      final q = double.tryParse(qtyController.text.trim());
      if (q != null && q > 0) {
        unitPriceController.text = _formatNum(initialAmount / q);
      }
    }
  }

  double get amount => double.tryParse(totalController.text.trim()) ?? 0.0;
  double? get unitPrice => double.tryParse(unitPriceController.text.trim());
  String? get quantity {
    final q = qtyController.text.trim();
    if (q.isEmpty) return null;
    return selectedUnit.isNotEmpty ? '$q $selectedUnit' : q;
  }

  void dispose() {
    qtyController.dispose();
    unitPriceController.dispose();
    totalController.dispose();
  }

  static ({String numStr, String unit}) _parseQuantity(String raw) {
    final trimmed = raw.trim();
    final parts = trimmed.split(RegExp(r'\s+'));
    if (parts.length >= 2) {
      final firstNum = double.tryParse(parts.first);
      if (firstNum != null) {
        final unitCandidate = parts.sublist(1).join(' ');
        final matchedUnit = _commonUnits.firstWhere(
          (u) => u.toLowerCase() == unitCandidate.toLowerCase(),
          orElse: () => unitCandidate,
        );
        return (numStr: _formatNum(firstNum), unit: matchedUnit);
      }
    }
    final soleNum = double.tryParse(trimmed);
    if (soleNum != null) {
      return (numStr: _formatNum(soleNum), unit: '');
    }
    return (numStr: '', unit: trimmed);
  }

  static String _formatNum(double v) {
    if (v == v.roundToDouble()) return v.toStringAsFixed(0);
    final s = v.toStringAsFixed(2);
    if (s.endsWith('.00')) return s.substring(0, s.length - 3);
    if (s.endsWith('0')) return s.substring(0, s.length - 1);
    return s;
  }
}

class _MultiItemDetailScreenState extends ConsumerState<MultiItemDetailScreen> {
  final List<_ItemEntry> _items = [];
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _customController = TextEditingController();
  final FocusNode _customFocusNode = FocusNode();

  String _searchQuery = '';
  int _selectedFilterTab = 0; // 0 = All, 1 = Selected only
  double? _targetTotal;

  @override
  void initState() {
    super.initState();
    _targetTotal = widget.targetTotal;
    _initItems();
  }

  void _initItems() {
    final subs = [...widget.category.subcategories]
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));

    for (final s in subs) {
      if (s.isActive && s.name.trim().toLowerCase() != 'other') {
        _items.add(_ItemEntry(
          name: s.name,
          subcategoryId: s.id,
          classification: s.defaultClassification,
        ));
      }
    }

    if (isGroceryOnlyCategory(widget.category)) {
      for (final item in _defaultGroceryItems) {
        if (!_hasItem(item)) {
          _items.add(_ItemEntry(
            name: item,
            subcategoryId: null,
            classification: widget.category.defaultClassification,
          ));
        }
      }
    } else if (isFoodCategory(widget.category)) {
      for (final item in _defaultFoodItems) {
        if (!_hasItem(item)) {
          _items.add(_ItemEntry(
            name: item,
            subcategoryId: null,
            classification: widget.category.defaultClassification,
          ));
        }
      }
    }

    // Restore previously selected lines
    for (final line in widget.initial) {
      var entry = _findItem(line.name);
      if (entry == null) {
        entry = _ItemEntry(
          name: line.name,
          subcategoryId: line.subcategoryId,
          isSelected: true,
          initialAmount: line.amount,
          initialQuantity: line.quantity,
          initialUnitPrice: line.unitPrice,
          classification: line.classification,
          personId: line.personId,
          personName: line.personName,
        );
        _items.insert(0, entry);
      } else {
        entry.isSelected = true;
        entry.classification = line.classification;
        entry.personId = line.personId;
        entry.personName = line.personName;
        if (line.amount > 0) {
          entry.totalController.text = _formatNum(line.amount);
        }
        if (line.quantity != null && line.quantity!.trim().isNotEmpty) {
          final parsed = _ItemEntry._parseQuantity(line.quantity!);
          entry.qtyController.text = parsed.numStr;
          entry.selectedUnit = parsed.unit;
        }
        if (line.unitPrice != null && line.unitPrice! > 0) {
          entry.unitPriceController.text = _formatNum(line.unitPrice!);
        } else if (line.amount > 0) {
          final q = double.tryParse(entry.qtyController.text.trim());
          if (q != null && q > 0) {
            entry.unitPriceController.text = _formatNum(line.amount / q);
          }
        }
      }
    }
  }

  bool _hasItem(String name) => _findItem(name) != null;

  _ItemEntry? _findItem(String name) {
    final n = name.trim().toLowerCase();
    for (final item in _items) {
      if (item.name.toLowerCase() == n) return item;
    }
    return null;
  }

  static String _formatNum(double v) {
    if (v == v.roundToDouble()) return v.toStringAsFixed(0);
    final s = v.toStringAsFixed(2);
    if (s.endsWith('.00')) return s.substring(0, s.length - 3);
    if (s.endsWith('0')) return s.substring(0, s.length - 1);
    return s;
  }

  Color _getClassificationColor(ExpenseClassification classification) {
    switch (classification) {
      case ExpenseClassification.urgent:
        return AppTheme.urgentColor;
      case ExpenseClassification.required:
        return AppTheme.requiredColor;
      case ExpenseClassification.optional:
        return AppTheme.optionalColor;
      case ExpenseClassification.lost:
        return AppTheme.lostColor;
    }
  }

  @override
  void dispose() {
    for (final item in _items) {
      item.dispose();
    }
    _searchController.dispose();
    _customController.dispose();
    _customFocusNode.dispose();
    super.dispose();
  }

  double get _totalAllocated => _items
      .where((i) => i.isSelected)
      .fold(0.0, (sum, i) => sum + i.amount);

  int get _selectedCount => _items.where((i) => i.isSelected).length;

  bool get _isTargetMatched {
    if (_targetTotal == null || _targetTotal! <= 0) return true;
    return (_totalAllocated - _targetTotal!).abs() <= 0.01;
  }

  void _addCustomItem() {
    final name = _customController.text.trim();
    if (name.isEmpty) return;
    setState(() {
      var entry = _findItem(name);
      if (entry == null) {
        entry = _ItemEntry(
          name: name,
          subcategoryId: null,
          isSelected: true,
          classification: widget.category.defaultClassification,
        );
        _items.insert(0, entry);
      } else {
        entry.isSelected = true;
      }
      _customController.clear();
      _searchController.clear();
      _searchQuery = '';
      _selectedFilterTab = 0;
    });
    FocusScope.of(context).unfocus();
  }

  void _onQtyChanged(_ItemEntry entry, String text) {
    final q = double.tryParse(text.trim());
    final up = double.tryParse(entry.unitPriceController.text.trim());
    final tot = double.tryParse(entry.totalController.text.trim());

    if (q != null && q > 0) {
      if (up != null && up > 0) {
        // Qty + Unit Price -> Total
        entry.totalController.text = _formatNum(q * up);
      } else if (tot != null && tot > 0) {
        // Qty + Total -> Unit Price
        entry.unitPriceController.text = _formatNum(tot / q);
      }
    }
    setState(() {});
  }

  void _onUnitPriceChanged(_ItemEntry entry, String text) {
    final up = double.tryParse(text.trim());
    final q = double.tryParse(entry.qtyController.text.trim());
    final tot = double.tryParse(entry.totalController.text.trim());

    if (up != null && up > 0) {
      if (q != null && q > 0) {
        // Unit Price + Qty -> Total
        entry.totalController.text = _formatNum(q * up);
      } else if (tot != null && tot > 0) {
        // Unit Price + Total -> Qty
        entry.qtyController.text = _formatNum(tot / up);
      }
    }
    setState(() {});
  }

  void _onTotalChanged(_ItemEntry entry, String text) {
    final tot = double.tryParse(text.trim());
    final q = double.tryParse(entry.qtyController.text.trim());
    final up = double.tryParse(entry.unitPriceController.text.trim());

    if (tot != null && tot > 0) {
      if (q != null && q > 0) {
        // Total + Qty -> Unit Price
        entry.unitPriceController.text = _formatNum(tot / q);
      } else if (up != null && up > 0) {
        // Total + Unit Price -> Qty
        entry.qtyController.text = _formatNum(tot / up);
      }
    }
    setState(() {});
  }

  void _showEditTargetDialog() {
    final sym = CurrencyFormatters.defaultCurrency;
    final controller = TextEditingController(
      text: _targetTotal != null && _targetTotal! > 0 ? _formatNum(_targetTotal!) : '',
    );

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          final eval = MathEvaluator.tryEvaluate(controller.text.trim());
          return AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.edit_note, color: Colors.green),
                SizedBox(width: 8),
                Text('Edit Target Amount'),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Set or update the target amount for this category expense (e.g. 5000 or 800+100):',
                  style: TextStyle(fontSize: 13),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: controller,
                  autofocus: true,
                  keyboardType: TextInputType.text,
                  decoration: InputDecoration(
                    labelText: 'Target Amount',
                    prefixText: '$sym ',
                    border: const OutlineInputBorder(),
                    helperText: eval != null && MathEvaluator.hasOperator(controller.text)
                        ? '= $sym ${MathEvaluator.format(eval)}'
                        : null,
                    helperStyle: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold),
                  ),
                  onChanged: (_) => setDialogState(() {}),
                ),
                const SizedBox(height: 10),
                if (_totalAllocated > 0)
                  InkWell(
                    onTap: () {
                      controller.text = _formatNum(_totalAllocated);
                      setDialogState(() {});
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Text(
                        '⚡ Use items total ($sym ${_formatNum(_totalAllocated)})',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.green,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('Cancel'),
              ),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: Colors.green),
                onPressed: () {
                  final text = controller.text.trim();
                  final val = MathEvaluator.tryEvaluate(text);
                  setState(() {
                    _targetTotal = val != null && val > 0 ? val : null;
                  });
                  Navigator.of(ctx).pop();
                },
                child: const Text('Save Target'),
              ),
            ],
          );
        },
      ),
    );
  }

  void _done() {
    final selected = _items.where((i) => i.isSelected).toList();
    if (selected.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select at least one subcategory item.')),
      );
      return;
    }

    final missing = selected.where((i) => i.amount <= 0).map((i) => i.name).toList();
    if (missing.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Please enter an amount for: ${missing.join(', ')}'),
          backgroundColor: Colors.red.shade700,
        ),
      );
      return;
    }

    if (_targetTotal != null && _targetTotal! > 0) {
      final sym = CurrencyFormatters.defaultCurrency;
      final diff = _targetTotal! - _totalAllocated;
      if (diff.abs() > 0.01) {
        _showMismatchDialog(diff, sym, selected);
        return;
      }
    }

    _finishWithSelected(selected);
  }

  void _showMismatchDialog(double diff, String sym, List<_ItemEntry> selected) {
    final isOver = diff < 0;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: isOver ? Colors.red : Colors.amber.shade800),
            const SizedBox(width: 8),
            const Text('Amount Mismatch'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Target Total: $sym ${_formatNum(_targetTotal ?? 0)}'),
            const SizedBox(height: 4),
            Text('Items Total: $sym ${_formatNum(_totalAllocated)}',
                style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text(
              isOver
                  ? 'The selected items exceed the target amount by $sym ${_formatNum(diff.abs())}.'
                  : 'There is $sym ${_formatNum(diff)} left unallocated from the target amount.',
              style: TextStyle(
                color: isOver ? Colors.red.shade700 : Colors.amber.shade900,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'Would you like to update the expense total to match these items, or keep editing?',
              style: TextStyle(fontSize: 13),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Keep Editing'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.green),
            onPressed: () {
              Navigator.of(ctx).pop();
              _targetTotal = _totalAllocated;
              _finishWithSelected(selected);
            },
            child: Text('Update to $sym ${_formatNum(_totalAllocated)}'),
          ),
        ],
      ),
    );
  }

  void _finishWithSelected(List<_ItemEntry> selected) {
    final results = selected.map((i) {
      return MultiItemLine(
        name: i.name,
        subcategoryId: i.subcategoryId,
        amount: i.amount,
        quantity: i.quantity,
        unitPrice: i.unitPrice,
        classification: i.classification,
        personId: i.personId,
        personName: i.personName,
      );
    }).toList();

    Navigator.of(context).pop(
      MultiItemResult(
        items: results,
        targetTotal: _targetTotal,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final sym = CurrencyFormatters.defaultCurrency;
    final peopleList = ref.watch(peopleListProvider).valueOrNull ?? [];

    List<_ItemEntry> visible = _items;
    if (_searchQuery.isNotEmpty) {
      visible = visible.where((i) => i.name.toLowerCase().contains(_searchQuery)).toList();
    }
    if (_selectedFilterTab == 1) {
      visible = visible.where((i) => i.isSelected).toList();
    } else {
      // Show selected items at the top of the list
      visible = [
        ...visible.where((i) => i.isSelected),
        ...visible.where((i) => !i.isSelected),
      ];
    }

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Icon(
              CategoryIconHelper.getIconData(widget.category.icon),
              color: Colors.green,
              size: 22,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '${widget.category.name} Items',
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        actions: [
          TextButton.icon(
            onPressed: _selectedCount == 0 ? null : _done,
            icon: const Icon(Icons.check, size: 20),
            label: const Text('Done', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
      body: Column(
        children: [
          _buildSummaryHeader(scheme, sym),
          _buildSearchAndCustomBar(scheme),
          _buildFilterTabs(scheme),
          const Divider(height: 1),
          Expanded(
            child: visible.isEmpty
                ? _buildEmptyState(scheme)
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(14, 8, 14, 80),
                    itemCount: visible.length,
                    itemBuilder: (context, index) {
                      final item = visible[index];
                      return _buildItemCard(item, scheme, sym, peopleList);
                    },
                  ),
          ),
        ],
      ),
      bottomNavigationBar: _buildBottomBar(scheme, sym),
    );
  }

  Widget _buildSummaryHeader(ColorScheme scheme, String sym) {
    final hasTarget = _targetTotal != null && _targetTotal! > 0;
    if (!hasTarget) {
      return Container(
        margin: const EdgeInsets.fromLTRB(14, 10, 14, 6),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.6)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                const Icon(Icons.calculate_outlined, color: Colors.green, size: 24),
                const SizedBox(width: 10),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Total Allocated: $sym ${_formatNum(_totalAllocated)}',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                    Text('$_selectedCount items selected',
                        style: TextStyle(
                            fontSize: 12, color: scheme.onSurface.withValues(alpha: 0.7))),
                  ],
                ),
              ],
            ),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              ),
              onPressed: _showEditTargetDialog,
              icon: const Icon(Icons.add, size: 16),
              label: const Text('Set Target', style: TextStyle(fontSize: 12)),
            ),
          ],
        ),
      );
    }

    final target = _targetTotal!;
    final diff = target - _totalAllocated;
    final isMatched = diff.abs() <= 0.01;
    final isExceeded = diff < -0.01;

    final Color statusColor = isMatched
        ? Colors.green
        : (isExceeded ? Colors.red.shade700 : Colors.amber.shade900);

    final String statusText = isMatched
        ? '✓ Matched'
        : (isExceeded
            ? 'Exceeds by $sym ${_formatNum(diff.abs())}'
            : 'Remaining: $sym ${_formatNum(diff)}');

    final progressVal = target > 0 ? (_totalAllocated / target).clamp(0.0, 1.0) : 0.0;

    return Container(
      margin: const EdgeInsets.fromLTRB(14, 10, 14, 6),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isMatched
            ? Colors.green.withValues(alpha: 0.09)
            : (isExceeded
                ? Colors.red.withValues(alpha: 0.08)
                : Colors.amber.withValues(alpha: 0.12)),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: statusColor.withValues(alpha: 0.7),
          width: 1.2,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Row(
                  children: [
                    Text(
                      'Target: $sym ${_formatNum(target)}',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                    const SizedBox(width: 6),
                    InkWell(
                      onTap: _showEditTargetDialog,
                      borderRadius: BorderRadius.circular(4),
                      child: Padding(
                        padding: const EdgeInsets.all(2),
                        child: Icon(Icons.edit, size: 15, color: scheme.primary),
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  statusText,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                    color: statusColor,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progressVal,
              minHeight: 6,
              backgroundColor: scheme.outlineVariant.withValues(alpha: 0.4),
              valueColor: AlwaysStoppedAnimation<Color>(statusColor),
            ),
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Allocated: $sym ${_formatNum(_totalAllocated)}',
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
              ),
              if (!isMatched)
                InkWell(
                  onTap: () {
                    setState(() {
                      _targetTotal = _totalAllocated;
                    });
                  },
                  child: Text(
                    '⚡ Match target ($sym ${_formatNum(_totalAllocated)})',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: Colors.green.shade800,
                    ),
                  ),
                )
              else
                Text(
                  '$_selectedCount item${_selectedCount == 1 ? '' : 's'}',
                  style: TextStyle(fontSize: 12, color: scheme.onSurface.withValues(alpha: 0.7)),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSearchAndCustomBar(ColorScheme scheme) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      child: Column(
        children: [
          TextField(
            controller: _searchController,
            decoration: InputDecoration(
              hintText: 'Search items in ${widget.category.name}...',
              prefixIcon: const Icon(Icons.search, size: 20),
              suffixIcon: _searchQuery.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear, size: 18),
                      onPressed: () {
                        setState(() {
                          _searchController.clear();
                          _searchQuery = '';
                        });
                      },
                    )
                  : null,
              isDense: true,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            ),
            onChanged: (val) => setState(() => _searchQuery = val.trim().toLowerCase()),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _customController,
                  focusNode: _customFocusNode,
                  textCapitalization: TextCapitalization.words,
                  decoration: InputDecoration(
                    hintText: 'Add custom item...',
                    prefixIcon: const Icon(Icons.add_circle_outline, size: 20),
                    isDense: true,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                  onSubmitted: (_) => _addCustomItem(),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                ),
                onPressed: _addCustomItem,
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Add'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFilterTabs(ColorScheme scheme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 4, 14, 4),
      child: Row(
        children: [
          ChoiceChip(
            label: Text('All (${_items.length})'),
            selected: _selectedFilterTab == 0,
            onSelected: (val) => setState(() => _selectedFilterTab = 0),
          ),
          const SizedBox(width: 8),
          ChoiceChip(
            label: Text('Selected ($_selectedCount)'),
            selected: _selectedFilterTab == 1,
            selectedColor: Colors.green.withValues(alpha: 0.2),
            onSelected: (val) => setState(() => _selectedFilterTab = 1),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(ColorScheme scheme) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.inventory_2_outlined, size: 48, color: scheme.outline),
          const SizedBox(height: 12),
          Text(
            _selectedFilterTab == 1
                ? 'No items selected yet'
                : 'No items matching "$_searchQuery"',
            style: TextStyle(fontSize: 15, color: scheme.onSurface.withValues(alpha: 0.7)),
          ),
          const SizedBox(height: 6),
          Text(
            _selectedFilterTab == 1
                ? 'Switch to "All" tab to tick items.'
                : 'Type above and tap "+ Add" to create it.',
            style: TextStyle(fontSize: 12, color: scheme.onSurface.withValues(alpha: 0.5)),
          ),
        ],
      ),
    );
  }

  Widget _buildItemCard(
    _ItemEntry item,
    ColorScheme scheme,
    String sym,
    List<Person> peopleList,
  ) {
    if (!item.isSelected) {
      return Container(
        margin: const EdgeInsets.symmetric(vertical: 3),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.5)),
        ),
        child: ListTile(
          dense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 8),
          leading: Checkbox(
            value: false,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
            onChanged: (v) => setState(() => item.isSelected = true),
          ),
          title: Text(item.name, style: const TextStyle(fontWeight: FontWeight.w500)),
          trailing: IconButton(
            icon: const Icon(Icons.add_circle_outline, color: Colors.green),
            onPressed: () => setState(() => item.isSelected = true),
          ),
          onTap: () => setState(() => item.isSelected = true),
        ),
      );
    }

    // Selected state with 3-way calculator inputs + classification + family member assignment
    final double? q = double.tryParse(item.qtyController.text.trim());
    final double? up = double.tryParse(item.unitPriceController.text.trim());
    final double tot = item.amount;

    String formulaText = '';
    if (q != null && q > 0 && up != null && up > 0) {
      final unitSuffix = item.selectedUnit.isNotEmpty ? ' ${item.selectedUnit}' : '';
      formulaText = '${_formatNum(q)}$unitSuffix × $sym ${_formatNum(up)} = $sym ${_formatNum(tot)}';
    } else if (tot > 0) {
      formulaText = 'Total: $sym ${_formatNum(tot)}';
    }

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 5),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      decoration: BoxDecoration(
        color: Colors.green.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.green.withValues(alpha: 0.6), width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.check_circle, color: Colors.green, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  item.name,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                ),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.close, size: 18, color: Colors.grey),
                tooltip: 'Remove',
                onPressed: () => setState(() {
                  item.isSelected = false;
                }),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // Row 1: Quantity + Unit Dropdown
          Row(
            children: [
              Expanded(
                flex: 3,
                child: TextField(
                  controller: item.qtyController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*')),
                  ],
                  decoration: const InputDecoration(
                    labelText: 'Quantity',
                    hintText: 'e.g. 2',
                    isDense: true,
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  ),
                  onChanged: (text) => _onQtyChanged(item, text),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 2,
                child: DropdownButtonFormField<String>(
                  initialValue: _commonUnits.contains(item.selectedUnit) ? item.selectedUnit : '',
                  decoration: const InputDecoration(
                    labelText: 'Unit',
                    isDense: true,
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                  ),
                  items: _commonUnits.map((u) {
                    return DropdownMenuItem<String>(
                      value: u,
                      child: Text(u.isEmpty ? 'None' : u, style: const TextStyle(fontSize: 13)),
                    );
                  }).toList(),
                  onChanged: (val) {
                    setState(() {
                      item.selectedUnit = val ?? '';
                    });
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // Row 2: Unit Price and Total Amount (3-way calculation)
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: item.unitPriceController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*')),
                  ],
                  decoration: InputDecoration(
                    labelText: 'Unit Price',
                    prefixText: '$sym ',
                    hintText: '0',
                    isDense: true,
                    border: const OutlineInputBorder(),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  ),
                  onChanged: (text) => _onUnitPriceChanged(item, text),
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 6),
                child: Text('=', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              ),
              Expanded(
                child: TextField(
                  controller: item.totalController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*')),
                  ],
                  decoration: InputDecoration(
                    labelText: 'Total Amount',
                    prefixText: '$sym ',
                    hintText: '0',
                    isDense: true,
                    border: const OutlineInputBorder(),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  ),
                  style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.green),
                  onChanged: (text) => _onTotalChanged(item, text),
                ),
              ),
            ],
          ),
          if (formulaText.isNotEmpty) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                const Icon(Icons.info_outline, size: 14, color: Colors.green),
                const SizedBox(width: 4),
                Text(
                  formulaText,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: Colors.green,
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 10),
          const Divider(height: 1),
          const SizedBox(height: 8),
          // Row 3: Classification Selector (Required, Optional, Urgent, Lost)
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.label_outline, size: 14, color: Colors.grey),
                  const SizedBox(width: 4),
                  Text(
                    'Classification',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: scheme.onSurface.withValues(alpha: 0.7),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: ExpenseClassification.values.map((c) {
                    final isSel = item.classification == c;
                    final color = _getClassificationColor(c);
                    return Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: ChoiceChip(
                        visualDensity: VisualDensity.compact,
                        label: Text(
                          c.label,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: isSel ? FontWeight.bold : FontWeight.normal,
                            color: isSel ? Colors.white : color,
                          ),
                        ),
                        selected: isSel,
                        selectedColor: color,
                        backgroundColor: color.withValues(alpha: 0.08),
                        side: BorderSide(color: color.withValues(alpha: isSel ? 1.0 : 0.4)),
                        showCheckmark: false,
                        onSelected: (val) {
                          if (val) setState(() => item.classification = c);
                        },
                      ),
                    );
                  }).toList(),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // Row 4: Assign to Family Member
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String?>(
                  initialValue: item.personId,
                  decoration: const InputDecoration(
                    labelText: 'Assign to Family Member',
                    prefixIcon: Icon(Icons.person_outline, size: 18),
                    isDense: true,
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  ),
                  isExpanded: true,
                  items: [
                    const DropdownMenuItem<String?>(
                      value: null,
                      child: Text('Household (Shared)', style: TextStyle(fontSize: 12)),
                    ),
                    ...peopleList.map((p) {
                      final rel = p.relationship != null && p.relationship!.isNotEmpty
                          ? ' (${p.relationship})'
                          : '';
                      return DropdownMenuItem<String?>(
                        value: p.uuid,
                        child: Text(
                          '${p.name}$rel',
                          style: const TextStyle(fontSize: 12),
                          overflow: TextOverflow.ellipsis,
                        ),
                      );
                    }),
                  ],
                  onChanged: (val) {
                    setState(() {
                      item.personId = val;
                      final matched = peopleList.where((p) => p.uuid == val).firstOrNull;
                      item.personName = matched?.name;
                    });
                  },
                ),
              ),
              const SizedBox(width: 6),
              IconButton(
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.person_add_alt_1_outlined, color: Colors.green, size: 20),
                tooltip: 'Add Family Member',
                onPressed: () async {
                  final created = await showAddPersonDialog(context, ref);
                  if (created != null) {
                    setState(() {
                      item.personId = created.uuid;
                      item.personName = created.name;
                    });
                  }
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBottomBar(ColorScheme scheme, String sym) {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
        decoration: BoxDecoration(
          color: scheme.surface,
          border: Border(top: BorderSide(color: scheme.outlineVariant)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              offset: const Offset(0, -2),
              blurRadius: 4,
            ),
          ],
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '$_selectedCount item${_selectedCount == 1 ? '' : 's'} selected',
                    style: TextStyle(fontSize: 12, color: scheme.onSurface.withValues(alpha: 0.7)),
                  ),
                  Row(
                    children: [
                      Text(
                        'Total: $sym ${_formatNum(_totalAllocated)}',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                          color: _isTargetMatched ? Colors.green : Colors.amber.shade900,
                        ),
                      ),
                      if (_targetTotal != null && _targetTotal! > 0) ...[
                        const SizedBox(width: 4),
                        Text(
                          '/ ${_formatNum(_targetTotal!)}',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: scheme.onSurface.withValues(alpha: 0.6),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: Colors.green,
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
              ),
              onPressed: _selectedCount == 0 ? null : _done,
              icon: const Icon(Icons.check),
              label: const Text('Done', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }
}
