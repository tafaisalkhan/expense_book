import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:myexpence/core/utils/currency_formatters.dart';
import 'package:myexpence/features/categories/domain/models/category.dart';

/// One selected item (e.g. "Flour", Rs 1200, "10 kg") that will be saved as
/// its own expense row.
class MultiItemLine {
  final String name;
  final String? subcategoryId;
  final double amount;
  final String? quantity;

  const MultiItemLine({
    required this.name,
    required this.subcategoryId,
    required this.amount,
    this.quantity,
  });

  String get displayName =>
      (quantity != null && quantity!.trim().isNotEmpty) ? '$name (${quantity!.trim()})' : name;
}

/// Default grocery items. Each item is a real subcategory (seeded from
/// assets/config/default_categories.json). If any is missing for this user
/// (e.g. deleted), it is shown anyway and auto-created as a subcategory on save.
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

/// Allows multi-item picking for ANY category that has subcategories.
bool isMultiItemCategory(Category? c) {
  if (c == null) return false;
  return c.subcategories.isNotEmpty;
}

/// Backwards-compatible alias so existing call sites work for all multi-item categories.
bool isGroceryCategory(Category? c) => isMultiItemCategory(c);

/// Shows a bottom-sheet where the user ticks several items of [category]
/// and enters a price (and optional quantity) for each one.
/// If [targetTotal] is provided, enforces that the selected items sum matches it.
Future<List<MultiItemLine>?> showMultiItemPickerSheet(
  BuildContext context, {
  required Category category,
  List<MultiItemLine> initial = const [],
  double? targetTotal,
}) {
  return showModalBottomSheet<List<MultiItemLine>>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => _MultiItemPickerSheet(
      category: category,
      initial: initial,
      targetTotal: targetTotal,
    ),
  );
}

class _ItemOption {
  final String name;
  final String? subcategoryId;
  final TextEditingController price = TextEditingController();
  final TextEditingController qty = TextEditingController();
  bool selected = false;

  _ItemOption(this.name, this.subcategoryId);

  void dispose() {
    price.dispose();
    qty.dispose();
  }
}

class _MultiItemPickerSheet extends StatefulWidget {
  final Category category;
  final List<MultiItemLine> initial;
  final double? targetTotal;

  const _MultiItemPickerSheet({
    required this.category,
    required this.initial,
    this.targetTotal,
  });

  @override
  State<_MultiItemPickerSheet> createState() => _MultiItemPickerSheetState();
}

class _MultiItemPickerSheetState extends State<_MultiItemPickerSheet> {
  final List<_ItemOption> _options = [];
  final _searchController = TextEditingController();
  final _customController = TextEditingController();
  String _query = '';

