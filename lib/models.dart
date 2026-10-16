import 'dart:convert';
import 'dart:typed_data';

enum UserRole { receptionist, admin }

enum InventoryPeriod { daily, weekly, monthly }

enum InventoryViewMode { cards, table }

enum ProductPerformancePeriod { today, week, month, year }

enum ProductPerformanceView { highMovers, lowMovers, all }

enum AppThemePreference { system, light, dark }

enum AppNavigationPreference { automatic, bottom, side }

enum AppAccentPreference {
  blue,
  green,
  teal,
  indigo,
  graphite,
  amber,
  classicWhite,
  classicBlack,
  custom,
}

extension InventoryPeriodLabel on InventoryPeriod {
  String get label => switch (this) {
    InventoryPeriod.daily => 'Daily',
    InventoryPeriod.weekly => 'Weekly',
    InventoryPeriod.monthly => 'Monthly',
  };
}

class InventoryPreferences {
  const InventoryPreferences({
    this.notifyEverySale = false,
    this.notifyLowStock = true,
    this.notifyExpiry = true,
    this.notifyDebtDue = true,
    this.expiryReminderDays = 30,
    this.showExternalNotifications = false,
    this.defaultPeriod = InventoryPeriod.daily,
    this.weekStartsOn = DateTime.monday,
    this.inventoryView = InventoryViewMode.cards,
    this.theme = AppThemePreference.light,
    this.navigation = AppNavigationPreference.automatic,
    this.accent = AppAccentPreference.blue,
    this.customAccentArgb = 0xFF0B72E7,
    this.showProductImages = true,
    this.textScale = 1.0,
    this.collectCustomerDetails = false,
    this.staffCanReceiveStock = false,
  });

  final bool notifyEverySale;
  final bool notifyLowStock;
  final bool notifyExpiry;
  final bool notifyDebtDue;
  final int expiryReminderDays;
  final bool showExternalNotifications;
  final InventoryPeriod defaultPeriod;
  final int weekStartsOn;
  final InventoryViewMode inventoryView;
  final AppThemePreference theme;
  final AppNavigationPreference navigation;
  final AppAccentPreference accent;
  final int customAccentArgb;
  final bool showProductImages;
  final double textScale;
  final bool collectCustomerDetails;
  final bool staffCanReceiveStock;

  Map<String, dynamic> toSharedJson() => {
    'notify_every_sale': notifyEverySale,
    'notify_low_stock': notifyLowStock,
    'notify_expiry': notifyExpiry,
    'notify_debt_due': notifyDebtDue,
    'expiry_reminder_days': expiryReminderDays,
    'show_external_notifications': showExternalNotifications,
    'inventory_period': defaultPeriod.name,
    'inventory_week_start': weekStartsOn,
    'inventory_view': inventoryView.name,
    'app_theme': theme == AppThemePreference.dark ? 'dark' : 'light',
    'app_accent': accent.name,
    'app_custom_accent': customAccentArgb,
    'app_show_product_images': showProductImages,
    'app_text_scale': textScale,
    'collect_customer_details': collectCustomerDetails,
    'staff_can_receive_stock': staffCanReceiveStock,
  };

  InventoryPreferences applySharedJson(Map<String, dynamic> values) => copyWith(
    notifyEverySale: values['notify_every_sale'] as bool?,
    notifyLowStock: values['notify_low_stock'] as bool?,
    notifyExpiry: values['notify_expiry'] as bool?,
    notifyDebtDue: values['notify_debt_due'] as bool?,
    expiryReminderDays: values['expiry_reminder_days'] as int?,
    showExternalNotifications: values['show_external_notifications'] as bool?,
    defaultPeriod: InventoryPeriod.values
        .where((v) => v.name == values['inventory_period'])
        .firstOrNull,
    weekStartsOn: values['inventory_week_start'] as int?,
    inventoryView: InventoryViewMode.values
        .where((v) => v.name == values['inventory_view'])
        .firstOrNull,
    theme: values['app_theme'] == null
        ? null
        : values['app_theme'] == 'dark'
        ? AppThemePreference.dark
        : AppThemePreference.light,
    collectCustomerDetails: values['collect_customer_details'] as bool?,
    staffCanReceiveStock: values['staff_can_receive_stock'] as bool?,
    accent: AppAccentPreference.values
        .where((v) => v.name == values['app_accent'])
        .firstOrNull,
    customAccentArgb: values['app_custom_accent'] as int?,
    showProductImages: values['app_show_product_images'] as bool?,
    textScale: (values['app_text_scale'] as num?)?.toDouble(),
  );

