// lib/ui/settings/settings_page.dart
// Full settings page — Worker secret, stock rules, receipt, printer, CSV export, sign-out

import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/di/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../data/local/models/objectbox_models.dart';

// ─────────────────────────────────────────────────────────────
// App settings provider (loaded from Supabase tenants.app_settings)
// ─────────────────────────────────────────────────────────────

final appSettingsProvider =
    StateNotifierProvider<AppSettingsNotifier, AppSettings>((ref) {
  return AppSettingsNotifier(ref);
});

class AppSettings {
  final bool allowNegativeStock;
  final String defaultCurrency;
  final String receiptFooter;
  final String workerSecret;
  final bool thermalPrinterEnabled;
  final String thermalPrinterMac;

  const AppSettings({
    this.allowNegativeStock = false,
    this.defaultCurrency = 'LKR',
    this.receiptFooter = 'Thank you for shopping!',
    this.workerSecret = '',
    this.thermalPrinterEnabled = false,
    this.thermalPrinterMac = '',
  });

  AppSettings copyWith({
    bool? allowNegativeStock,
    String? defaultCurrency,
    String? receiptFooter,
    String? workerSecret,
    bool? thermalPrinterEnabled,
    String? thermalPrinterMac,
  }) =>
      AppSettings(
        allowNegativeStock: allowNegativeStock ?? this.allowNegativeStock,
        defaultCurrency: defaultCurrency ?? this.defaultCurrency,
        receiptFooter: receiptFooter ?? this.receiptFooter,
        workerSecret: workerSecret ?? this.workerSecret,
        thermalPrinterEnabled:
            thermalPrinterEnabled ?? this.thermalPrinterEnabled,
        thermalPrinterMac: thermalPrinterMac ?? this.thermalPrinterMac,
      );

  Map<String, dynamic> toJson() => {
        'allow_negative_stock': allowNegativeStock,
        'default_currency': defaultCurrency,
        'receipt_footer': receiptFooter,
        'worker_secret': workerSecret,
        'thermal_printer_enabled': thermalPrinterEnabled,
        'thermal_printer_mac': thermalPrinterMac,
      };

  factory AppSettings.fromJson(Map<String, dynamic> json) => AppSettings(
        allowNegativeStock: json['allow_negative_stock'] as bool? ?? false,
        defaultCurrency: json['default_currency'] as String? ?? 'LKR',
        receiptFooter:
            json['receipt_footer'] as String? ?? 'Thank you for shopping!',
        workerSecret: json['worker_secret'] as String? ?? '',
        thermalPrinterEnabled:
            json['thermal_printer_enabled'] as bool? ?? false,
        thermalPrinterMac: json['thermal_printer_mac'] as String? ?? '',
      );
}

class AppSettingsNotifier extends StateNotifier<AppSettings> {
  final Ref _ref;
  AppSettingsNotifier(this._ref) : super(const AppSettings()) {
    _load();
  }

  Future<void> _load() async {
    final tenantId = _ref.read(tenantIdProvider);
    if (tenantId == null) return;
    try {
      final supabase = _ref.read(supabaseProvider);
      final row = await supabase
          .from('tenants')
          .select('app_settings')
          .eq('tenant_id', tenantId)
          .single();
      final json = row['app_settings'] as Map<String, dynamic>? ?? {};
      state = AppSettings.fromJson(json);
    } catch (_) {}
  }

  Future<void> save(AppSettings updated) async {
    state = updated;
    final tenantId = _ref.read(tenantIdProvider);
    if (tenantId == null) return;
    try {
      final supabase = _ref.read(supabaseProvider);
      await supabase.from('tenants').update({
        'app_settings': updated.toJson(),
      }).eq('tenant_id', tenantId);

      // Update secure storage for Worker secret
      if (updated.workerSecret.isNotEmpty) {
        await _ref
            .read(syncServiceProvider)
            .storeAuthToken(updated.workerSecret);
      }
    } catch (_) {}
  }
}

// ─────────────────────────────────────────────────────────────
// CSV export helper
// ─────────────────────────────────────────────────────────────

