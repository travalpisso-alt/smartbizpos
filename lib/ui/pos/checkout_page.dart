// lib/ui/pos/checkout_page.dart
// Dependencies: supabase_flutter, objectbox, provider or riverpod

import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../data/local/models/objectbox_models.dart';
import '../../services/sync_service.dart';
import '../../objectbox.g.dart';

// ─────────────────────────────────────────────────────────────
// Data helpers
// ─────────────────────────────────────────────────────────────

class CartItem {
  final ItemEntity item;
  double qty;
  final String pricingTier;

  CartItem({required this.item, this.qty = 1, required this.pricingTier});

  Map<String, dynamic> get prices => jsonDecode(item.pricesJson) as Map<String, dynamic>;
  double get unitPrice => (prices[pricingTier.toLowerCase()] as num).toDouble();
  double get subtotal => unitPrice * qty;
  String get displayName {
    final names = jsonDecode(item.nameTranslationsJson) as Map<String, dynamic>;
    return names['si'] as String? ?? names['en'] as String? ?? item.remoteId;
  }
}

// ─────────────────────────────────────────────────────────────
// CheckoutPage
// ─────────────────────────────────────────────────────────────

class CheckoutPage extends StatefulWidget {
  final Store store;
  final SyncService syncService;
  final String tenantId;
  final SupabaseClient supabase;

  const CheckoutPage({
    super.key,
    required this.store,
    required this.syncService,
    required this.tenantId,
    required this.supabase,
  });

  @override
  State<CheckoutPage> createState() => _CheckoutPageState();
}