  InventoryPreferences copyWith({
    bool? notifyEverySale,
    bool? notifyLowStock,
    bool? notifyExpiry,
    bool? notifyDebtDue,
    int? expiryReminderDays,
    bool? showExternalNotifications,
    InventoryPeriod? defaultPeriod,
    int? weekStartsOn,
    InventoryViewMode? inventoryView,
    AppThemePreference? theme,
    AppNavigationPreference? navigation,
    AppAccentPreference? accent,
    int? customAccentArgb,
    bool? showProductImages,
    double? textScale,
    bool? collectCustomerDetails,
    bool? staffCanReceiveStock,
  }) => InventoryPreferences(
    notifyEverySale: notifyEverySale ?? this.notifyEverySale,
    notifyLowStock: notifyLowStock ?? this.notifyLowStock,
    notifyExpiry: notifyExpiry ?? this.notifyExpiry,
    notifyDebtDue: notifyDebtDue ?? this.notifyDebtDue,
    expiryReminderDays: expiryReminderDays ?? this.expiryReminderDays,
    showExternalNotifications:
        showExternalNotifications ?? this.showExternalNotifications,
    defaultPeriod: defaultPeriod ?? this.defaultPeriod,
    weekStartsOn: weekStartsOn ?? this.weekStartsOn,
    inventoryView: inventoryView ?? this.inventoryView,
    theme: theme ?? this.theme,
    navigation: navigation ?? this.navigation,
    accent: accent ?? this.accent,
    customAccentArgb: customAccentArgb ?? this.customAccentArgb,
    showProductImages: showProductImages ?? this.showProductImages,
    textScale: textScale ?? this.textScale,
    collectCustomerDetails:
        collectCustomerDetails ?? this.collectCustomerDetails,
    staffCanReceiveStock: staffCanReceiveStock ?? this.staffCanReceiveStock,
  );
}

class StockMovement {
  const StockMovement({
    required this.id,
    required this.movementUuid,
    required this.productId,
    required this.type,
    required this.quantityBase,
    required this.createdAt,
    required this.actorName,
    this.note,
    this.referenceId,
  });

  final int id;
  final String movementUuid;
  final int productId;
  final String type;
  final int quantityBase;
  final DateTime createdAt;
  final String actorName;
  final String? note;
  final String? referenceId;

  factory StockMovement.fromMap(Map<String, Object?> map) => StockMovement(
    id: map['id'] as int,
    movementUuid: map['movement_uuid'] as String,
    productId: map['product_id'] as int,
    type: map['type'] as String,
    quantityBase: (map['quantity_base'] as num).toInt(),
    createdAt: DateTime.parse(map['created_at'] as String),
    actorName: map['actor_name'] as String? ?? 'Saleo',
    note: map['note'] as String?,
    referenceId: map['reference_id'] as String?,
  );

  Map<String, Object?> toSyncJson({required String productCode}) => {
    'movement_uuid': movementUuid,
    'product_code': productCode.trim().toUpperCase(),
    'type': type,
    'quantity_base': quantityBase,
    'actor_name': actorName,
    'note': note,
    'reference_id': referenceId,
    'created_at': createdAt.toUtc().toIso8601String(),
  };
}

class AppNotificationRecord {
  const AppNotificationRecord({
    required this.id,
    required this.type,
    required this.title,
    required this.message,
    required this.createdAt,
    required this.isRead,
    this.productId,
    this.saleId,
    this.resolvedAt,
  });

  final int id;
  final String type;
  final String title;
  final String message;
  final DateTime createdAt;
  final bool isRead;
  final int? productId;
  final int? saleId;
  final DateTime? resolvedAt;
  bool get isResolved => resolvedAt != null;