Future<void> _exportInvoicesCsv(BuildContext context, WidgetRef ref) async {
  final invoiceBox = ref.read(invoiceBoxProvider);
  final lineItemBox = ref.read(lineItemBoxProvider);
  final itemBox = ref.read(itemBoxProvider);
  final customerBox = ref.read(customerBoxProvider);

  final invoices = invoiceBox.getAll();
  if (invoices.isEmpty) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No invoices to export.')),
      );
    }
    return;
  }

  final buf = StringBuffer();
  buf.writeln(
      'Invoice ULID,Date,Customer,Payment Mode,Total,Item,Qty,Unit Price,Tier');

  for (final inv in invoices) {
    final customer = inv.customerId != null
        ? customerBox
            .query(CustomerEntity_.remoteId.equals(inv.customerId!))
            .build()
            .findFirst()
        : null;
    final customerName = customer?.name ?? 'Walk-in';

    final lines = lineItemBox
        .query(LineItemEntity_.invoice.equals(inv.id))
        .build()
        .find();

    if (lines.isEmpty) {
      buf.writeln([
        inv.ulid,
        DateFormat('yyyy-MM-dd HH:mm').format(inv.createdAtLocal),
        customerName,
        inv.paymentMode,
        inv.totalAmount.toStringAsFixed(2),
        '',
        '',
        '',
        '',
      ].join(','));
    } else {
      for (final li in lines) {
        final item = itemBox
            .query(ItemEntity_.remoteId.equals(li.itemId))
            .build()
            .findFirst();
        final names = item != null
            ? jsonDecode(item.nameTranslationsJson) as Map<String, dynamic>
            : <String, dynamic>{};
        final itemName =
            (names['en'] as String?)?.replaceAll(',', ' ') ?? li.itemId;

        buf.writeln([
          inv.ulid,
          DateFormat('yyyy-MM-dd HH:mm').format(inv.createdAtLocal),
          customerName.replaceAll(',', ' '),
          inv.paymentMode,
          inv.totalAmount.toStringAsFixed(2),
          itemName,
          li.qty.toStringAsFixed(2),
          li.unitPrice.toStringAsFixed(2),
          li.pricingTier,
        ].join(','));
      }
    }
  }

  try {
    final dir = await getTemporaryDirectory();
    final file = File(
        '${dir.path}/smartbiz_export_${DateFormat('yyyyMMdd_HHmm').format(DateTime.now())}.csv');
    await file.writeAsString(buf.toString());
    await Share.shareXFiles(
      [XFile(file.path)],
      subject: 'SmartBiz Invoice Export',
    );
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Export failed: $e')),
      );
    }
  }
}

// ─────────────────────────────────────────────────────────────
// SettingsPage
// ─────────────────────────────────────────────────────────────