class _CheckoutPageState extends State<CheckoutPage>
    with TickerProviderStateMixin {
  // ── State ────────────────────────────────────────────────────
  final List<CartItem> _cart = [];
  final TextEditingController _searchCtrl = TextEditingController();
  final FocusNode _searchFocus = FocusNode();

  String _pricingTier = 'RETAIL'; // or 'WHOLESALE'
  String _paymentMode = 'CASH';
  CustomerEntity? _selectedCustomer;

  List<ItemEntity> _searchResults = [];
  List<CustomerEntity> _customerResults = [];
  bool _showCustomerSearch = false;
  bool _isProcessing = false;
  String? _errorMessage;

  // Dual-display WebSocket channel
  RealtimeChannel? _displayChannel;
  late AnimationController _successAnimCtrl;

  late final Box<ItemEntity> _itemBox;
  late final Box<CustomerEntity> _customerBox;
  late final Box<InvoiceEntity> _invoiceBox;
  late final Box<LineItemEntity> _lineItemBox;

  @override
  void initState() {
    super.initState();
    _itemBox = widget.store.box<ItemEntity>();
    _customerBox = widget.store.box<CustomerEntity>();
    _invoiceBox = widget.store.box<InvoiceEntity>();
    _lineItemBox = widget.store.box<LineItemEntity>();

    _successAnimCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );

    _initDualDisplay();
    _searchCtrl.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _displayChannel?.unsubscribe();
    _searchCtrl.dispose();
    _searchFocus.dispose();
    _successAnimCtrl.dispose();
    super.dispose();
  }

  // ── Dual-display WebSocket ───────────────────────────────────

  void _initDualDisplay() {
    _displayChannel = widget.supabase.channel('display:${widget.tenantId}');
    _displayChannel!.subscribe();
  }

  void _pushToDisplay() {
    _displayChannel?.sendBroadcastMessage(
      event: 'cart_update',
      payload: {
        'items': _cart
            .map((c) => {
                  'name': c.displayName,
                  'qty': c.qty,
                  'unit_price': c.unitPrice,
                  'subtotal': c.subtotal,
                })
            .toList(),
        'total': _cartTotal,
        'payment_mode': _paymentMode,
      },
    );
  }

  // ── Search ───────────────────────────────────────────────────

  void _onSearchChanged() {
    final q = _searchCtrl.text.trim().toLowerCase();
    if (q.isEmpty) {
      setState(() => _searchResults = []);
      return;
    }

    // Try barcode exact match first
    final byBarcode = _itemBox
        .query(ItemEntity_.barcode.equals(q))
        .build()
        .find();

    if (byBarcode.isNotEmpty) {
      // Auto-add on exact barcode scan
      _addToCart(byBarcode.first);
      _searchCtrl.clear();
      return;
    }

    // Fuzzy name search (contains, case-insensitive stored in JSON)
    final all = _itemBox
        .query(ItemEntity_.isActive.equals(true))
        .build()
        .find();

    setState(() {
      _searchResults = all.where((item) {
        final names = jsonDecode(item.nameTranslationsJson) as Map<String, dynamic>;
        return names.values.any((v) =>
            v.toString().toLowerCase().contains(q));
      }).take(20).toList();
    });
  }

  void _searchCustomers(String q) {
    if (q.isEmpty) {
      setState(() => _customerResults = []);
      return;
    }
    final all = _customerBox.getAll();
    setState(() {
      _customerResults = all
          .where((c) =>
              c.name.toLowerCase().contains(q.toLowerCase()) ||
              c.phone.contains(q))
          .take(10)
          .toList();
    });
  }

  // ── Cart operations ──────────────────────────────────────────

  void _addToCart(ItemEntity item) {
    setState(() {
      final existing = _cart.indexWhere((c) => c.item.id == item.id);
      if (existing >= 0) {
        _cart[existing].qty += 1;
      } else {
        _cart.add(CartItem(item: item, pricingTier: _pricingTier));
      }
      _searchResults = [];
    });
    _pushToDisplay();
    HapticFeedback.lightImpact();
  }

  void _removeFromCart(int index) {
    setState(() => _cart.removeAt(index));
    _pushToDisplay();
  }

  void _updateQty(int index, double delta) {
    setState(() {
      _cart[index].qty = (_cart[index].qty + delta).clamp(0.001, 99999);
      if (_cart[index].qty < 0.001) _cart.removeAt(index);
    });
    _pushToDisplay();
  }

  void _switchPricingTier(String tier) {
    setState(() {
      _pricingTier = tier;
      for (final c in _cart) {
        // re-assign tier (CartItem is mutable)
      }
      // Rebuild cart with new tier
      final updated = _cart.map((c) => CartItem(
            item: c.item,
            qty: c.qty,
            pricingTier: tier,
          )).toList();
      _cart
        ..clear()
        ..addAll(updated);
    });
    _pushToDisplay();
  }

  double get _cartTotal =>
      _cart.fold(0, (sum, c) => sum + c.subtotal);

  // ── Checkout ─────────────────────────────────────────────────

  Future<void> _processCheckout() async {
    if (_cart.isEmpty) {
      setState(() => _errorMessage = 'Cart is empty.');
      return;
    }

    setState(() {
      _isProcessing = true;
      _errorMessage = null;
    });

    try {
      // Build and save invoice locally
      final invoice = InvoiceEntity(
        tenantId: widget.tenantId,
        customerId: _selectedCustomer?.remoteId,
        totalAmount: _cartTotal,
        paymentMode: _paymentMode,
        isSynced: false,
      );
      _invoiceBox.put(invoice);

      // Save line items
      final lineItems = _cart.map((c) => LineItemEntity(
            itemId: c.item.remoteId,
            qty: c.qty,
            unitPrice: c.unitPrice,
            pricingTier: c.pricingTier,
          )..invoice.target = invoice).toList();
      _lineItemBox.putMany(lineItems);

      // Optimistic stock deduction locally
      for (final c in _cart) {
        c.item.qtyInStock -= c.qty;
        _itemBox.put(c.item);
      }

      // Clear cart + push zero state to display
      setState(() {
        _cart.clear();
        _selectedCustomer = null;
        _paymentMode = 'CASH';
      });

      // Push success to dual display
      _displayChannel?.sendBroadcastMessage(
        event: 'sale_complete',
        payload: {
          'total': _cartTotal,
          'payment_mode': _paymentMode,
        },
      );

      // Play success animation
      await _successAnimCtrl.forward(from: 0);

      // Trigger background sync
      unawaited(widget.syncService.triggerSync());
    } catch (e) {
      setState(() => _errorMessage = e.toString());
    } finally {
      setState(() => _isProcessing = false);
    }
  }

  // ── UI ───────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: const Color(0xFF0F1117),
      body: SafeArea(
        child: Column(
          children: [
            _buildTopBar(theme),
            Expanded(
              child: Row(
                children: [
                  // Left: item search + cart
                  Expanded(
                    flex: 6,
                    child: Column(
                      children: [
                        _buildSearchBar(),
                        if (_searchResults.isNotEmpty) _buildSearchDropdown(),
                        Expanded(child: _buildCartList()),
                      ],
                    ),
                  ),
                  // Right: totals + actions
                  SizedBox(
                    width: 280,
                    child: _buildSummaryPanel(theme),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopBar(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      color: const Color(0xFF1A1D27),
      child: Row(
        children: [
          // Tenant / logo placeholder
          const Icon(Icons.store_rounded, color: Color(0xFF6C63FF), size: 28),
          const SizedBox(width: 12),
          Text('SmartBiz POS',
              style: theme.textTheme.titleLarge?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              )),
          const Spacer(),
          // Pricing tier toggle
          _TierToggle(
            selected: _pricingTier,
            onChanged: _switchPricingTier,
          ),
          const SizedBox(width: 12),
          // Sync status indicator
          ValueListenableBuilder<SyncStatus>(
            valueListenable: widget.syncService.syncStatus,
            builder: (_, status, __) => Icon(
              status == SyncStatus.syncing
                  ? Icons.sync_rounded
                  : status == SyncStatus.error
                      ? Icons.sync_problem_rounded
                      : Icons.cloud_done_rounded,
              color: status == SyncStatus.error
                  ? Colors.redAccent
                  : status == SyncStatus.syncing
                      ? Colors.amber
                      : const Color(0xFF4CAF50),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: TextField(
        controller: _searchCtrl,
        focusNode: _searchFocus,
        style: const TextStyle(color: Colors.white),
        decoration: InputDecoration(
          hintText: 'Scan barcode or search item…',
          hintStyle: const TextStyle(color: Color(0xFF6B7280)),
          prefixIcon: const Icon(Icons.search, color: Color(0xFF6C63FF)),
          suffixIcon: _searchCtrl.text.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear, color: Colors.white54),
                  onPressed: () {
                    _searchCtrl.clear();
                    setState(() => _searchResults = []);
                  },
                )
              : null,
          filled: true,
          fillColor: const Color(0xFF1A1D27),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFF6C63FF), width: 1.5),
          ),
        ),
      ),
    );
  }

  Widget _buildSearchDropdown() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF1E2132),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF6C63FF).withOpacity(0.3)),
      ),
      constraints: const BoxConstraints(maxHeight: 200),
      child: ListView.builder(
        shrinkWrap: true,
        itemCount: _searchResults.length,
        itemBuilder: (_, i) {
          final item = _searchResults[i];
          final names = jsonDecode(item.nameTranslationsJson) as Map<String, dynamic>;
          final prices = jsonDecode(item.pricesJson) as Map<String, dynamic>;
          final price = (prices[_pricingTier.toLowerCase()] as num).toDouble();
          return ListTile(
            dense: true,
            title: Text(
              names['si'] as String? ?? names['en'] as String? ?? '',
              style: const TextStyle(color: Colors.white),
            ),
            subtitle: Text(
              'Stock: ${item.qtyInStock.toStringAsFixed(2)}',
              style: const TextStyle(color: Color(0xFF9CA3AF), fontSize: 11),
            ),
            trailing: Text(
              'Rs. ${price.toStringAsFixed(2)}',
              style: const TextStyle(color: Color(0xFF6C63FF), fontWeight: FontWeight.bold),
            ),
            onTap: () => _addToCart(item),
          );
        },
      ),
    );
  }

  Widget _buildCartList() {
    if (_cart.isEmpty) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.shopping_cart_outlined, color: Color(0xFF374151), size: 64),
            SizedBox(height: 12),
            Text('Cart is empty', style: TextStyle(color: Color(0xFF6B7280))),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      itemCount: _cart.length,
      itemBuilder: (_, i) {
        final c = _cart[i];
        return Dismissible(
          key: Key('${c.item.id}_$i'),
          direction: DismissDirection.endToStart,
          background: Container(
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.only(right: 16),
            decoration: BoxDecoration(
              color: Colors.redAccent.withOpacity(0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.delete_outline, color: Colors.redAccent),
          ),
          onDismissed: (_) => _removeFromCart(i),
          child: Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFF1A1D27),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(c.displayName,
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500)),
                      Text(
                        'Rs. ${c.unitPrice.toStringAsFixed(2)} × ${c.qty.toStringAsFixed(c.qty % 1 == 0 ? 0 : 2)}',
                        style: const TextStyle(color: Color(0xFF9CA3AF), fontSize: 12),
                      ),
                    ],
                  ),
                ),
                // Qty controls
                Row(
                  children: [
                    _QtyButton(
                      icon: Icons.remove,
                      onTap: () => _updateQty(i, -1),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Text(
                        c.qty.toStringAsFixed(c.qty % 1 == 0 ? 0 : 2),
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                      ),
                    ),
                    _QtyButton(
                      icon: Icons.add,
                      onTap: () => _updateQty(i, 1),
                    ),
                  ],
                ),
                const SizedBox(width: 12),
                Text(
                  'Rs. ${c.subtotal.toStringAsFixed(2)}',
                  style: const TextStyle(
                    color: Color(0xFF6C63FF),
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildSummaryPanel(ThemeData theme) {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF1A1D27),
        border: Border(left: BorderSide(color: Color(0xFF2D3142), width: 1)),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Customer selector
          GestureDetector(
            onTap: () => setState(() => _showCustomerSearch = !_showCustomerSearch),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFF0F1117),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFF2D3142)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.person_outline, color: Color(0xFF6C63FF), size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _selectedCustomer?.name ?? 'Walk-in Customer',
                      style: TextStyle(
                        color: _selectedCustomer != null ? Colors.white : const Color(0xFF6B7280),
                        fontSize: 13,
                      ),
                    ),
                  ),
                  const Icon(Icons.arrow_drop_down, color: Colors.white54),
                ],
              ),
            ),
          ),

          if (_showCustomerSearch) ...[
            const SizedBox(height: 8),
            TextField(
              style: const TextStyle(color: Colors.white, fontSize: 13),
              decoration: const InputDecoration(
                hintText: 'Search customer…',
                hintStyle: TextStyle(color: Color(0xFF6B7280), fontSize: 13),
                filled: true,
                fillColor: Color(0xFF0F1117),
                border: OutlineInputBorder(borderSide: BorderSide.none),
                contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              ),
              onChanged: _searchCustomers,
            ),
            ..._customerResults.map((c) => ListTile(
                  dense: true,
                  title: Text(c.name, style: const TextStyle(color: Colors.white, fontSize: 12)),
                  subtitle: Text(c.phone, style: const TextStyle(color: Color(0xFF9CA3AF), fontSize: 11)),
                  onTap: () {
                    setState(() {
                      _selectedCustomer = c;
                      _showCustomerSearch = false;
                      _customerResults = [];
                      // Auto-switch pricing tier
                      _switchPricingTier(c.pricingTier);
                    });
                  },
                )),
          ],

          const SizedBox(height: 16),
          const Divider(color: Color(0xFF2D3142)),
          const SizedBox(height: 8),

          // Item count
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Items', style: TextStyle(color: Color(0xFF9CA3AF), fontSize: 13)),
              Text('${_cart.length}', style: const TextStyle(color: Colors.white, fontSize: 13)),
            ],
          ),
          const SizedBox(height: 8),

          // Total
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Total', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
              Text(
                'Rs. ${_cartTotal.toStringAsFixed(2)}',
                style: const TextStyle(
                  color: Color(0xFF6C63FF),
                  fontWeight: FontWeight.bold,
                  fontSize: 20,
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),
          const Divider(color: Color(0xFF2D3142)),
          const SizedBox(height: 12),

          // Payment mode
          const Text('Payment', style: TextStyle(color: Color(0xFF9CA3AF), fontSize: 12)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: ['CASH', 'CARD_TAP', 'LANKAQR', 'CREDIT'].map((mode) {
              final selected = _paymentMode == mode;
              return GestureDetector(
                onTap: () => setState(() => _paymentMode = mode),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: selected ? const Color(0xFF6C63FF) : const Color(0xFF0F1117),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: selected ? const Color(0xFF6C63FF) : const Color(0xFF2D3142),
                    ),
                  ),
                  child: Text(
                    mode.replaceAll('_', ' '),
                    style: TextStyle(
                      color: selected ? Colors.white : const Color(0xFF9CA3AF),
                      fontSize: 11,
                      fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),

          if (_errorMessage != null) ...[
            const SizedBox(height: 12),
            Text(_errorMessage!, style: const TextStyle(color: Colors.redAccent, fontSize: 12)),
          ],

          const Spacer(),

          // Checkout button
          SizedBox(
            height: 52,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: _cart.isEmpty ? const Color(0xFF2D3142) : const Color(0xFF6C63FF),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              onPressed: _cart.isEmpty || _isProcessing ? null : _processCheckout,
              child: _isProcessing
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                    )
                  : Text(
                      'Charge  Rs. ${_cartTotal.toStringAsFixed(2)}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Small reusable widgets
// ─────────────────────────────────────────────────────────────

class _TierToggle extends StatelessWidget {
  final String selected;
  final ValueChanged<String> onChanged;

  const _TierToggle({required this.selected, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF0F1117),
        borderRadius: BorderRadius.circular(20),
      ),
      padding: const EdgeInsets.all(3),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: ['RETAIL', 'WHOLESALE'].map((tier) {
          final isSelected = selected == tier;
          return GestureDetector(
            onTap: () => onChanged(tier),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
              decoration: BoxDecoration(
                color: isSelected ? const Color(0xFF6C63FF) : Colors.transparent,
                borderRadius: BorderRadius.circular(17),
              ),
              child: Text(
                tier,
                style: TextStyle(
                  color: isSelected ? Colors.white : const Color(0xFF9CA3AF),
                  fontSize: 12,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _QtyButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _QtyButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          color: const Color(0xFF2D3142),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, color: Colors.white, size: 16),
      ),
    );
  }
}