  factory AppNotificationRecord.fromMap(Map<String, Object?> map) =>
      AppNotificationRecord(
        id: map['id'] as int,
        type: map['type'] as String,
        title: map['title'] as String,
        message: map['message'] as String,
        createdAt: DateTime.parse(map['created_at'] as String),
        isRead: (map['is_read'] as int) == 1,
        productId: (map['product_id'] as num?)?.toInt(),
        saleId: (map['sale_id'] as num?)?.toInt(),
        resolvedAt: map['resolved_at'] == null
            ? null
            : DateTime.parse(map['resolved_at'] as String),
      );

  Map<String, Object?> toMap() => {
    'id': id,
    'type': type,
    'title': title,
    'message': message,
    'product_id': productId,
    'sale_id': saleId,
    'created_at': createdAt.toUtc().toIso8601String(),
    'is_read': isRead ? 1 : 0,
    'resolved_at': resolvedAt?.toUtc().toIso8601String(),
  };
}

class AppUser {
  const AppUser({
    required this.id,
    required this.username,
    required this.displayName,
    required this.role,
    required this.active,
    this.archivedAt,
    this.jobTitle = 'Receptionist',
  });

  final int id;
  final String username;
  final String displayName;
  final UserRole role;
  final bool active;
  final DateTime? archivedAt;
  final String jobTitle;
  bool get isArchived => archivedAt != null;

  factory AppUser.fromMap(Map<String, Object?> map) => AppUser(
    id: map['id'] as int,
    username: map['username'] as String,
    displayName: map['display_name'] as String,
    role: (map['role'] as String) == 'admin'
        ? UserRole.admin
        : UserRole.receptionist,
    active: (map['active'] as int) == 1,
    archivedAt: map['archived_at'] == null
        ? null
        : DateTime.parse(map['archived_at'] as String),
    jobTitle: map['job_title'] as String? ?? 'Receptionist',
  );
}

class SellingForm {
  const SellingForm({
    required this.id,
    required this.productId,
    required this.name,
    required this.priceCents,
    required this.active,
    this.unitsPerForm = 1,
  });

  final int id;
  final int productId;
  final String name;
  final int priceCents;
  final bool active;
  final int unitsPerForm;

  factory SellingForm.fromMap(Map<String, Object?> map) => SellingForm(
    id: map['id'] as int,
    productId: map['product_id'] as int,
    name: map['name'] as String,
    priceCents: map['price_cents'] as int,
    active: (map['active'] as int) == 1,
    unitsPerForm: (map['units_per_form'] as num?)?.toInt() ?? 1,
  );

  Map<String, Object?> toSyncJson() => {
    'name': name,
    'price_cents': priceCents,
    'active': active,
    'units_per_form': unitsPerForm,
  };
}

class Product {
  const Product({
    required this.id,
    required this.name,
    required this.code,
    required this.category,
    required this.active,
    required this.forms,
    this.baseUnit = 'unit',
    this.currentStock = 0,
    this.lowStockThreshold = 0,
    this.imageBytes,
  });

  final int id;
  final String name;
  final String code;
  final String category;
  final bool active;
  final List<SellingForm> forms;
  final String baseUnit;
  final int currentStock;
  final int lowStockThreshold;
  final Uint8List? imageBytes;

  bool get isLowStock =>
      lowStockThreshold > 0 && currentStock <= lowStockThreshold;

  Map<String, Object?> toSyncJson() => {
    'name': name,
    'code': code,
    'category': category,
    'active': active,
    'base_unit': baseUnit,
    'current_stock': currentStock,
    'low_stock_threshold': lowStockThreshold,
    'image_base64': imageBytes == null ? null : base64Encode(imageBytes!),
    'forms': forms.map((form) => form.toSyncJson()).toList(),
  };
}

class StockShortage {
  const StockShortage({
    required this.product,
    required this.availableBase,
    required this.requiredBase,
  });

  final Product product;
  final int availableBase;
  final int requiredBase;
}

class ReceiptTemplate {
  const ReceiptTemplate({
    required this.shopName,
    this.location = '',
    this.phoneNumber = '',
    this.showCustomerName = true,
    this.showReceiptId = true,
    this.footerMessage = 'Thank you for your business.',
    this.operatorLabel = 'Operator',
    this.useStaffRole = false,
    this.showCustomerPhone = false,
  });

