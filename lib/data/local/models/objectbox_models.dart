// lib/data/local/models/objectbox_models.dart
//
// Run after editing:
//   flutter pub run build_runner build --delete-conflicting-outputs
//
// Dependencies (pubspec.yaml):
//   objectbox: ^4.0.0
//   objectbox_flutter_libs: ^4.0.0
//   ulid: ^1.1.0

import 'package:objectbox/objectbox.dart';
import 'package:ulid/ulid.dart';

// ─────────────────────────────────────────────────────────────
// ULID helper
// ─────────────────────────────────────────────────────────────
String generateUlid() => Ulid().toString();

// ─────────────────────────────────────────────────────────────
// InvoiceEntity  (local, not yet synced)
// ─────────────────────────────────────────────────────────────
@Entity()
class InvoiceEntity {
  @Id()
  int id = 0; // ObjectBox internal auto-increment id

  /// ULID – used as idempotency_key when pushing to Cloudflare
  @Unique()
  String ulid;

  String tenantId;
  String? customerId;

  double totalAmount;

  /// "CASH" | "CARD_TAP" | "LANKAQR" | "CREDIT"
  String paymentMode;

  /// ISO-8601 string of device clock at sale time
  @Property(type: PropertyType.date)
  DateTime createdAtLocal;

  /// false = needs to be pushed to Cloudflare Worker
  bool isSynced;

  /// Back-link to line items
  @Backlink('invoice')
  final lineItems = ToMany<LineItemEntity>();

  InvoiceEntity({
    this.id = 0,
    String? ulid,
    required this.tenantId,
    this.customerId,
    required this.totalAmount,
    required this.paymentMode,
    DateTime? createdAtLocal,
    this.isSynced = false,
  })  : ulid = ulid ?? generateUlid(),
        createdAtLocal = createdAtLocal ?? DateTime.now();
}

// ─────────────────────────────────────────────────────────────
// LineItemEntity
// ─────────────────────────────────────────────────────────────
@Entity()
class LineItemEntity {
  @Id()
  int id = 0;

  String itemId;
  double qty;
  double unitPrice;

  /// "RETAIL" | "WHOLESALE"
  String pricingTier;

  final invoice = ToOne<InvoiceEntity>();

  LineItemEntity({
    this.id = 0,
    required this.itemId,
    required this.qty,
    required this.unitPrice,
    required this.pricingTier,
  });
}

// ─────────────────────────────────────────────────────────────
// ItemEntity  (local catalog cache)
// ─────────────────────────────────────────────────────────────
@Entity()
class ItemEntity {
  @Id()
  int id = 0;

  /// UUID from Supabase (or ULID if created offline)
  @Unique()
  String remoteId;

  String tenantId;
  String? barcode;

  /// JSON string: {"en":"Sugar","si":"සීනි"}
  String nameTranslationsJson;

  /// JSON string: {"retail":500,"wholesale":450}
  String pricesJson;

  double qtyInStock;
  bool isActive;
  bool isSynced;

  @Property(type: PropertyType.date)
  DateTime updatedAt;

  ItemEntity({
    this.id = 0,
    String? remoteId,
    required this.tenantId,
    this.barcode,
    required this.nameTranslationsJson,
    required this.pricesJson,
    this.qtyInStock = 0,
    this.isActive = true,
    this.isSynced = false,
    DateTime? updatedAt,
  })  : remoteId = remoteId ?? generateUlid(),
        updatedAt = updatedAt ?? DateTime.now();
}

// ─────────────────────────────────────────────────────────────
// CustomerEntity  (local cache)
// ─────────────────────────────────────────────────────────────
@Entity()
class CustomerEntity {
  @Id()
  int id = 0;

  @Unique()
  String remoteId;

  String tenantId;
  String name;
  String phone;

  /// "RETAIL" | "WHOLESALE"
  String pricingTier;

  double currentDebt;

  CustomerEntity({
    this.id = 0,
    String? remoteId,
    required this.tenantId,
    required this.name,
    required this.phone,
    this.pricingTier = 'RETAIL',
    this.currentDebt = 0.0,
  }) : remoteId = remoteId ?? generateUlid();
}

// ─────────────────────────────────────────────────────────────
// PendingSyncEntity  (generic retry queue)
// ─────────────────────────────────────────────────────────────
@Entity()
class PendingSyncEntity {
  @Id()
  int id = 0;

  /// "invoice" | "item"
  String entityType;

  /// ULID / UUID of the entity to sync
  String entityUlid;

  int retryCount;

  @Property(type: PropertyType.date)
  DateTime createdAt;

  @Property(type: PropertyType.date)
  DateTime? lastAttemptAt;

  String? lastError;

  PendingSyncEntity({
    this.id = 0,
    required this.entityType,
    required this.entityUlid,
    this.retryCount = 0,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();
}
