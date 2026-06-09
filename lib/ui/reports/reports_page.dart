// lib/ui/reports/reports_page.dart
// Sales reports dashboard — daily totals, top items, payment breakdown

import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:objectbox/objectbox.dart';

import '../../core/di/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../data/local/models/objectbox_models.dart';
import '../../objectbox.g.dart';

// ─────────────────────────────────────────────────────────────
// Data models
// ─────────────────────────────────────────────────────────────

class DailySales {
  final DateTime date;
  final double total;
  final int invoiceCount;
  DailySales(this.date, this.total, this.invoiceCount);
}

class TopItem {
  final String name;
  final double totalQty;
  final double totalRevenue;
  TopItem(this.name, this.totalQty, this.totalRevenue);
}

// ─────────────────────────────────────────────────────────────
// Report period provider
// ─────────────────────────────────────────────────────────────

final reportPeriodProvider = StateProvider<int>((ref) => 7); // days

final reportDataProvider = Provider<_ReportData>((ref) {
  final invoiceBox = ref.watch(invoiceBoxProvider);
  final lineItemBox = ref.watch(lineItemBoxProvider);
  final itemBox = ref.watch(itemBoxProvider);
  final days = ref.watch(reportPeriodProvider);

  final cutoff = DateTime.now().subtract(Duration(days: days));

  final invoices = invoiceBox
      .query(InvoiceEntity_.createdAtLocal.greaterThan(cutoff.millisecondsSinceEpoch))
      .order(InvoiceEntity_.createdAtLocal)
      .build()
      .find();

  // Daily aggregation
  final dailyMap = <String, DailySales>{};
  for (final inv in invoices) {
    final key = DateFormat('yyyy-MM-dd').format(inv.createdAtLocal);
    final existing = dailyMap[key];
    if (existing == null) {
      dailyMap[key] = DailySales(inv.createdAtLocal, inv.totalAmount, 1);
    } else {
      dailyMap[key] = DailySales(
        existing.date,
        existing.total + inv.totalAmount,
        existing.invoiceCount + 1,
      );
    }
  }

  // Fill in missing days with 0
  final allDays = <DailySales>[];
  for (var i = days - 1; i >= 0; i--) {
    final d = DateTime.now().subtract(Duration(days: i));
    final key = DateFormat('yyyy-MM-dd').format(d);
    allDays.add(dailyMap[key] ?? DailySales(d, 0, 0));
  }

  // Payment mode breakdown
  final paymentMap = <String, double>{};
  for (final inv in invoices) {
    paymentMap[inv.paymentMode] =
        (paymentMap[inv.paymentMode] ?? 0) + inv.totalAmount;
  }

  // Top items by revenue
  final itemRevMap = <String, double>{};
  final itemQtyMap = <String, double>{};
  final invoiceIds = invoices.map((i) => i.id).toList();

  if (invoiceIds.isNotEmpty) {
    final lines = lineItemBox
        .query()
        .build()
        .find()
        .where((li) => invoiceIds.contains(li.invoice.targetId))
        .toList();

    for (final li in lines) {
      final revenue = li.unitPrice * li.qty;
      itemRevMap[li.itemId] = (itemRevMap[li.itemId] ?? 0) + revenue;
      itemQtyMap[li.itemId] = (itemQtyMap[li.itemId] ?? 0) + li.qty;
    }
  }

  final topItems = itemRevMap.entries
      .map((e) {
        final item = itemBox
            .query(ItemEntity_.remoteId.equals(e.key))
            .build()
            .findFirst();
        final names = item != null
            ? jsonDecode(item.nameTranslationsJson) as Map<String, dynamic>
            : <String, dynamic>{};
        final name = names['si'] as String? ??
            names['en'] as String? ??
            e.key.substring(0, 8);
        return TopItem(name, itemQtyMap[e.key] ?? 0, e.value);
      })
      .toList()
    ..sort((a, b) => b.totalRevenue.compareTo(a.totalRevenue));

  return _ReportData(
    dailySales: allDays,
    paymentBreakdown: paymentMap,
    topItems: topItems.take(5).toList(),
    totalRevenue: invoices.fold(0, (s, i) => s + i.totalAmount),
    totalInvoices: invoices.length,
    averageOrder: invoices.isEmpty
        ? 0
        : invoices.fold(0.0, (s, i) => s + i.totalAmount) / invoices.length,
  );
});

