// lib/services/sync_service.dart
// Dependencies: connectivity_plus, http, flutter_secure_storage, objectbox

import 'dart:async';
import 'dart:convert';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:objectbox/objectbox.dart';
import '../data/local/models/objectbox_models.dart';
import '../objectbox.g.dart';

const _workerBaseUrl = 'https://smartbiz.YOUR_SUBDOMAIN.workers.dev';
const _syncEndpoint = '$_workerBaseUrl/api/v1/sync';
const _itemsEndpoint = '$_workerBaseUrl/api/v1/items';
const _maxBatchSize = 50;
const _maxRetries = 5;
const _retryDelays = [5, 15, 60, 300, 900];

enum SyncStatus { idle, syncing, error }

class SyncService {
  final Store _store;
  final FlutterSecureStorage _secureStorage;
  final Connectivity _connectivity;

  late final Box<InvoiceEntity> _invoiceBox;
  late final Box<LineItemEntity> _lineItemBox;
  late final Box<ItemEntity> _itemBox;

  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;
  Timer? _periodicTimer;
  bool _isSyncing = false;

  final ValueNotifier<SyncStatus> syncStatus = ValueNotifier(SyncStatus.idle);
  final ValueNotifier<String?> lastSyncError = ValueNotifier(null);
  final ValueNotifier<DateTime?> lastSyncTime = ValueNotifier(null);

  SyncService({
    required Store store,
    FlutterSecureStorage? secureStorage,
    Connectivity? connectivity,
  })  : _store = store,
        _secureStorage = secureStorage ?? const FlutterSecureStorage(),
        _connectivity = connectivity ?? Connectivity() {
    _invoiceBox = _store.box<InvoiceEntity>();
    _lineItemBox = _store.box<LineItemEntity>();
    _itemBox = _store.box<ItemEntity>();
  }

  void start() {
    _connectivitySub = _connectivity.onConnectivityChanged.listen((results) async {
      final hasNet = results.any((r) =>
          r == ConnectivityResult.mobile ||
          r == ConnectivityResult.wifi ||
          r == ConnectivityResult.ethernet);
      if (hasNet) await triggerSync();
    });
    _periodicTimer = Timer.periodic(const Duration(minutes: 3), (_) => triggerSync());
  }

  void dispose() {
    _connectivitySub?.cancel();
    _periodicTimer?.cancel();
    syncStatus.dispose();
    lastSyncError.dispose();
    lastSyncTime.dispose();
  }

  Future<void> triggerSync() async {
    if (_isSyncing) return;
    _isSyncing = true;
    syncStatus.value = SyncStatus.syncing;
    try {
      await _syncInvoices();
      await _syncItems();
      lastSyncTime.value = DateTime.now();
      lastSyncError.value = null;
      syncStatus.value = SyncStatus.idle;
    } catch (e) {
      lastSyncError.value = e.toString();
      syncStatus.value = SyncStatus.error;
    } finally {
      _isSyncing = false;
    }
  }

  Future<void> _syncInvoices() async {
    final unsynced = _invoiceBox
        .query(InvoiceEntity_.isSynced.equals(false))
        .order(InvoiceEntity_.createdAtLocal)
        .build()
        .find();
    if (unsynced.isEmpty) return;

    final token = await _getAuthToken();
    if (token == null) throw Exception('No auth token stored.');

    for (var i = 0; i < unsynced.length; i += _maxBatchSize) {
      final batch = unsynced.skip(i).take(_maxBatchSize).toList();
      final payload = _buildInvoicePayload(batch);
      final response = await _postWithRetry(_syncEndpoint, payload, token);
      _handleInvoiceSyncResponse(response, batch);
    }
  }

  Map<String, dynamic> _buildInvoicePayload(List<InvoiceEntity> invoices) {
    return {
      'invoices': invoices.map((inv) {
        final lines = _lineItemBox
            .query(LineItemEntity_.invoice.equals(inv.id))
            .build()
            .find();
        return {
          'idempotency_key': inv.ulid,
          'tenant_id': inv.tenantId,
          'customer_id': inv.customerId,
          'total_amount': inv.totalAmount,
          'payment_mode': inv.paymentMode,
          'created_at_local': inv.createdAtLocal.toIso8601String(),
          'line_items': lines.map((li) => {
                'item_id': li.itemId,
                'qty': li.qty,
                'unit_price': li.unitPrice,
                'pricing_tier': li.pricingTier,
              }).toList(),
        };
      }).toList(),
    };
  }

  void _handleInvoiceSyncResponse(
      Map<String, dynamic> response, List<InvoiceEntity> batch) {
    final results = response['results'] as List<dynamic>? ?? [];
    final resultMap = <String, String>{};
    for (final r in results) {
      final m = r as Map<String, dynamic>;
      resultMap[m['idempotency_key'] as String] = m['status'] as String;
    }
    final toUpdate = <InvoiceEntity>[];
    for (final inv in batch) {
      final status = resultMap[inv.ulid];
      if (status == 'created' || status == 'duplicate') {
        inv.isSynced = true;
        toUpdate.add(inv);
      }
    }
    _invoiceBox.putMany(toUpdate);
  }

  Future<void> _syncItems() async {
    final unsynced = _itemBox.query(ItemEntity_.isSynced.equals(false)).build().find();
    if (unsynced.isEmpty) return;
    final token = await _getAuthToken();
    if (token == null) throw Exception('No auth token stored.');
    for (var i = 0; i < unsynced.length; i += _maxBatchSize) {
      final batch = unsynced.skip(i).take(_maxBatchSize).toList();
      final payload = {
        'items': batch.map((item) => {
              'item_id': item.remoteId.length == 36 ? item.remoteId : null,
              'tenant_id': item.tenantId,
              'barcode': item.barcode,
              'name_translations': jsonDecode(item.nameTranslationsJson),
              'prices': jsonDecode(item.pricesJson),
              'qty_in_stock': item.qtyInStock,
            }).toList(),
      };
      await _postWithRetry(_itemsEndpoint, payload, token);
      for (final item in batch) {
        item.isSynced = true;
      }
      _itemBox.putMany(batch);
    }
  }

  Future<Map<String, dynamic>> _postWithRetry(
      String url, Map<String, dynamic> payload, String token,
      {int attempt = 0}) async {
    try {
      final response = await http
          .post(
            Uri.parse(url),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $token',
            },
            body: jsonEncode(payload),
          )
          .timeout(const Duration(seconds: 30));
      if (response.statusCode == 200 || response.statusCode == 207) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      }
      if (response.statusCode == 401) {
        throw Exception('Unauthorized – check WORKER_AUTH_SECRET.');
      }
      throw Exception('HTTP ${response.statusCode}: ${response.body}');
    } catch (e) {
      if (attempt < _maxRetries - 1) {
        await Future.delayed(Duration(seconds: _retryDelays[attempt]));
        return _postWithRetry(url, payload, token, attempt: attempt + 1);
      }
      rethrow;
    }
  }

  Future<String?> _getAuthToken() async =>
      _secureStorage.read(key: 'worker_auth_secret');

  Future<void> storeAuthToken(String token) async =>
      _secureStorage.write(key: 'worker_auth_secret', value: token);
}
