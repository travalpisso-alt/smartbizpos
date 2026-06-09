// lib/ui/customers/customers_page.dart
// Full customer management — list, add/edit, debt tracking

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

final customerSearchProvider = StateProvider<String>((ref) => '');
final customerTierFilterProvider = StateProvider<String?>((ref) => null);

final customerListProvider = Provider<List<CustomerEntity>>((ref) {
  final box = ref.watch(customerBoxProvider);
  final query = ref.watch(customerSearchProvider).toLowerCase();
  final tier = ref.watch(customerTierFilterProvider);
  return box.getAll().where((c) {
    final matchSearch = query.isEmpty ||
        c.name.toLowerCase().contains(query) ||
        c.phone.contains(query);
    final matchTier = tier == null || c.pricingTier == tier;
    return matchSearch && matchTier;
  }).toList()
    ..sort((a, b) => b.currentDebt.compareTo(a.currentDebt));
});

// ─────────────────────────────────────────────────────────────
// CustomersPage
// ─────────────────────────────────────────────────────────────

class CustomersPage extends ConsumerStatefulWidget {
  const CustomersPage({super.key});

  @override
  ConsumerState<CustomersPage> createState() => _CustomersPageState();
}

class _CustomersPageState extends ConsumerState<CustomersPage> {
  final _searchCtrl = TextEditingController();

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  void _openCustomerForm({CustomerEntity? customer}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => CustomerFormSheet(
        existing: customer,
        tenantId: ref.read(tenantIdProvider) ?? '',
        onSaved: (saved) {
          ref.read(customerBoxProvider).put(saved);
          setState(() {});
        },
      ),
    );
  }

  void _openDebtSheet(CustomerEntity customer) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => DebtAdjustSheet(
        customer: customer,
        onSaved: (updated) {
          ref.read(customerBoxProvider).put(updated);
          setState(() {});
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final customers = ref.watch(customerListProvider);
    final tier = ref.watch(customerTierFilterProvider);
    final totalDebt = customers.fold<double>(0, (s, c) => s + c.currentDebt);

    return Scaffold(
      backgroundColor: AppTheme.surfaceDeep,
      appBar: AppBar(
        backgroundColor: AppTheme.surface,
        title: const Text('Customers'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: TextButton.icon(
              onPressed: () => _openCustomerForm(),
              icon: const Icon(Icons.person_add_alt_1_rounded,
                  color: AppTheme.primary, size: 20),
              label: const Text('Add', style: TextStyle(color: AppTheme.primary)),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          // Search
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: TextField(
              controller: _searchCtrl,
              style: const TextStyle(color: AppTheme.textPrimary),
              onChanged: (v) =>
                  ref.read(customerSearchProvider.notifier).state = v,
              decoration: InputDecoration(
                hintText: 'Search by name or phone…',
                prefixIcon:
                    const Icon(Icons.search, color: AppTheme.textMuted),
                suffixIcon: _searchCtrl.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, color: AppTheme.textMuted),
                        onPressed: () {
                          _searchCtrl.clear();
                          ref.read(customerSearchProvider.notifier).state = '';
                        },
                      )
                    : null,
              ),
            ),
          ),

          // Tier filter chips
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                _FilterChip(
                  label: 'All',
                  selected: tier == null,
                  onTap: () => ref
                      .read(customerTierFilterProvider.notifier)
                      .state = null,
                ),
                const SizedBox(width: 8),
                _FilterChip(
                  label: 'Retail',
                  selected: tier == 'RETAIL',
                  color: AppTheme.lkr,
                  onTap: () => ref
                      .read(customerTierFilterProvider.notifier)
                      .state = 'RETAIL',
                ),
                const SizedBox(width: 8),
                _FilterChip(
                  label: 'Wholesale',
                  selected: tier == 'WHOLESALE',
                  color: AppTheme.primary,
                  onTap: () => ref
                      .read(customerTierFilterProvider.notifier)
                      .state = 'WHOLESALE',
                ),
                const Spacer(),
                if (totalDebt > 0)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppTheme.error.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      'Total Debt: Rs.${NumberFormat('#,##0.00').format(totalDebt)}',
                      style: const TextStyle(
                          color: AppTheme.error,
                          fontSize: 11,
                          fontWeight: FontWeight.w600),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // List
          Expanded(
            child: customers.isEmpty
                ? const Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.people_outline,
                            color: AppTheme.border, size: 56),
                        SizedBox(height: 16),
                        Text('No customers found',
                            style: TextStyle(color: AppTheme.textMuted)),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: customers.length,
                    itemBuilder: (_, i) {
                      final c = customers[i];
                      final isWholesale = c.pricingTier == 'WHOLESALE';
                      final tierColor =
                          isWholesale ? AppTheme.primary : AppTheme.lkr;

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
                          leading: CircleAvatar(
                            backgroundColor: tierColor.withOpacity(0.15),
                            child: Text(
                              c.name.isNotEmpty
                                  ? c.name[0].toUpperCase()
                                  : '?',
                              style: TextStyle(
                                  color: tierColor,
                                  fontWeight: FontWeight.bold),
                            ),
                          ),
                          title: Text(c.name,
                              style: const TextStyle(
                                  color: AppTheme.textPrimary,
                                  fontWeight: FontWeight.w600)),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  const Icon(Icons.phone_outlined,
                                      size: 13, color: AppTheme.textMuted),
                                  const SizedBox(width: 4),
                                  Text(c.phone,
                                      style: const TextStyle(
                                          color: AppTheme.textMuted,
                                          fontSize: 12)),
                                  const SizedBox(width: 10),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 6, vertical: 1),
                                    decoration: BoxDecoration(
                                      color: tierColor.withOpacity(0.12),
                                      borderRadius: BorderRadius.circular(5),
                                    ),
                                    child: Text(
                                      c.pricingTier,
                                      style: TextStyle(
                                          color: tierColor,
                                          fontSize: 10,
                                          fontWeight: FontWeight.w600),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                          trailing: GestureDetector(
                            onTap: () => _openDebtSheet(c),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(
                                  'Rs.${NumberFormat('#,##0.00').format(c.currentDebt)}',
                                  style: TextStyle(
                                    color: c.currentDebt > 0
                                        ? AppTheme.error
                                        : AppTheme.success,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14,
                                  ),
                                ),
                                Text(
                                  c.currentDebt > 0 ? 'debt' : 'clear',
                                  style: TextStyle(
                                    color: c.currentDebt > 0
                                        ? AppTheme.error.withOpacity(0.6)
                                        : AppTheme.success.withOpacity(0.6),
                                    fontSize: 10,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          onTap: () => _openCustomerForm(customer: c),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppTheme.primary,
        onPressed: () => _openCustomerForm(),
        icon: const Icon(Icons.person_add_alt_1_rounded, color: Colors.white),
        label: const Text('New Customer', style: TextStyle(color: Colors.white)),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// CustomerFormSheet
// ─────────────────────────────────────────────────────────────

class CustomerFormSheet extends StatefulWidget {
  final CustomerEntity? existing;
  final String tenantId;
  final ValueChanged<CustomerEntity> onSaved;

  const CustomerFormSheet({
    super.key,
    this.existing,
    required this.tenantId,
    required this.onSaved,
  });

  @override
  State<CustomerFormSheet> createState() => _CustomerFormSheetState();
}

class _CustomerFormSheetState extends State<CustomerFormSheet> {
  final _nameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  String _tier = 'RETAIL';
  String? _error;

  @override
  void initState() {
    super.initState();
    final c = widget.existing;
    if (c != null) {
      _nameCtrl.text = c.name;
      _phoneCtrl.text = c.phone;
      _tier = c.pricingTier;
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    super.dispose();
  }

  void _save() {
    if (_nameCtrl.text.trim().isEmpty) {
      setState(() => _error = 'Customer name is required.');
      return;
    }
    if (_phoneCtrl.text.trim().isEmpty) {
      setState(() => _error = 'Phone number is required.');
      return;
    }

    final customer = widget.existing ??
        CustomerEntity(
          tenantId: widget.tenantId,
          name: '',
          phone: '',
        );

    customer
      ..name = _nameCtrl.text.trim()
      ..phone = _phoneCtrl.text.trim()
      ..pricingTier = _tier;

    widget.onSaved(customer);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
        left: 24,
        right: 24,
        top: 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                  color: AppTheme.border,
                  borderRadius: BorderRadius.circular(2)),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            widget.existing != null ? 'Edit Customer' : 'New Customer',
            style: const TextStyle(
                color: AppTheme.textPrimary,
                fontSize: 20,
                fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 24),
          const Text('Full Name',
              style: TextStyle(
                  color: AppTheme.textSecondary,
                  fontSize: 12,
                  fontWeight: FontWeight.w500)),
          const SizedBox(height: 8),
          TextField(
            controller: _nameCtrl,
            style: const TextStyle(color: AppTheme.textPrimary),
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              hintText: 'e.g. Kamal Perera',
              prefixIcon: Icon(Icons.person_outline, color: AppTheme.textMuted),
            ),
          ),
          const SizedBox(height: 16),
          const Text('Phone',
              style: TextStyle(
                  color: AppTheme.textSecondary,
                  fontSize: 12,
                  fontWeight: FontWeight.w500)),
          const SizedBox(height: 8),
          TextField(
            controller: _phoneCtrl,
            keyboardType: TextInputType.phone,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            style: const TextStyle(color: AppTheme.textPrimary),
            decoration: const InputDecoration(
              hintText: '07XXXXXXXX',
              prefixIcon: Icon(Icons.phone_outlined, color: AppTheme.textMuted),
            ),
          ),
          const SizedBox(height: 16),
          const Text('Pricing Tier',
              style: TextStyle(
                  color: AppTheme.textSecondary,
                  fontSize: 12,
                  fontWeight: FontWeight.w500)),
          const SizedBox(height: 8),
          Row(
            children: ['RETAIL', 'WHOLESALE'].map((t) {
              final isSelected = _tier == t;
              final color = t == 'WHOLESALE' ? AppTheme.primary : AppTheme.lkr;
              return Expanded(
                child: GestureDetector(
                  onTap: () => setState(() => _tier = t),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    margin: EdgeInsets.only(right: t == 'RETAIL' ? 8 : 0),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? color.withOpacity(0.15)
                          : AppTheme.surfaceDeep,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isSelected ? color : AppTheme.border,
                        width: isSelected ? 1.5 : 1,
                      ),
                    ),
                    child: Center(
                      child: Text(
                        t,
                        style: TextStyle(
                          color: isSelected ? color : AppTheme.textMuted,
                          fontWeight: isSelected
                              ? FontWeight.bold
                              : FontWeight.normal,
                        ),
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!,
                style: const TextStyle(color: AppTheme.error, fontSize: 13)),
          ],
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              onPressed: _save,
              child: Text(widget.existing != null
                  ? 'Save Changes'
                  : 'Add Customer'),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// DebtAdjustSheet — record payment / add debt
// ─────────────────────────────────────────────────────────────

class DebtAdjustSheet extends StatefulWidget {
  final CustomerEntity customer;
  final ValueChanged<CustomerEntity> onSaved;

  const DebtAdjustSheet(
      {super.key, required this.customer, required this.onSaved});

  @override
  State<DebtAdjustSheet> createState() => _DebtAdjustSheetState();
}

class _DebtAdjustSheetState extends State<DebtAdjustSheet> {
  final _amountCtrl = TextEditingController();
  String _mode = 'payment'; // 'payment' or 'charge'
  String? _error;

  @override
  void dispose() {
    _amountCtrl.dispose();
    super.dispose();
  }

  void _apply() {
    final amount = double.tryParse(_amountCtrl.text);
    if (amount == null || amount <= 0) {
      setState(() => _error = 'Enter a valid amount.');
      return;
    }
    final updated = widget.customer;
    if (_mode == 'payment') {
      updated.currentDebt = (updated.currentDebt - amount).clamp(0, double.infinity);
    } else {
      updated.currentDebt += amount;
    }
    widget.onSaved(updated);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final debt = widget.customer.currentDebt;
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
        left: 24,
        right: 24,
        top: 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40, height: 4,
              decoration: BoxDecoration(
                  color: AppTheme.border,
                  borderRadius: BorderRadius.circular(2)),
            ),
          ),
          const SizedBox(height: 20),
          Text(widget.customer.name,
              style: const TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: 20,
                  fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Row(
            children: [
              const Text('Current debt: ',
                  style: TextStyle(
                      color: AppTheme.textSecondary, fontSize: 14)),
              Text(
                'Rs.${NumberFormat('#,##0.00').format(debt)}',
                style: TextStyle(
                  color: debt > 0 ? AppTheme.error : AppTheme.success,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: _ModeButton(
                  label: 'Record Payment',
                  icon: Icons.payment_rounded,
                  selected: _mode == 'payment',
                  color: AppTheme.success,
                  onTap: () => setState(() => _mode = 'payment'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _ModeButton(
                  label: 'Add Charge',
                  icon: Icons.add_circle_outline,
                  selected: _mode == 'charge',
                  color: AppTheme.error,
                  onTap: () => setState(() => _mode = 'charge'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _amountCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            style: const TextStyle(color: AppTheme.textPrimary, fontSize: 22, fontWeight: FontWeight.bold),
            decoration: InputDecoration(
              hintText: '0.00',
              prefixText: 'Rs. ',
              prefixStyle: const TextStyle(color: AppTheme.textSecondary, fontSize: 22),
              hintStyle: const TextStyle(color: AppTheme.border),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: AppTheme.border),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: AppTheme.border),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: AppTheme.primary, width: 1.5),
              ),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 10),
            Text(_error!, style: const TextStyle(color: AppTheme.error, fontSize: 13)),
          ],
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: _mode == 'payment' ? AppTheme.success : AppTheme.error,
              ),
              onPressed: _apply,
              child: Text(
                _mode == 'payment' ? 'Record Payment' : 'Add Charge',
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final Color? color;
  final VoidCallback onTap;

  const _FilterChip({
    required this.label,
    required this.selected,
    this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = color ?? AppTheme.primary;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? c.withOpacity(0.15) : AppTheme.surfaceDeep,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: selected ? c : AppTheme.border),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? c : AppTheme.textMuted,
            fontSize: 12,
            fontWeight: selected ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
  }
}

class _ModeButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final Color color;
  final VoidCallback onTap;

  const _ModeButton({
    required this.label,
    required this.icon,
    required this.selected,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: selected ? color.withOpacity(0.12) : AppTheme.surfaceDeep,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? color : AppTheme.border,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Column(
          children: [
            Icon(icon, color: selected ? color : AppTheme.textMuted, size: 22),
            const SizedBox(height: 4),
            Text(label,
                style: TextStyle(
                    color: selected ? color : AppTheme.textMuted,
                    fontSize: 12,
                    fontWeight:
                        selected ? FontWeight.bold : FontWeight.normal)),
          ],
        ),
      ),
    );
  }
}
