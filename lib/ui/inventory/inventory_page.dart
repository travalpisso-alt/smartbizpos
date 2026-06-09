// lib/ui/inventory/inventory_page.dart
// Full CRUD inventory management — add/edit items, barcode, bilingual names, pricing

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/di/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../data/local/models/objectbox_models.dart';

// ─────────────────────────────────────────────────────────────
// Providers
// ─────────────────────────────────────────────────────────────

final inventorySearchProvider = StateProvider<String>((ref) => '');

final inventoryListProvider = Provider<List<ItemEntity>>((ref) {
  final box = ref.watch(itemBoxProvider);
  final query = ref.watch(inventorySearchProvider).toLowerCase();
  final all = box.getAll();
  if (query.isEmpty) return all;
  return all.where((item) {
    final names = jsonDecode(item.nameTranslationsJson) as Map<String, dynamic>;
    final barcode = item.barcode ?? '';
    return names.values.any((v) => v.toString().toLowerCase().contains(query)) ||
        barcode.contains(query);
  }).toList();
});

// ─────────────────────────────────────────────────────────────
// InventoryPage
// ─────────────────────────────────────────────────────────────

class InventoryPage extends ConsumerStatefulWidget {
  const InventoryPage({super.key});

  @override
  ConsumerState<InventoryPage> createState() => _InventoryPageState();
}

