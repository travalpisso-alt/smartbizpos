// lib/core/di/providers.dart
// Riverpod providers for global singletons (store, supabase, sync service)

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:objectbox/objectbox.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/local/models/objectbox_models.dart';
import '../../services/sync_service.dart';
import '../../objectbox.g.dart';

// ── ObjectBox Store ──────────────────────────────────────────
/// Overridden in main.dart with the already-opened store.
final obxStoreProvider = Provider<Store>((ref) {
  throw UnimplementedError('Override obxStoreProvider before use.');
});

// ── ObjectBox Boxes ──────────────────────────────────────────
final invoiceBoxProvider = Provider<Box<InvoiceEntity>>((ref) {
  return ref.watch(obxStoreProvider).box<InvoiceEntity>();
});

final itemBoxProvider = Provider<Box<ItemEntity>>((ref) {
  return ref.watch(obxStoreProvider).box<ItemEntity>();
});

final customerBoxProvider = Provider<Box<CustomerEntity>>((ref) {
  return ref.watch(obxStoreProvider).box<CustomerEntity>();
});

final lineItemBoxProvider = Provider<Box<LineItemEntity>>((ref) {
  return ref.watch(obxStoreProvider).box<LineItemEntity>();
});

// ── Supabase ─────────────────────────────────────────────────
final supabaseProvider = Provider<SupabaseClient>((ref) {
  return Supabase.instance.client;
});

final authStateProvider = StreamProvider<AuthState>((ref) {
  return ref.watch(supabaseProvider).auth.onAuthStateChange;
});

final currentUserProvider = Provider<User?>((ref) {
  return ref.watch(supabaseProvider).auth.currentUser;
});

// ── SyncService ──────────────────────────────────────────────
final syncServiceProvider = Provider<SyncService>((ref) {
  final store = ref.watch(obxStoreProvider);
  final service = SyncService(store: store);
  service.start();
  ref.onDispose(service.dispose);
  return service;
});

// ── Active tenant ID ─────────────────────────────────────────
/// Loaded from Supabase after login and cached here.
final tenantIdProvider = StateProvider<String?>((ref) => null);

// ── Pricing tier (global POS state) ─────────────────────────
final pricingTierProvider = StateProvider<String>((ref) => 'RETAIL');