  @override
  void initState() {
    super.initState();
    final subs = [...widget.category.subcategories]
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));

    for (final s in subs) {
      if (s.isActive && s.name.trim().toLowerCase() != 'other') {
        _options.add(_ItemOption(s.name, s.id));
      }
    }

    if (isGroceryOnlyCategory(widget.category)) {
      for (final item in _defaultGroceryItems) {
        if (!_hasOption(item)) _options.add(_ItemOption(item, null));
      }
    } else if (isFoodCategory(widget.category)) {
      for (final item in _defaultFoodItems) {
        if (!_hasOption(item)) _options.add(_ItemOption(item, null));
      }
    }

    // Restore previously selected items (when user re-opens the picker)
    for (final line in widget.initial) {
      var opt = _findOption(line.name);
      if (opt == null) {
        opt = _ItemOption(line.name, line.subcategoryId);
        _options.insert(0, opt);
      }
      opt.selected = true;
      opt.price.text = _fmt(line.amount);
      opt.qty.text = line.quantity ?? '';
    }
  }

  String _fmt(double v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(2);

  bool _hasOption(String name) => _findOption(name) != null;

  _ItemOption? _findOption(String name) {
    final n = name.trim().toLowerCase();
    for (final o in _options) {
      if (o.name.toLowerCase() == n) return o;
    }
    return null;
  }

  @override
  void dispose() {
    for (final o in _options) {
      o.dispose();
    }
    _searchController.dispose();
    _customController.dispose();
    super.dispose();
  }

  double get _total => _options
      .where((o) => o.selected)
      .fold(0.0, (sum, o) => sum + (double.tryParse(o.price.text.trim()) ?? 0));

  int get _selectedCount => _options.where((o) => o.selected).length;

  void _addCustom() {
    final name = _customController.text.trim();
    if (name.isEmpty) return;
    setState(() {
      var opt = _findOption(name);
      if (opt == null) {
        opt = _ItemOption(name, null); // new subcategory created on save
        _options.insert(0, opt);
      }
      opt.selected = true;
      _customController.clear();
      _searchController.clear();
      _query = '';
    });
  }

  bool get _isTargetMatched {
    if (widget.targetTotal == null || widget.targetTotal! <= 0) return true;
    return (_total - widget.targetTotal!).abs() <= 0.01;
  }

  String get _targetStatusText {
    if (widget.targetTotal == null || widget.targetTotal! <= 0) return '';
    final sym = CurrencyFormatters.defaultCurrency;
    final diff = widget.targetTotal! - _total;
    if (diff.abs() <= 0.01) return '✓ Matched';
    if (diff > 0) return 'Remaining: $sym ${_fmt(diff)}';
    return 'Exceeds by: $sym ${_fmt(diff.abs())}';
  }

  Color get _targetStatusColor {
    if (widget.targetTotal == null || widget.targetTotal! <= 0) return Colors.green;
    final diff = widget.targetTotal! - _total;
    if (diff.abs() <= 0.01) return Colors.green;
    if (diff > 0) return Colors.amber.shade900;
    return Colors.red.shade700;
  }

  void _done() {
    final selected = _options.where((o) => o.selected).toList();
    final missing = selected
        .where((o) => (double.tryParse(o.price.text.trim()) ?? 0) <= 0)
        .map((o) => o.name)
        .toList();
    if (missing.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Enter price for: ${missing.join(', ')}')),
      );
      return;
    }

    if (widget.targetTotal != null && widget.targetTotal! > 0) {
      final sym = CurrencyFormatters.defaultCurrency;
      final diff = widget.targetTotal! - _total;
      if (diff.abs() > 0.01) {
        final msg = diff > 0
            ? 'Total of sub-items ($sym ${_fmt(_total)}) does not match entered amount ($sym ${_fmt(widget.targetTotal!)}). Remaining to allocate: $sym ${_fmt(diff)}.'
            : 'Total of sub-items ($sym ${_fmt(_total)}) exceeds entered amount ($sym ${_fmt(widget.targetTotal!)}). Excess: $sym ${_fmt(diff.abs())}.';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(msg),
            backgroundColor: Colors.red[800],
            duration: const Duration(seconds: 4),
          ),
        );
        return;
      }
    }

    Navigator.of(context).pop(selected
        .map((o) => MultiItemLine(
              name: o.name,
              subcategoryId: o.subcategoryId,
              amount: double.parse(o.price.text.trim()),
              quantity: o.qty.text.trim().isEmpty ? null : o.qty.text.trim(),
            ))
        .toList());
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    final visible = _query.isEmpty
        ? _options
        : _options.where((o) => o.name.toLowerCase().contains(_query)).toList();
    // Selected items first so they are easy to review
    final sorted = [
      ...visible.where((o) => o.selected),
      ...visible.where((o) => !o.selected),
    ];

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.9,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        builder: (context, scrollController) {
          return Column(
            children: [
              const SizedBox(height: 8),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: scheme.outlineVariant,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
                child: Row(
                  children: [
                    const Icon(Icons.shopping_cart, color: Colors.green),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Select ${widget.category.name} Sub-Items',
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  'Tick each sub-item, enter its price. Each item is saved as a separate expense.',
                  style: TextStyle(fontSize: 12, color: scheme.onSurface.withValues(alpha: 0.6)),
                ),
              ),
              if (widget.targetTotal != null && widget.targetTotal! > 0)
                Container(
                  margin: const EdgeInsets.fromLTRB(16, 8, 16, 2),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: _isTargetMatched
                        ? Colors.green.withValues(alpha: 0.1)
                        : (_total > widget.targetTotal!
                            ? Colors.red.withValues(alpha: 0.1)
                            : Colors.amber.withValues(alpha: 0.15)),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: _isTargetMatched
                          ? Colors.green
                          : (_total > widget.targetTotal! ? Colors.red : Colors.amber.shade700),
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Target Total: ${CurrencyFormatters.defaultCurrency} ${_fmt(widget.targetTotal!)}',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                      Text(
                        _targetStatusText,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                          color: _targetStatusColor,
                        ),
                      ),
                    ],
                  ),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
                child: TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.search),
                    hintText: 'Search items in ${widget.category.name}...',
                    border: const OutlineInputBorder(),
                    isDense: true,
                  ),
                  onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 6, 16, 4),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _customController,
                        textCapitalization: TextCapitalization.words,
                        decoration: const InputDecoration(
                          hintText: 'Add custom item',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        onSubmitted: (_) => _addCustom(),
                      ),
                    ),
                    const SizedBox(width: 8),
                    FilledButton.icon(
                      onPressed: _addCustom,
                      icon: const Icon(Icons.add, size: 18),
                      label: const Text('Add'),
                    ),
                  ],
                ),
              ),
              const Divider(height: 12),
              Expanded(
                child: ListView.builder(
                  controller: scrollController,
                  itemCount: sorted.length,
                  itemBuilder: (context, i) {
                    final o = sorted[i];
                    return Container(
                      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
                      decoration: BoxDecoration(
                        color: o.selected ? Colors.green.withValues(alpha: 0.08) : null,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: o.selected
                              ? Colors.green.withValues(alpha: 0.5)
                              : scheme.outlineVariant.withValues(alpha: 0.4),
                        ),
                      ),
                      child: Row(
                        children: [
                          Checkbox(
                            value: o.selected,
                            activeColor: Colors.green,
                            onChanged: (v) => setState(() => o.selected = v ?? false),
                          ),
                          Expanded(
                            child: GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: () => setState(() => o.selected = !o.selected),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(vertical: 14),
                                child: Text(
                                  o.name,
                                  style: TextStyle(
                                    fontWeight: o.selected ? FontWeight.bold : FontWeight.w500,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          if (o.selected) ...[
                            SizedBox(
                              width: 64,
                              child: TextField(
                                controller: o.qty,
                                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                inputFormatters: [
                                  FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*')),
                                ],
                                decoration: InputDecoration(
                                  hintText: 'Qty',
                                  isDense: true,
                                  border: OutlineInputBorder(),
                                ),
                                style: const TextStyle(fontSize: 13),
                              ),
                            ),
                            const SizedBox(width: 6),
                            SizedBox(
                              width: 92,
                              child: TextField(
                                controller: o.price,
                                keyboardType:
                                    const TextInputType.numberWithOptions(decimal: true),
                                decoration: InputDecoration(
                                  hintText: 'Price',
                                  prefixText: '${CurrencyFormatters.defaultCurrency} ',
                                  isDense: true,
                                  border: const OutlineInputBorder(),
                                ),
                                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                                onChanged: (_) => setState(() {}),
                              ),
                            ),
                            const SizedBox(width: 8),
                          ],
                        ],
                      ),
                    );
                  },
                ),
              ),
              SafeArea(
                top: false,
                child: Container(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
                  decoration: BoxDecoration(
                    color: scheme.surface,
                    border: Border(top: BorderSide(color: scheme.outlineVariant)),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('$_selectedCount items selected',
                                style: const TextStyle(fontSize: 12)),
                            Row(
                              children: [
                                Text(
                                  'Total: ${CurrencyFormatters.defaultCurrency} ${_fmt(_total)}',
                                  style: TextStyle(
                                    fontSize: 17,
                                    fontWeight: FontWeight.bold,
                                    color: _isTargetMatched ? Colors.green : Colors.redAccent,
                                  ),
                                ),
                                if (widget.targetTotal != null && widget.targetTotal! > 0) ...[
                                  const SizedBox(width: 4),
                                  Text(
                                    '/ ${_fmt(widget.targetTotal!)}',
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
                        style: FilledButton.styleFrom(backgroundColor: Colors.green),
                        onPressed: _selectedCount == 0 ? null : _done,
                        icon: const Icon(Icons.check),
                        label: const Text('Done'),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