class _ReportData {
  final List<DailySales> dailySales;
  final Map<String, double> paymentBreakdown;
  final List<TopItem> topItems;
  final double totalRevenue;
  final int totalInvoices;
  final double averageOrder;

  _ReportData({
    required this.dailySales,
    required this.paymentBreakdown,
    required this.topItems,
    required this.totalRevenue,
    required this.totalInvoices,
    required this.averageOrder,
  });
}

// ─────────────────────────────────────────────────────────────
// ReportsPage
// ─────────────────────────────────────────────────────────────

class ReportsPage extends ConsumerWidget {
  const ReportsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final period = ref.watch(reportPeriodProvider);
    final data = ref.watch(reportDataProvider);
    final fmt = NumberFormat('#,##0.00');

    return Scaffold(
      backgroundColor: AppTheme.surfaceDeep,
      appBar: AppBar(
        backgroundColor: AppTheme.surface,
        title: const Text('Reports'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: DropdownButton<int>(
              value: period,
              dropdownColor: AppTheme.surface,
              underline: const SizedBox(),
              style: const TextStyle(color: AppTheme.textPrimary, fontSize: 13),
              items: const [
                DropdownMenuItem(value: 7, child: Text('Last 7 days')),
                DropdownMenuItem(value: 14, child: Text('Last 14 days')),
                DropdownMenuItem(value: 30, child: Text('Last 30 days')),
              ],
              onChanged: (v) =>
                  ref.read(reportPeriodProvider.notifier).state = v!,
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ── KPI cards ───────────────────────────────────────
          Row(
            children: [
              _KpiCard(
                label: 'Revenue',
                value: 'Rs.${fmt.format(data.totalRevenue)}',
                icon: Icons.trending_up_rounded,
                color: AppTheme.lkr,
              ),
              const SizedBox(width: 12),
              _KpiCard(
                label: 'Invoices',
                value: '${data.totalInvoices}',
                icon: Icons.receipt_long_outlined,
                color: AppTheme.primary,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _KpiCard(
                label: 'Avg. Order',
                value: 'Rs.${fmt.format(data.averageOrder)}',
                icon: Icons.bar_chart_rounded,
                color: AppTheme.warning,
              ),
              const SizedBox(width: 12),
              _KpiCard(
                label: 'Best Day',
                value: data.dailySales.isEmpty
                    ? '-'
                    : 'Rs.${fmt.format(data.dailySales.map((d) => d.total).reduce(math.max))}',
                icon: Icons.star_outline_rounded,
                color: const Color(0xFFE879F9),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // ── Daily sales bar chart (custom canvas) ───────────
          _SectionTitle('Daily Sales'),
          const SizedBox(height: 12),
          Container(
            height: 200,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppTheme.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppTheme.border),
            ),
            child: data.dailySales.every((d) => d.total == 0)
                ? const Center(
                    child: Text('No sales in this period',
                        style: TextStyle(color: AppTheme.textMuted)))
                : _BarChart(dailySales: data.dailySales),
          ),
          const SizedBox(height: 24),

          // ── Payment breakdown ───────────────────────────────
          _SectionTitle('Payment Breakdown'),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppTheme.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppTheme.border),
            ),
            child: data.paymentBreakdown.isEmpty
                ? const Center(
                    child: Text('No data',
                        style: TextStyle(color: AppTheme.textMuted)))
                : Column(
                    children: data.paymentBreakdown.entries.map((e) {
                      final pct = data.totalRevenue > 0
                          ? e.value / data.totalRevenue
                          : 0.0;
                      final color = _paymentColor(e.key);
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Row(
                                  children: [
                                    Container(
                                      width: 10,
                                      height: 10,
                                      decoration: BoxDecoration(
                                        color: color,
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      e.key.replaceAll('_', ' '),
                                      style: const TextStyle(
                                          color: AppTheme.textPrimary,
                                          fontSize: 13),
                                    ),
                                  ],
                                ),
                                Text(
                                  'Rs.${fmt.format(e.value)}  (${(pct * 100).toStringAsFixed(1)}%)',
                                  style: const TextStyle(
                                      color: AppTheme.textSecondary,
                                      fontSize: 12),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(4),
                              child: LinearProgressIndicator(
                                value: pct,
                                backgroundColor: color.withOpacity(0.12),
                                valueColor:
                                    AlwaysStoppedAnimation<Color>(color),
                                minHeight: 6,
                              ),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                  ),
          ),
          const SizedBox(height: 24),

          // ── Top 5 items ─────────────────────────────────────
          _SectionTitle('Top 5 Items by Revenue'),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppTheme.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppTheme.border),
            ),
            child: data.topItems.isEmpty
                ? const Center(
                    child: Text('No data',
                        style: TextStyle(color: AppTheme.textMuted)))
                : Column(
                    children: data.topItems.asMap().entries.map((e) {
                      final rank = e.key + 1;
                      final item = e.value;
                      final maxRev = data.topItems.first.totalRevenue;
                      final pct =
                          maxRev > 0 ? item.totalRevenue / maxRev : 0.0;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 14),
                        child: Row(
                          children: [
                            SizedBox(
                              width: 24,
                              child: Text(
                                '#$rank',
                                style: TextStyle(
                                  color: rank == 1
                                      ? AppTheme.warning
                                      : AppTheme.textMuted,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        item.name,
                                        style: const TextStyle(
                                            color: AppTheme.textPrimary,
                                            fontSize: 13,
                                            fontWeight: FontWeight.w500),
                                      ),
                                      Text(
                                        'Rs.${fmt.format(item.totalRevenue)}',
                                        style: const TextStyle(
                                            color: AppTheme.lkr,
                                            fontSize: 12,
                                            fontWeight: FontWeight.bold),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 5),
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(4),
                                    child: LinearProgressIndicator(
                                      value: pct,
                                      backgroundColor:
                                          AppTheme.primary.withOpacity(0.12),
                                      valueColor:
                                          const AlwaysStoppedAnimation<Color>(
                                              AppTheme.primary),
                                      minHeight: 5,
                                    ),
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    'Qty sold: ${item.totalQty.toStringAsFixed(item.totalQty % 1 == 0 ? 0 : 2)}',
                                    style: const TextStyle(
                                        color: AppTheme.textMuted,
                                        fontSize: 10),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                  ),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Color _paymentColor(String mode) {
    switch (mode) {
      case 'CASH':
        return AppTheme.lkr;
      case 'CARD_TAP':
        return AppTheme.primary;
      case 'LANKAQR':
        return AppTheme.warning;
      case 'CREDIT':
        return AppTheme.error;
      default:
        return AppTheme.textMuted;
    }
  }
}

// ─────────────────────────────────────────────────────────────
// Custom bar chart widget (no external chart library needed)
// ─────────────────────────────────────────────────────────────

class _BarChart extends StatelessWidget {
  final List<DailySales> dailySales;
  const _BarChart({required this.dailySales});

  @override
  Widget build(BuildContext context) {
    final maxVal = dailySales.map((d) => d.total).reduce(math.max);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: dailySales.asMap().entries.map((e) {
        final i = e.key;
        final d = e.value;
        final heightPct = maxVal > 0 ? d.total / maxVal : 0.0;
        final isToday = DateFormat('yyyy-MM-dd').format(d.date) ==
            DateFormat('yyyy-MM-dd').format(DateTime.now());

        return Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (d.total > 0)
                  Tooltip(
                    message: 'Rs.${NumberFormat('#,##0').format(d.total)}\n${d.invoiceCount} sales',
                    child: AnimatedContainer(
                      duration: Duration(milliseconds: 300 + i * 30),
                      curve: Curves.easeOut,
                      height: (140 * heightPct).clamp(4, 140),
                      decoration: BoxDecoration(
                        color: isToday ? AppTheme.primary : AppTheme.primary.withOpacity(0.5),
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                      ),
                    ),
                  )
                else
                  Container(
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppTheme.border,
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(2)),
                    ),
                  ),
                const SizedBox(height: 4),
                Text(
                  DateFormat(dailySales.length > 14 ? 'd' : 'E').format(d.date),
                  style: TextStyle(
                    color: isToday ? AppTheme.primary : AppTheme.textMuted,
                    fontSize: 9,
                    fontWeight: isToday ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Small helpers
// ─────────────────────────────────────────────────────────────

class _KpiCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  const _KpiCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppTheme.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(height: 10),
            Text(
              value,
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 4),
            Text(label,
                style: const TextStyle(
                    color: AppTheme.textMuted, fontSize: 11)),
          ],
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) => Text(
        text,
        style: const TextStyle(
          color: AppTheme.textPrimary,
          fontSize: 16,
          fontWeight: FontWeight.w700,
        ),
      );
}