  final String shopName;
  final String location;
  final String phoneNumber;
  final bool showCustomerName;
  final bool showReceiptId;
  final String footerMessage;
  final String operatorLabel;
  final bool useStaffRole;
  final bool showCustomerPhone;

  factory ReceiptTemplate.defaults(String companyName) => ReceiptTemplate(
    shopName: companyName.trim().isEmpty ? 'Saleo Shop' : companyName.trim(),
  );

  factory ReceiptTemplate.fromJson(
    Map<String, dynamic>? json, {
    required String companyName,
  }) {
    if (json == null) return ReceiptTemplate.defaults(companyName);
    return ReceiptTemplate(
      shopName: (json['shop_name']?.toString().trim().isNotEmpty ?? false)
          ? json['shop_name'].toString().trim()
          : companyName,
      location: json['location']?.toString().trim() ?? '',
      phoneNumber: json['phone_number']?.toString().trim() ?? '',
      showCustomerName: json['show_customer_name'] != false,
      showReceiptId: json['show_receipt_id'] != false,
      operatorLabel:
          json['operator_label']?.toString().trim().isNotEmpty == true
          ? json['operator_label'].toString().trim()
          : 'Operator',
      useStaffRole: json['use_staff_role'] == true,
      showCustomerPhone: json['show_customer_phone'] == true,
      footerMessage:
          (json['footer_message']?.toString().trim().isNotEmpty ?? false)
          ? json['footer_message'].toString().trim()
          : 'Thank you for your business.',
    );
  }

  Map<String, dynamic> toJson() => {
    'shop_name': shopName.trim(),
    'location': location.trim(),
    'phone_number': phoneNumber.trim(),
    'show_customer_name': showCustomerName,
    'show_receipt_id': showReceiptId,
    'operator_label': operatorLabel.trim().isEmpty
        ? 'Operator'
        : operatorLabel.trim(),
    'use_staff_role': useStaffRole,
    'show_customer_phone': showCustomerPhone,
    'footer_message': footerMessage.trim(),
  };
}

enum ReceiptTemplateKind { defaultTemplate, custom }

extension ReceiptTemplateKindLabel on ReceiptTemplateKind {
  String get label => switch (this) {
    ReceiptTemplateKind.defaultTemplate => 'Default',
    ReceiptTemplateKind.custom => 'Custom',
  };

  String get apiValue => switch (this) {
    ReceiptTemplateKind.defaultTemplate => 'default',
    ReceiptTemplateKind.custom => 'custom',
  };
}

class ReceiptTemplateSettings {
  const ReceiptTemplateSettings({
    required this.defaultTemplate,
    required this.customTemplate,
    required this.active,
  });

  final ReceiptTemplate defaultTemplate;
  final ReceiptTemplate? customTemplate;
  final ReceiptTemplateKind active;

  ReceiptTemplate get activeTemplate =>
      active == ReceiptTemplateKind.custom && customTemplate != null
      ? customTemplate!
      : defaultTemplate;

  factory ReceiptTemplateSettings.forCompany(String companyName) =>
      ReceiptTemplateSettings(
        defaultTemplate: ReceiptTemplate.defaults(companyName),
        customTemplate: null,
        active: ReceiptTemplateKind.defaultTemplate,
      );

  factory ReceiptTemplateSettings.fromJson(
    Map<String, dynamic>? json, {
    required String companyName,
    Map<String, dynamic>? legacyActiveTemplate,
  }) {
    final fallback = ReceiptTemplate.defaults(companyName);
    if (json == null) {
      if (legacyActiveTemplate == null) {
        return ReceiptTemplateSettings.forCompany(companyName);
      }
      final legacy = ReceiptTemplate.fromJson(
        legacyActiveTemplate,
        companyName: companyName,
      );
      final isDefault = _sameReceiptTemplate(legacy, fallback);
      return ReceiptTemplateSettings(
        defaultTemplate: fallback,
        customTemplate: isDefault ? null : legacy,
        active: isDefault
            ? ReceiptTemplateKind.defaultTemplate
            : ReceiptTemplateKind.custom,
      );
    }
    final customJson = (json['custom_template'] as Map?)
        ?.cast<String, dynamic>();
    final custom = customJson == null
        ? null
        : ReceiptTemplate.fromJson(customJson, companyName: companyName);
    final requestedActive = json['active'] == 'custom'
        ? ReceiptTemplateKind.custom
        : ReceiptTemplateKind.defaultTemplate;
    return ReceiptTemplateSettings(
      defaultTemplate: ReceiptTemplate.fromJson(
        (json['default_template'] as Map?)?.cast<String, dynamic>(),
        companyName: companyName,
      ),
      customTemplate: custom,
      active: requestedActive == ReceiptTemplateKind.custom && custom == null
          ? ReceiptTemplateKind.defaultTemplate
          : requestedActive,
    );
  }