class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key});

  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
  bool _workerSecretVisible = false;
  bool _isSaving = false;

  late TextEditingController _workerSecretCtrl;
  late TextEditingController _receiptFooterCtrl;
  late TextEditingController _printerMacCtrl;

  @override
  void initState() {
    super.initState();
    final s = ref.read(appSettingsProvider);
    _workerSecretCtrl = TextEditingController(text: s.workerSecret);
    _receiptFooterCtrl = TextEditingController(text: s.receiptFooter);
    _printerMacCtrl = TextEditingController(text: s.thermalPrinterMac);
  }

  @override
  void dispose() {
    _workerSecretCtrl.dispose();
    _receiptFooterCtrl.dispose();
    _printerMacCtrl.dispose();
    super.dispose();
  }

  Future<void> _saveSettings() async {
    setState(() => _isSaving = true);
    final current = ref.read(appSettingsProvider);
    await ref.read(appSettingsProvider.notifier).save(
          current.copyWith(
            workerSecret: _workerSecretCtrl.text.trim(),
            receiptFooter: _receiptFooterCtrl.text.trim(),
            thermalPrinterMac: _printerMacCtrl.text.trim(),
          ),
        );
    if (mounted) {
      setState(() => _isSaving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Settings saved.'),
          backgroundColor: AppTheme.success,
        ),
      );
    }
  }

  Future<void> _signOut() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppTheme.surface,
        title: const Text('Sign Out',
            style: TextStyle(color: AppTheme.textPrimary)),
        content: const Text('Are you sure you want to sign out?',
            style: TextStyle(color: AppTheme.textSecondary)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel',
                style: TextStyle(color: AppTheme.textMuted)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Sign Out',
                style: TextStyle(color: AppTheme.error)),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await Supabase.instance.client.auth.signOut();
      if (mounted) context.go('/login');
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(appSettingsProvider);
    final user = ref.watch(currentUserProvider);
    final syncStatus = ref.watch(syncServiceProvider).syncStatus;
    final lastSync = ref.watch(syncServiceProvider).lastSyncTime;

    return Scaffold(
      backgroundColor: AppTheme.surfaceDeep,
      appBar: AppBar(
        backgroundColor: AppTheme.surface,
        title: const Text('Settings'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: TextButton(
              onPressed: _isSaving ? null : _saveSettings,
              child: _isSaving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          color: AppTheme.primary, strokeWidth: 2))
                  : const Text('Save',
                      style: TextStyle(
                          color: AppTheme.primary,
                          fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ── Account card ─────────────────────────────────────
          _Card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    CircleAvatar(
                      backgroundColor: AppTheme.primary.withOpacity(0.15),
                      radius: 22,
                      child: Text(
                        (user?.email ?? '?')[0].toUpperCase(),
                        style: const TextStyle(
                            color: AppTheme.primary,
                            fontWeight: FontWeight.bold,
                            fontSize: 18),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            user?.email ?? 'Unknown',
                            style: const TextStyle(
                                color: AppTheme.textPrimary,
                                fontWeight: FontWeight.w600,
                                fontSize: 15),
                          ),
                          const SizedBox(height: 2),
                          ValueListenableBuilder(
                            valueListenable: lastSync,
                            builder: (_, dt, __) => Text(
                              dt != null
                                  ? 'Last sync: ${DateFormat('d MMM, HH:mm').format(dt)}'
                                  : 'Never synced',
                              style: const TextStyle(
                                  color: AppTheme.textMuted, fontSize: 12),
                            ),
                          ),
                        ],
                      ),
                    ),
                    ValueListenableBuilder(
                      valueListenable: syncStatus,
                      builder: (_, status, __) => GestureDetector(
                        onTap: () => ref.read(syncServiceProvider).triggerSync(),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: _syncColor(status).withOpacity(0.12),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(_syncIcon(status),
                                  color: _syncColor(status), size: 14),
                              const SizedBox(width: 4),
                              Text(
                                _syncLabel(status),
                                style: TextStyle(
                                    color: _syncColor(status),
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // ── Cloudflare Worker ─────────────────────────────────
          _SectionHeader('Cloudflare Worker'),
          const SizedBox(height: 10),
          _Card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Worker Auth Secret',
                  style: TextStyle(
                      color: AppTheme.textSecondary,
                      fontSize: 12,
                      fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _workerSecretCtrl,
                  obscureText: !_workerSecretVisible,
                  style: const TextStyle(
                      color: AppTheme.textPrimary,
                      fontFamily: 'monospace',
                      fontSize: 13),
                  decoration: InputDecoration(
                    hintText: 'Paste your WORKER_AUTH_SECRET',
                    suffixIcon: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: Icon(
                            _workerSecretVisible
                                ? Icons.visibility_off_outlined
                                : Icons.visibility_outlined,
                            color: AppTheme.textMuted,
                            size: 20,
                          ),
                          onPressed: () => setState(
                              () => _workerSecretVisible = !_workerSecretVisible),
                        ),
                        IconButton(
                          icon: const Icon(Icons.copy_outlined,
                              color: AppTheme.textMuted, size: 18),
                          onPressed: () {
                            Clipboard.setData(ClipboardData(
                                text: _workerSecretCtrl.text));
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                  content: Text('Copied to clipboard')),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                const Text(
                  'Set this via: wrangler secret put WORKER_AUTH_SECRET',
                  style: TextStyle(color: AppTheme.textMuted, fontSize: 11),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // ── Stock & Sales Rules ───────────────────────────────
          _SectionHeader('Stock & Sales Rules'),
          const SizedBox(height: 10),
          _Card(
            child: Column(
              children: [
                _ToggleRow(
                  label: 'Allow Negative Stock',
                  sublabel:
                      'Allow sales even when qty reaches 0',
                  value: settings.allowNegativeStock,
                  onChanged: (v) => ref
                      .read(appSettingsProvider.notifier)
                      .save(settings.copyWith(allowNegativeStock: v)),
                ),
                const Divider(color: AppTheme.border, height: 24),
                _ToggleRow(
                  label: 'Thermal Printer',
                  sublabel: 'Enable Bluetooth receipt printing',
                  value: settings.thermalPrinterEnabled,
                  onChanged: (v) => ref
                      .read(appSettingsProvider.notifier)
                      .save(settings.copyWith(thermalPrinterEnabled: v)),
                ),
                if (settings.thermalPrinterEnabled) ...[
                  const SizedBox(height: 14),
                  const Text(
                    'Printer Bluetooth MAC Address',
                    style: TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: 12,
                        fontWeight: FontWeight.w500),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _printerMacCtrl,
                    style: const TextStyle(
                        color: AppTheme.textPrimary,
                        fontFamily: 'monospace',
                        fontSize: 13),
                    inputFormatters: [
                      TextInputFormatter.withFunction((old, nw) {
                        final cleaned =
                            nw.text.replaceAll(RegExp(r'[^0-9A-Fa-f:]'), '');
                        return nw.copyWith(text: cleaned.toUpperCase());
                      }),
                    ],
                    decoration: const InputDecoration(
                      hintText: 'AA:BB:CC:DD:EE:FF',
                      prefixIcon: Icon(Icons.bluetooth_rounded,
                          color: AppTheme.primary, size: 20),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 20),

          // ── Receipt Footer ────────────────────────────────────
          _SectionHeader('Receipt'),
          const SizedBox(height: 10),
          _Card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Footer Message',
                  style: TextStyle(
                      color: AppTheme.textSecondary,
                      fontSize: 12,
                      fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _receiptFooterCtrl,
                  maxLines: 3,
                  style: const TextStyle(color: AppTheme.textPrimary),
                  decoration: const InputDecoration(
                    hintText: 'e.g. Thank you for shopping with us!',
                  ),
                ),
                const SizedBox(height: 10),
                const Text(
                  'This message prints at the bottom of every receipt.',
                  style:
                      TextStyle(color: AppTheme.textMuted, fontSize: 11),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // ── Data & Export ─────────────────────────────────────
          _SectionHeader('Data & Export'),
          const SizedBox(height: 10),
          _Card(
            child: Column(
              children: [
                _ActionRow(
                  icon: Icons.download_rounded,
                  iconColor: AppTheme.lkr,
                  label: 'Export Invoices as CSV',
                  sublabel: 'Share all local invoices as a spreadsheet',
                  onTap: () => _exportInvoicesCsv(context, ref),
                ),
                const Divider(color: AppTheme.border, height: 24),
                _ActionRow(
                  icon: Icons.sync_rounded,
                  iconColor: AppTheme.primary,
                  label: 'Force Sync Now',
                  sublabel: 'Push all pending invoices to server',
                  onTap: () async {
                    await ref.read(syncServiceProvider).triggerSync();
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Sync triggered.'),
                          backgroundColor: AppTheme.success,
                        ),
                      );
                    }
                  },
                ),
                const Divider(color: AppTheme.border, height: 24),
                _ActionRow(
                  icon: Icons.delete_sweep_outlined,
                  iconColor: AppTheme.warning,
                  label: 'Clear Synced Invoices',
                  sublabel: 'Remove invoices that have been pushed to cloud',
                  onTap: () => _confirmClearSynced(context, ref),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // ── App Info ──────────────────────────────────────────
          _SectionHeader('About'),
          const SizedBox(height: 10),
          _Card(
            child: Column(
              children: [
                _InfoRow(label: 'App Version', value: '1.0.0'),
                const Divider(color: AppTheme.border, height: 20),
                _InfoRow(label: 'Platform', value: 'Flutter + Supabase + Cloudflare Workers'),
                const Divider(color: AppTheme.border, height: 20),
                _InfoRow(
                    label: 'Database',
                    value: 'ObjectBox (local) + PostgreSQL (cloud)'),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // ── Sign out ──────────────────────────────────────────
          SizedBox(
            width: double.infinity,
            height: 52,
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: AppTheme.error,
                side: const BorderSide(color: AppTheme.error),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
              icon: const Icon(Icons.logout_rounded),
              label: const Text('Sign Out'),
              onPressed: _signOut,
            ),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Future<void> _confirmClearSynced(
      BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppTheme.surface,
        title: const Text('Clear Synced Data',
            style: TextStyle(color: AppTheme.textPrimary)),
        content: const Text(
          'This will remove all invoices that have already been synced to the cloud. Unsynced invoices will be kept. This cannot be undone.',
          style: TextStyle(color: AppTheme.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel',
                style: TextStyle(color: AppTheme.textMuted)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Clear',
                style: TextStyle(color: AppTheme.warning)),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      final invoiceBox = ref.read(invoiceBoxProvider);
      final synced = invoiceBox
          .query(InvoiceEntity_.isSynced.equals(true))
          .build()
          .find();
      invoiceBox.removeMany(synced.map((i) => i.id).toList());
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Removed ${synced.length} synced invoices.'),
            backgroundColor: AppTheme.success,
          ),
        );
      }
    }
  }

  Color _syncColor(SyncStatus status) {
    switch (status) {
      case SyncStatus.syncing:
        return AppTheme.warning;
      case SyncStatus.error:
        return AppTheme.error;
      case SyncStatus.idle:
        return AppTheme.success;
    }
  }

  IconData _syncIcon(SyncStatus status) {
    switch (status) {
      case SyncStatus.syncing:
        return Icons.sync_rounded;
      case SyncStatus.error:
        return Icons.sync_problem_rounded;
      case SyncStatus.idle:
        return Icons.cloud_done_rounded;
    }
  }

  String _syncLabel(SyncStatus status) {
    switch (status) {
      case SyncStatus.syncing:
        return 'Syncing…';
      case SyncStatus.error:
        return 'Error';
      case SyncStatus.idle:
        return 'Synced';
    }
  }
}

// ─────────────────────────────────────────────────────────────
// Reusable setting widgets
// ─────────────────────────────────────────────────────────────

class _Card extends StatelessWidget {
  final Widget child;
  const _Card({required this.child});

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppTheme.border),
        ),
        child: child,
      );
}

class _SectionHeader extends StatelessWidget {
  final String text;
  const _SectionHeader(this.text);

  @override
  Widget build(BuildContext context) => Text(
        text.toUpperCase(),
        style: const TextStyle(
          color: AppTheme.textMuted,
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.0,
        ),
      );
}

class _ToggleRow extends StatelessWidget {
  final String label;
  final String sublabel;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _ToggleRow({
    required this.label,
    required this.sublabel,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: const TextStyle(
                        color: AppTheme.textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w500)),
                const SizedBox(height: 2),
                Text(sublabel,
                    style: const TextStyle(
                        color: AppTheme.textMuted, fontSize: 12)),
              ],
            ),
          ),
          Switch.adaptive(
            value: value,
            onChanged: onChanged,
            activeColor: AppTheme.primary,
          ),
        ],
      );
}

class _ActionRow extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String label;
  final String sublabel;
  final VoidCallback onTap;

  const _ActionRow({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.sublabel,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: iconColor.withOpacity(0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: iconColor, size: 20),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: const TextStyle(
                          color: AppTheme.textPrimary,
                          fontSize: 14,
                          fontWeight: FontWeight.w500)),
                  Text(sublabel,
                      style: const TextStyle(
                          color: AppTheme.textMuted, fontSize: 12)),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded,
                color: AppTheme.textMuted, size: 20),
          ],
        ),
      );
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;

  const _InfoRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) => Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: const TextStyle(
                  color: AppTheme.textSecondary, fontSize: 13)),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: const TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: 13,
                  fontWeight: FontWeight.w500),
            ),
          ),
        ],
      );
}