class _InventoryPageState extends ConsumerState<InventoryPage> {
  final _searchCtrl = TextEditingController();

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  void _openItemForm({ItemEntity? item}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => ItemFormSheet(
        existingItem: item,
        tenantId: ref.read(tenantIdProvider) ?? '',
        onSaved: (saved) {
          final box = ref.read(itemBoxProvider);
          box.put(saved);
          if (mounted) setState(() {});
        },
      ),
    );
  }

  void _deleteItem(ItemEntity item) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppTheme.surface,
        title: const Text('Delete Item', style: TextStyle(color: AppTheme.textPrimary)),
        content: Text(
          'Delete "${_itemName(item)}"? This cannot be undone.',
          style: const TextStyle(color: AppTheme.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel', style: TextStyle(color: AppTheme.textMuted)),
          ),
          TextButton(
            onPressed: () {
              ref.read(itemBoxProvider).remove(item.id);
              Navigator.pop(context);
              setState(() {});
            },
            child: const Text('Delete', style: TextStyle(color: AppTheme.error)),
          ),
        ],
      ),
    );
  }

  String _itemName(ItemEntity item) {
    final names = jsonDecode(item.nameTranslationsJson) as Map<String, dynamic>;
    return names['si'] as String? ?? names['en'] as String? ?? 'Unknown';
  }

  @override
  Widget build(BuildContext context) {
    final items = ref.watch(inventoryListProvider);

    return Scaffold(
      backgroundColor: AppTheme.surfaceDeep,
      appBar: AppBar(
        backgroundColor: AppTheme.surface,
        title: const Text('Inventory'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: TextButton.icon(
              onPressed: () => _openItemForm(),
              icon: const Icon(Icons.add_rounded, color: AppTheme.primary, size: 20),
              label: const Text('Add Item', style: TextStyle(color: AppTheme.primary)),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          // Search bar
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              controller: _searchCtrl,
              style: const TextStyle(color: AppTheme.textPrimary),
              onChanged: (v) =>
                  ref.read(inventorySearchProvider.notifier).state = v,
              decoration: InputDecoration(
                hintText: 'Search by name or barcode…',
                prefixIcon: const Icon(Icons.search, color: AppTheme.textMuted),
                suffixIcon: _searchCtrl.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, color: AppTheme.textMuted),
                        onPressed: () {
                          _searchCtrl.clear();
                          ref.read(inventorySearchProvider.notifier).state = '';
                        },
                      )
                    : null,
              ),
            ),
          ),

          // Stats row
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                _StatChip(
                  label: 'Total Items',
                  value: '${items.length}',
                  icon: Icons.inventory_2_outlined,
                  color: AppTheme.primary,
                ),
                const SizedBox(width: 12),
                _StatChip(
                  label: 'Low Stock',
                  value: '${items.where((i) => i.qtyInStock < 5).length}',
                  icon: Icons.warning_amber_rounded,
                  color: AppTheme.warning,
                ),
                const SizedBox(width: 12),
                _StatChip(
                  label: 'Out of Stock',
                  value: '${items.where((i) => i.qtyInStock <= 0).length}',
                  icon: Icons.remove_shopping_cart_outlined,
                  color: AppTheme.error,
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // Item list
          Expanded(
            child: items.isEmpty
                ? const Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.inventory_2_outlined,
                            color: AppTheme.border, size: 56),
                        SizedBox(height: 16),
                        Text('No items found',
                            style: TextStyle(color: AppTheme.textMuted)),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: items.length,
                    itemBuilder: (_, i) {
                      final item = items[i];
                      final names = jsonDecode(item.nameTranslationsJson)
                          as Map<String, dynamic>;
                      final prices = jsonDecode(item.pricesJson)
                          as Map<String, dynamic>;
                      final retail =
                          (prices['retail'] as num?)?.toDouble() ?? 0;
                      final wholesale =
                          (prices['wholesale'] as num?)?.toDouble() ?? 0;

                      final stockColor = item.qtyInStock <= 0
                          ? AppTheme.error
                          : item.qtyInStock < 5
                              ? AppTheme.warning
                              : AppTheme.success;

                      return Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        decoration: BoxDecoration(
                          color: AppTheme.surface,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: AppTheme.border),
                        ),
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 8),
                          leading: Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: AppTheme.primary.withOpacity(0.12),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(Icons.inventory_2_outlined,
                                color: AppTheme.primary, size: 22),
                          ),
                          title: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                names['si'] as String? ?? '',
                                style: const TextStyle(
                                    color: AppTheme.textPrimary,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 15),
                              ),
                              if ((names['en'] as String?)?.isNotEmpty == true)
                                Text(
                                  names['en'] as String,
                                  style: const TextStyle(
                                      color: AppTheme.textMuted, fontSize: 12),
                                ),
                            ],
                          ),
                          subtitle: Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Row(
                              children: [
                                _PriceTag(
                                    label: 'R',
                                    price: retail,
                                    color: AppTheme.lkr),
                                const SizedBox(width: 8),
                                _PriceTag(
                                    label: 'W',
                                    price: wholesale,
                                    color: AppTheme.primary),
                                if (item.barcode != null) ...[
                                  const SizedBox(width: 8),
                                  Icon(Icons.qr_code_2,
                                      size: 14,
                                      color: AppTheme.textMuted),
                                  const SizedBox(width: 2),
                                  Text(
                                    item.barcode!,
                                    style: const TextStyle(
                                        color: AppTheme.textMuted,
                                        fontSize: 11),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          trailing: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                item.qtyInStock
                                    .toStringAsFixed(
                                        item.qtyInStock % 1 == 0 ? 0 : 2),
                                style: TextStyle(
                                    color: stockColor,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16),
                              ),
                              Text(
                                'in stock',
                                style: TextStyle(
                                    color: stockColor.withOpacity(0.7),
                                    fontSize: 10),
                              ),
                            ],
                          ),
                          onTap: () => _openItemForm(item: item),
                          onLongPress: () => _deleteItem(item),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppTheme.primary,
        onPressed: () => _openItemForm(),
        icon: const Icon(Icons.add_rounded, color: Colors.white),
        label:
            const Text('New Item', style: TextStyle(color: Colors.white)),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// ItemFormSheet — add / edit item
// ─────────────────────────────────────────────────────────────

class ItemFormSheet extends StatefulWidget {
  final ItemEntity? existingItem;
  final String tenantId;
  final ValueChanged<ItemEntity> onSaved;

  const ItemFormSheet({
    super.key,
    this.existingItem,
    required this.tenantId,
    required this.onSaved,
  });

  @override
  State<ItemFormSheet> createState() => _ItemFormSheetState();
}

class _ItemFormSheetState extends State<ItemFormSheet> {
  final _nameEnCtrl = TextEditingController();
  final _nameSiCtrl = TextEditingController();
  final _barcodeCtrl = TextEditingController();
  final _retailCtrl = TextEditingController();
  final _wholesaleCtrl = TextEditingController();
  final _stockCtrl = TextEditingController();
  String? _error;

  @override
  void initState() {
    super.initState();
    final item = widget.existingItem;
    if (item != null) {
      final names = jsonDecode(item.nameTranslationsJson) as Map<String, dynamic>;
      final prices = jsonDecode(item.pricesJson) as Map<String, dynamic>;
      _nameEnCtrl.text = names['en'] as String? ?? '';
      _nameSiCtrl.text = names['si'] as String? ?? '';
      _barcodeCtrl.text = item.barcode ?? '';
      _retailCtrl.text = (prices['retail'] as num?)?.toString() ?? '';
      _wholesaleCtrl.text = (prices['wholesale'] as num?)?.toString() ?? '';
      _stockCtrl.text = item.qtyInStock.toString();
    }
  }

  @override
  void dispose() {
    _nameEnCtrl.dispose();
    _nameSiCtrl.dispose();
    _barcodeCtrl.dispose();
    _retailCtrl.dispose();
    _wholesaleCtrl.dispose();
    _stockCtrl.dispose();
    super.dispose();
  }

  void _save() {
    final nameEn = _nameEnCtrl.text.trim();
    final nameSi = _nameSiCtrl.text.trim();
    final retail = double.tryParse(_retailCtrl.text);
    final wholesale = double.tryParse(_wholesaleCtrl.text);
    final stock = double.tryParse(_stockCtrl.text) ?? 0;

    if (nameEn.isEmpty && nameSi.isEmpty) {
      setState(() => _error = 'Enter at least one name (English or Sinhala).');
      return;
    }
    if (retail == null || wholesale == null) {
      setState(() => _error = 'Enter valid retail and wholesale prices.');
      return;
    }

    final item = widget.existingItem ??
        ItemEntity(
          tenantId: widget.tenantId,
          nameTranslationsJson: '{}',
          pricesJson: '{}',
        );

    item
      ..nameTranslationsJson = jsonEncode({'en': nameEn, 'si': nameSi})
      ..pricesJson = jsonEncode({'retail': retail, 'wholesale': wholesale})
      ..barcode = _barcodeCtrl.text.trim().isEmpty ? null : _barcodeCtrl.text.trim()
      ..qtyInStock = stock
      ..isSynced = false
      ..updatedAt = DateTime.now();

    widget.onSaved(item);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.existingItem != null;
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
        left: 24,
        right: 24,
        top: 24,
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppTheme.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              isEdit ? 'Edit Item' : 'Add New Item',
              style: const TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: 20,
                  fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 24),

            _SectionLabel('Names'),
            const SizedBox(height: 8),
            TextField(
              controller: _nameSiCtrl,
              style: const TextStyle(color: AppTheme.textPrimary),
              decoration: const InputDecoration(
                hintText: 'සිංහල නාමය (Sinhala name)',
                prefixIcon: Icon(Icons.translate, color: AppTheme.textMuted),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _nameEnCtrl,
              style: const TextStyle(color: AppTheme.textPrimary),
              decoration: const InputDecoration(
                hintText: 'English name',
                prefixIcon: Icon(Icons.abc_rounded, color: AppTheme.textMuted),
              ),
            ),
            const SizedBox(height: 20),

            _SectionLabel('Barcode (optional)'),
            const SizedBox(height: 8),
            TextField(
              controller: _barcodeCtrl,
              style: const TextStyle(color: AppTheme.textPrimary),
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(
                hintText: 'Scan or type barcode',
                prefixIcon: Icon(Icons.qr_code_scanner, color: AppTheme.textMuted),
              ),
            ),
            const SizedBox(height: 20),

            _SectionLabel('Pricing (Rs.)'),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _retailCtrl,
                    style: const TextStyle(color: AppTheme.textPrimary),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                      hintText: 'Retail',
                      prefixIcon: Container(
                        width: 32,
                        alignment: Alignment.center,
                        child: Text('R',
                            style: TextStyle(
                                color: AppTheme.lkr,
                                fontWeight: FontWeight.bold,
                                fontSize: 13)),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _wholesaleCtrl,
                    style: const TextStyle(color: AppTheme.textPrimary),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                      hintText: 'Wholesale',
                      prefixIcon: Container(
                        width: 32,
                        alignment: Alignment.center,
                        child: Text('W',
                            style: TextStyle(
                                color: AppTheme.primary,
                                fontWeight: FontWeight.bold,
                                fontSize: 13)),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            _SectionLabel('Initial Stock'),
            const SizedBox(height: 8),
            TextField(
              controller: _stockCtrl,
              style: const TextStyle(color: AppTheme.textPrimary),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                hintText: '0',
                prefixIcon: Icon(Icons.warehouse_outlined, color: AppTheme.textMuted),
              ),
            ),

            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!,
                  style: const TextStyle(color: AppTheme.error, fontSize: 13)),
            ],

            const SizedBox(height: 28),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                onPressed: _save,
                child: Text(isEdit ? 'Save Changes' : 'Add Item'),
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Small helpers
// ─────────────────────────────────────────────────────────────

class _StatChip extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  const _StatChip({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: color.withOpacity(0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withOpacity(0.2)),
        ),
        child: Row(
          children: [
            Icon(icon, color: color, size: 18),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(value,
                    style: TextStyle(
                        color: color,
                        fontWeight: FontWeight.bold,
                        fontSize: 16)),
                Text(label,
                    style: const TextStyle(
                        color: AppTheme.textMuted, fontSize: 10)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _PriceTag extends StatelessWidget {
  final String label;
  final double price;
  final Color color;

  const _PriceTag({required this.label, required this.price, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        '$label Rs.${NumberFormat('#,##0').format(price)}',
        style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) => Text(
        text,
        style: const TextStyle(
            color: AppTheme.textSecondary,
            fontSize: 12,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.5),
      );
}