  ReceiptTemplateSettings withCustom(ReceiptTemplate template) =>
      ReceiptTemplateSettings(
        defaultTemplate: defaultTemplate,
        customTemplate: template,
        active: ReceiptTemplateKind.custom,
      );

  ReceiptTemplateSettings withActive(ReceiptTemplateKind value) =>
      ReceiptTemplateSettings(
        defaultTemplate: defaultTemplate,
        customTemplate: customTemplate,
        active: value == ReceiptTemplateKind.custom && customTemplate == null
            ? ReceiptTemplateKind.defaultTemplate
            : value,
      );

  Map<String, dynamic> toJson() => {
    'default_template': defaultTemplate.toJson(),
    'custom_template': customTemplate?.toJson(),
    'active': active.apiValue,
  };
}

bool _sameReceiptTemplate(ReceiptTemplate left, ReceiptTemplate right) =>
    left.shopName == right.shopName &&
    left.location == right.location &&
    left.phoneNumber == right.phoneNumber &&
    left.showCustomerName == right.showCustomerName &&
    left.showReceiptId == right.showReceiptId &&
    left.operatorLabel == right.operatorLabel &&
    left.useStaffRole == right.useStaffRole &&
    left.showCustomerPhone == right.showCustomerPhone &&
    left.footerMessage == right.footerMessage;

class CartLine {
  const CartLine({
    required this.product,
    required this.form,
    required this.quantity,
  });

  final Product product;
  final SellingForm form;
  final int quantity;
  int get lineTotalCents => form.priceCents * quantity;

  CartLine copyWith({int? quantity}) => CartLine(
    product: product,
    form: form,
    quantity: quantity ?? this.quantity,
  );
}

class SaleItem {
  const SaleItem({
    required this.productId,
    required this.productName,
    required this.formName,
    required this.unitPriceCents,
    required this.quantity,
    required this.lineTotalCents,
    this.productCode = '',
    this.unitsPerForm = 1,
  });

  final int productId;
  final String productName;
  final String formName;
  final int unitPriceCents;
  final int quantity;
  final int lineTotalCents;
  final String productCode;
  final int unitsPerForm;

  Map<String, Object?> toJson() => {
    'product_id': productId,
    'product_name': productName,
    'selling_form': formName,
    'unit_price_cents': unitPriceCents,
    'quantity': quantity,
    'line_total_cents': lineTotalCents,
    'product_code': productCode,
    'units_per_form': unitsPerForm,
  };
}

class Sale {
  const Sale({
    required this.id,
    required this.transactionUuid,
    required this.receiptNumber,
    required this.receptionistId,
    required this.receptionistUsername,
    required this.receptionistName,
    this.customerName,
    this.customerPhone,
    this.customerCompany,
    this.collectedBy,
    this.collectorPhone,
    this.previousDebtCents = 0,
    this.operatorLabel = 'Operator',
    required this.deviceId,
    required this.createdAt,
    required this.totalCents,
    required this.paymentMethod,
    required this.cashCents,
    required this.mobileMoneyCents,
    this.cashTenderedCents = 0,
    this.changeGivenCents = 0,
    this.debtCents = 0,
    this.debtPaidCents = 0,
    this.debtDueAt,
    this.debtNote,
    required this.syncStatus,
    required this.voided,
    this.voidReason,
    this.items = const [],
    this.stockOverride = false,
  });

  final int id;
  final String transactionUuid;
  final String receiptNumber;
  final int receptionistId;
  final String receptionistUsername;
  final String receptionistName;
  final String? customerName;
  final String? customerPhone;
  final String? customerCompany;
  final String? collectedBy;
  final String? collectorPhone;
  final int previousDebtCents;
  final String operatorLabel;
  final String deviceId;
  final DateTime createdAt;
  final int totalCents;
  final String paymentMethod;
  final int cashCents;
  final int mobileMoneyCents;
  final int cashTenderedCents;
  final int changeGivenCents;
  final int debtCents;
  final int debtPaidCents;
  final DateTime? debtDueAt;
  final String? debtNote;
  final String syncStatus;
  final bool voided;
  final String? voidReason;
  final List<SaleItem> items;
  final bool stockOverride;

  bool get isSynced => syncStatus == 'synced';
  int get outstandingDebtCents {
    final value = debtCents - debtPaidCents;
    return value < 0 ? 0 : value;
  }

  bool get hasDebt => outstandingDebtCents > 0;

  Map<String, Object?> toSyncJson() => {
    'transaction_uuid': transactionUuid,
    'receipt_number': receiptNumber,
    'receptionist_id': receptionistId,
    'receptionist_username': receptionistUsername,
    'receptionist_name': receptionistName,
    'customer_name': customerName,
    'customer_phone': customerPhone,
    'customer_company': customerCompany,
    'collected_by': collectedBy,
    'collector_phone': collectorPhone,
    'previous_debt_cents': previousDebtCents,
    'operator_label': operatorLabel,
    'device_id': deviceId,
    'created_at': createdAt.toUtc().toIso8601String(),
    'total_cents': totalCents,
    'payment_method': paymentMethod,
    'cash_cents': cashCents,
    'mobile_money_cents': mobileMoneyCents,
    'cash_tendered_cents': cashTenderedCents,
    'change_given_cents': changeGivenCents,
    'debt_cents': debtCents,
    'debt_paid_cents': debtPaidCents,
    'debt_due_at': debtDueAt?.toUtc().toIso8601String(),
    'debt_note': debtNote,
    'voided': voided,
    'void_reason': voidReason,
    'stock_override': stockOverride,
    'items': items.map((item) => item.toJson()).toList(),
  };
}

class DebtorSummary {
  const DebtorSummary({
    required this.customerName,
    required this.customerPhone,
    required this.totalDebtCents,
    required this.paidCents,
    required this.outstandingCents,
    required this.saleCount,
    this.companyName = '',
    this.latestSaleAt,
    this.nextDueAt,
  });

  final String customerName;
  final String customerPhone;
  final String companyName;
  final int totalDebtCents;
  final int paidCents;
  final int outstandingCents;
  final int saleCount;
  final DateTime? latestSaleAt;
  final DateTime? nextDueAt;

  bool get isOverdue =>
      outstandingCents > 0 &&
      nextDueAt != null &&
      nextDueAt!.isBefore(DateTime.now());
}

class CreditPaymentRecord {
  const CreditPaymentRecord({
    required this.id,
    required this.companyName,
    required this.customerName,
    required this.amountCents,
    required this.cashCents,
    required this.mobileMoneyCents,
    required this.recordedBy,
    required this.createdAt,
    required this.method,
    this.note,
  });
  final String id;
  final String companyName;
  final String customerName;
  final int amountCents;
  final int cashCents;
  final int mobileMoneyCents;
  final String recordedBy;
  final DateTime createdAt;
  final String method;
  final String? note;
  factory CreditPaymentRecord.fromMap(Map<String, Object?> row) =>
      CreditPaymentRecord(
        id: row['payment_uuid'] as String,
        companyName: row['customer_company'] as String? ?? '',
        customerName: row['customer_name'] as String? ?? '',
        amountCents: (row['amount_cents'] as num).toInt(),
        cashCents: (row['cash_cents'] as num?)?.toInt() ?? 0,
        mobileMoneyCents: (row['mobile_money_cents'] as num?)?.toInt() ?? 0,
        recordedBy: row['received_by'] as String? ?? '',
        createdAt: DateTime.parse(row['created_at'] as String),
        method: row['payment_method'] as String? ?? '',
        note: row['note'] as String?,
      );
}

class DebtLedgerEntry {
  const DebtLedgerEntry({
    required this.id,
    required this.entryType,
    required this.customerName,
    required this.customerPhone,
    required this.companyName,
    required this.amountCents,
    required this.balanceAfterCents,
    required this.createdAt,
    this.balanceBeforeCents = 0,
    this.purchaseTotalCents,
    this.paidAtPurchaseCents = 0,
    this.recordedBy,
    this.payerName,
    this.payerPhone,
    this.saleId,
    this.receiptNumber,
    this.paymentMethod,
    this.collectedBy,
    this.collectorPhone,
    this.note,
    this.items = const [],
  });

  final String id;
  final String entryType;
  final String customerName;
  final String customerPhone;
  final String companyName;
  final int amountCents;
  final int balanceAfterCents;
  final DateTime createdAt;
  final int? saleId;
  final String? receiptNumber;
  final String? paymentMethod;
  final String? collectedBy;
  final String? collectorPhone;
  final String? note;
  final List<SaleItem> items;

  final int balanceBeforeCents;
  final int? purchaseTotalCents;
  final int paidAtPurchaseCents;
  final String? recordedBy;
  final String? payerName;
  final String? payerPhone;

  bool get isPayment => entryType == 'payment';
}

class CustomerRecord {
  const CustomerRecord({
    required this.id,
    required this.name,
    required this.phone,
    this.companyName = '',
    this.address = '',
    required this.createdAt,
    required this.updatedAt,
    this.lastPurchaseAt,
    this.purchaseCount = 0,
    this.totalSpentCents = 0,
  });

  final int id;
  final String name;
  final String phone;
  final String companyName;
  final String address;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? lastPurchaseAt;
  final int purchaseCount;
  final int totalSpentCents;

  factory CustomerRecord.fromMap(Map<String, Object?> map) => CustomerRecord(
    id: map['id'] as int,
    name: map['name'] as String? ?? '',
    phone: map['phone'] as String? ?? '',
    companyName: map['company_name'] as String? ?? '',
    address: map['address'] as String? ?? '',
    createdAt: DateTime.parse(map['created_at'] as String),
    updatedAt: DateTime.parse(map['updated_at'] as String),
    lastPurchaseAt: map['last_purchase_at'] == null
        ? null
        : DateTime.parse(map['last_purchase_at'] as String),
    purchaseCount: (map['purchase_count'] as num?)?.toInt() ?? 0,
    totalSpentCents: (map['total_spent_cents'] as num?)?.toInt() ?? 0,
  );

  Map<String, Object?> toSyncJson() => {
    'name': name,
    'phone': phone,
    'company_name': companyName,
    'address': address,
    'created_at': createdAt.toUtc().toIso8601String(),
    'updated_at': updatedAt.toUtc().toIso8601String(),
    'last_purchase_at': lastPurchaseAt?.toUtc().toIso8601String(),
    'purchase_count': purchaseCount,
    'total_spent_cents': totalSpentCents,
  };
}

class StockDiscrepancy {
  const StockDiscrepancy({
    required this.id,
    required this.productId,
    required this.quantityBase,
    required this.createdAt,
    required this.createdBy,
    this.saleId,
    this.resolvedAt,
    this.resolvedBy,
    this.resolutionReason,
  });

  final int id;
  final int productId;
  final int quantityBase;
  final int? saleId;
  final DateTime createdAt;
  final String createdBy;
  final DateTime? resolvedAt;
  final String? resolvedBy;
  final String? resolutionReason;
  bool get isResolved => resolvedAt != null;

  factory StockDiscrepancy.fromMap(Map<String, Object?> map) =>
      StockDiscrepancy(
        id: map['id'] as int,
        productId: map['product_id'] as int,
        quantityBase: (map['quantity_base'] as num).toInt(),
        saleId: (map['sale_id'] as num?)?.toInt(),
        createdAt: DateTime.parse(map['created_at'] as String),
        createdBy: map['created_by'] as String? ?? 'Saleo',
        resolvedAt: map['resolved_at'] == null
            ? null
            : DateTime.parse(map['resolved_at'] as String),
        resolvedBy: map['resolved_by'] as String?,
        resolutionReason: map['resolution_reason'] as String?,
      );
}

enum StockReceiptStatus { draft, confirmed, reversed }

class StockReceiptItem {
  const StockReceiptItem({
    required this.id,
    required this.receiptId,
    required this.productId,
    required this.productName,
    required this.formName,
    required this.quantityForms,
    required this.unitsPerForm,
    required this.quantityBase,
    this.purchaseCostCents,
    this.batchNumber,
    this.expiryDate,
  });

  final int id;
  final int receiptId;
  final int productId;
  final String productName;
  final String formName;
  final int quantityForms;
  final int unitsPerForm;
  final int quantityBase;
  final int? purchaseCostCents;
  final String? batchNumber;
  final DateTime? expiryDate;

  factory StockReceiptItem.fromMap(Map<String, Object?> map) =>
      StockReceiptItem(
        id: map['id'] as int,
        receiptId: map['receipt_id'] as int,
        productId: map['product_id'] as int,
        productName: map['product_name'] as String,
        formName: map['form_name'] as String,
        quantityForms: (map['quantity_forms'] as num).toInt(),
        unitsPerForm: (map['units_per_form'] as num).toInt(),
        quantityBase: (map['quantity_base'] as num).toInt(),
        purchaseCostCents: (map['purchase_cost_cents'] as num?)?.toInt(),
        batchNumber: map['batch_number'] as String?,
        expiryDate: map['expiry_date'] == null
            ? null
            : DateTime.parse(map['expiry_date'] as String),
      );

  Map<String, Object?> toSyncJson() => {
    'product_id': productId,
    'product_name': productName,
    'form_name': formName,
    'quantity_forms': quantityForms,
    'units_per_form': unitsPerForm,
    'quantity_base': quantityBase,
    'purchase_cost_cents': purchaseCostCents,
    'batch_number': batchNumber,
    'expiry_date': expiryDate?.toIso8601String(),
  };
}

class StockReceipt {
  const StockReceipt({
    required this.id,
    required this.receiptUuid,
    required this.status,
    required this.createdAt,
    required this.createdBy,
    required this.items,
    this.supplierName,
    this.invoiceNumber,
    this.confirmedAt,
    this.reversedAt,
    this.reversalReason,
  });

  final int id;
  final String receiptUuid;
  final StockReceiptStatus status;
  final String? supplierName;
  final String? invoiceNumber;
  final DateTime createdAt;
  final DateTime? confirmedAt;
  final String createdBy;
  final DateTime? reversedAt;
  final String? reversalReason;
  final List<StockReceiptItem> items;

  int get totalUnits => items.fold(0, (sum, item) => sum + item.quantityBase);
  int get totalCostCents => items.fold(
    0,
    (sum, item) => sum + (item.purchaseCostCents ?? 0) * item.quantityForms,
  );

  Map<String, Object?> toSyncJson() => {
    'receipt_uuid': receiptUuid,
    'status': status.name,
    'supplier_name': supplierName,
    'invoice_number': invoiceNumber,
    'created_at': createdAt.toUtc().toIso8601String(),
    'confirmed_at': confirmedAt?.toUtc().toIso8601String(),
    'created_by': createdBy,
    'reversed_at': reversedAt?.toUtc().toIso8601String(),
    'reversal_reason': reversalReason,
    'items': items.map((item) => item.toSyncJson()).toList(),
  };
}

class StockReceiptDraftItem {
  const StockReceiptDraftItem({
    required this.product,
    required this.form,
    required this.quantityForms,
    this.purchaseCostCents,
    this.batchNumber,
    this.expiryDate,
  });

  final Product product;
  final SellingForm form;
  final int quantityForms;
  final int? purchaseCostCents;
  final String? batchNumber;
  final DateTime? expiryDate;
  int get quantityBase => quantityForms * form.unitsPerForm;
}

class DashboardSummary {
  const DashboardSummary({
    required this.todayCents,
    required this.todayTransactions,
    required this.pendingSync,
    required this.activeReceptionists,
  });

  final int todayCents;
  final int todayTransactions;
  final int pendingSync;
  final int activeReceptionists;
}
