import 'dart:convert';

import 'package:http/http.dart' as http;

import 'models.dart';
import 'live_sales_service.dart';
import 'desktop_security.dart';

enum SyncResultType { success, notConfigured, failed }

/// Fields that the server will reject for a customer contact.
List<String> customerSyncIssues(Map<String, Object?> row) {
  final issues = <String>[];
  final name = (row['name']?.toString() ?? '').trim();
  final phone = (row['phone']?.toString() ?? '').trim();
  if (name.isEmpty || name.length > 160) issues.add('name');
  if (phone.length < 3 || phone.length > 40) issues.add('phone');
  if ((row['company_name']?.toString() ?? '').length > 160) {
    issues.add('company name');
  }
  if ((row['address']?.toString() ?? '').length > 300) issues.add('address');
  if ((row['purchase_count'] as num?)?.isNegative == true) {
    issues.add('purchase count');
  }
  if ((row['total_spent_cents'] as num?)?.isNegative == true) {
    issues.add('total spent');
  }
  return issues;
}

class SyncResult {
  const SyncResult(this.type, {this.acceptedIds = const [], this.message});

  final SyncResultType type;
  final List<String> acceptedIds;
  final String? message;
}

class SyncService {
  SyncService() {
    validateServerConfiguration(
      const String.fromEnvironment(
        'API_BASE_URL',
        defaultValue: 'https://api.naprojekts.xyz',
      ),
      baseUrl,
    );
  }

  static const baseUrl = String.fromEnvironment(
    'SYNC_API_URL',
    defaultValue: 'https://api.naprojekts.xyz',
  );
  String? _sessionToken;
  String? lastSalesDownloadError;
  String? lastCustomerUploadError;
  final Set<String> rejectedCustomerPhones = <String>{};
  String? workflowError;
  final _sentCatalog = <String, Map<String, String>>{};
  String _fingerprint(String kind, Map<String, Object?> row) {
    final value = Map<String, Object?>.from(row);
    // Stock is posted through its ledger, not by editing product metadata.
    if (kind == 'products') value.remove('current_stock');
    return jsonEncode(value);
  }

  Map<String, dynamic> get catalogSnapshot => {
    for (final entry in _sentCatalog.entries)
      entry.key: Map<String, String>.from(entry.value),
  };
  void restoreCatalogSnapshot(Map<String, dynamic> value) {
    _sentCatalog.clear();
    for (final entry in value.entries) {
      _sentCatalog[entry.key] = (entry.value as Map).cast<String, String>();
    }
  }

  Set<String> pendingProductCodes(List<Product> rows) => _changed(
    'products',
    rows.map((v) => v.toSyncJson()).toList(),
    'code',
  ).map((v) => v['code'].toString()).toSet();
  Set<String> pendingCustomerPhones(List<CustomerRecord> rows) => _changed(
    'customers',
    rows.map((v) => v.toSyncJson()).toList(),
    'phone',
  ).map((v) => v['phone'].toString()).toSet();
  void rememberDownloadedProducts(List<Product> rows) => _acknowledge(
    'products',
    rows.map((v) => v.toSyncJson()).toList(),
    'code',
    _sessionToken,
  );
  void rememberDownloadedCustomers(List<CustomerRecord> rows) => _acknowledge(
    'customers',
    rows.map((v) => v.toSyncJson()).toList(),
    'phone',
    _sessionToken,
  );

  void rememberDownloadedMovements(
    List<StockMovement> rows,
    List<Product> products,
    List<Map<String, dynamic>> downloaded,
  ) {
    final ids = downloaded.map((v) => v['movement_uuid'].toString()).toSet();
    final byId = {for (final p in products) p.id: p};
    _acknowledge(
      'movements',
      rows
          .where(
            (v) =>
                ids.contains(v.movementUuid) && byId.containsKey(v.productId),
          )
          .map((v) => v.toSyncJson(productCode: byId[v.productId]!.code))
          .toList(),
      'movement_uuid',
      _sessionToken,
    );
  }

  int pendingCatalogCount(
    List<Product> products,
    List<CustomerRecord> customers,
    List<StockReceipt> receipts,
    List<StockMovement> movements, {
    required bool admin,
  }) {
    final productsById = {for (final p in products) p.id: p};
    return (admin ? pendingProductCodes(products).length : 0) +
        pendingCustomerPhones(customers).length +
        _changed(
          'receipts',
          receipts.map((v) => v.toSyncJson()).toList(),
          'receipt_uuid',
        ).length +
        _changed(
          'movements',
          movements
              .where(
                (v) =>
                    v.type != 'sync_snapshot' &&
                    productsById.containsKey(v.productId),
              )
              .map(
                (v) =>
                    v.toSyncJson(productCode: productsById[v.productId]!.code),
              )
              .toList(),
          'movement_uuid',
        ).length;
  }

  List<Map<String, Object?>> _changed(
    String kind,
    List<Map<String, Object?>> rows,
    String key,
  ) => rows
      .where(
        (row) =>
            _sentCatalog[kind]?[row[key].toString()] != _fingerprint(kind, row),
      )
      .toList();
  void _acknowledge(
    String kind,
    List<Map<String, Object?>> rows,
    String key,
    String? token,
  ) {
    if (token != _sessionToken) return;
    final sent = _sentCatalog.putIfAbsent(kind, () => {});
    for (final row in rows) {
      sent[row[key].toString()] = _fingerprint(kind, row);
    }
  }

  Future<Map<String, dynamic>?> workflowRequest(
    String route, {
    Map<String, dynamic>? body,
    bool put = false,
  }) async {
    if (!isConfigured) {
      workflowError = 'Sign in and connect to the server. Approval is never applied offline.';
      return null;
    }
    final token = _sessionToken;
    try {
      final uri = Uri.parse(
        '${baseUrl.replaceAll(RegExp(r'/$'), '')}/api/v1/workflows$route',
      );
      final headers = {..._headers, 'content-type': 'application/json'};
      final response =
          await (body == null
                  ? http.get(uri, headers: headers)
                  : put
                  ? http.put(uri, headers: headers, body: jsonEncode(body))
                  : http.post(uri, headers: headers, body: jsonEncode(body)))
              .timeout(const Duration(seconds: 15));
      if (token != _sessionToken) return null;
      if (response.statusCode < 200 || response.statusCode >= 300) {
        workflowError = response.statusCode == 404 || response.statusCode == 503
            ? 'Approval backend is not deployed or migrated yet. No inventory was added.'
            : 'Approval request failed: ${response.body}';
        return null;
      }
      workflowError = null;
      return (jsonDecode(response.body) as Map).cast<String, dynamic>();
    } catch (_) {
      workflowError = 'Could not reach the approval server. Your submission remains queued.';
      return null;
    }
  }

  final _liveSales = LiveSalesService();
  Future<void> _salesUploadQueue = Future<void>.value();
  bool get liveSalesConnected => _liveSales.connected;

  void stopLiveSales() => _liveSales.stop();
  void startLiveSales({
    required Future<void> Function(List<Map<String, dynamic>>, bool replay)
    onSales,
    required void Function(String) onError,
  }) {
    if (!isConfigured) return;
    _liveSales.start(
      baseUrl: baseUrl,
      headers: _headers,
      onSales: onSales,
      onError: onError,
    );
  }

  bool get isConfigured =>
      baseUrl.trim().isNotEmpty && (_sessionToken?.isNotEmpty ?? false);

  void useSession(String? token) {
    stopLiveSales();
    if (token != _sessionToken) _sentCatalog.clear();
    _sessionToken = token;
  }

  Map<String, String> get _headers => {
    'accept': 'application/json',
    'authorization': 'Bearer $_sessionToken',
  };

  Future<SyncResult> pushSales(List<Sale> sales) async {
    // Serialize immediate uploads and full sync so the same transaction cannot
    // race another insert. Retain the originating session while queued.
    final token = _sessionToken;
    final result = _salesUploadQueue.then<SyncResult>((_) async {
      if (token != _sessionToken) {
        return const SyncResult(
          SyncResultType.failed,
          message: 'Session changed. Sales remain safely queued.',
        );
      }
      return _pushSales(sales);
    });
    _salesUploadQueue = result.then<void>(
      (_) {},
      onError: (Object error, StackTrace stackTrace) {},
    );
    return result;
  }

  Future<SyncResult> _pushSales(List<Sale> sales) async {
    if (!isConfigured) {
      return const SyncResult(
        SyncResultType.notConfigured,
        message:
            'Online sync will activate after the hosting API is connected.',
      );
    }
    if (sales.isEmpty) {
      return const SyncResult(SyncResultType.success);
    }

    try {
      final uri = Uri.parse(
        '${baseUrl.replaceAll(RegExp(r'/$'), '')}/api/v1/sales/batch',
      );
      final response = await http
          .post(
            uri,
            headers: {..._headers, 'content-type': 'application/json'},
            body: jsonEncode({
              'sales': sales.map((sale) => sale.toSyncJson()).toList(),
            }),
          )
          .timeout(const Duration(seconds: 15));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return SyncResult(
          SyncResultType.failed,
          message:
              'Server returned ${response.statusCode}. Sales remain safely queued.',
        );
      }
      final payload = jsonDecode(response.body) as Map<String, Object?>;
      final accepted =
          (payload['accepted_transaction_ids'] as List<dynamic>? ?? const [])
              .map((value) => value.toString())
              .toList();
      return SyncResult(SyncResultType.success, acceptedIds: accepted);
    } catch (_) {
      return const SyncResult(
        SyncResultType.failed,
        message: 'Could not reach the server. Sales remain safely queued.',
      );
    }
  }

  Future<List<Map<String, dynamic>>?> pullSales() async {
    lastSalesDownloadError = null;
    if (!isConfigured) {
      lastSalesDownloadError =
          'Sales download needs a signed-in company session.';
      return null;
    }
    try {
      final uri = Uri.parse(
        '${baseUrl.replaceAll(RegExp(r'/$'), '')}/api/v1/sales',
      );
      final response = await http
          .get(uri, headers: _headers)
          .timeout(const Duration(seconds: 15));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        lastSalesDownloadError = switch (response.statusCode) {
          401 => 'Sales download: your session expired. Sign in again.',
          403 =>
            'Sales download: administrator access was refused by the server.',
          _ =>
            'Sales download failed (HTTP ${response.statusCode}). Retry or check the backend.',
        };
        return null;
      }
      final payload = jsonDecode(response.body) as Map<String, dynamic>;
      final sales = payload['sales'];
      if (sales is! List) {
        lastSalesDownloadError =
            'Sales download: the server returned an unexpected response.';
        return null;
      }
      return sales.map((row) => (row as Map).cast<String, dynamic>()).toList();
    } catch (_) {
      lastSalesDownloadError = 'Sales download failed: connection, timeout or unreadable server response. Retry sync.';
      return null;
    }
  }

  Future<SyncResult> pushDebtPayments(
    List<Map<String, Object?>> payments,
  ) async {
    if (!isConfigured) {
      return const SyncResult(SyncResultType.notConfigured);
    }
    if (payments.isEmpty) return const SyncResult(SyncResultType.success);
    try {
      final uri = Uri.parse(
        '${baseUrl.replaceAll(RegExp(r'/$'), '')}/api/v1/debt-payments/batch',
      );
      final response = await http
          .post(
            uri,
            headers: {..._headers, 'content-type': 'application/json'},
            body: jsonEncode({'payments': payments}),
          )
          .timeout(const Duration(seconds: 15));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return const SyncResult(
          SyncResultType.failed,
          message: 'Debt payments remain safely queued.',
        );
      }
      final payload = jsonDecode(response.body) as Map<String, dynamic>;
      final accepted =
          (payload['accepted_payment_ids'] as List<dynamic>? ?? const [])
              .map((value) => value.toString())
              .toList();
      return SyncResult(SyncResultType.success, acceptedIds: accepted);
    } catch (_) {
      return const SyncResult(
        SyncResultType.failed,
        message: 'Debt payments remain safely queued.',
      );
    }
  }

  Future<List<Map<String, dynamic>>?> pullDebtPayments() async {
    if (!isConfigured) return null;
    try {
      final uri = Uri.parse(
        '${baseUrl.replaceAll(RegExp(r'/$'), '')}/api/v1/debt-payments',
      );
      final response = await http
          .get(uri, headers: _headers)
          .timeout(const Duration(seconds: 15));
      if (response.statusCode < 200 || response.statusCode >= 300) return null;
      final payload = jsonDecode(response.body) as Map<String, dynamic>;
      return (payload['payments'] as List<dynamic>? ?? const [])
          .cast<Map<String, dynamic>>();
    } catch (_) {
      return null;
    }
  }

  Future<bool> pushProducts(List<Product> products) async {
    if (!isConfigured) return false;
    final token = _sessionToken;
    final payload = _changed(
      'products',
      products.map((p) => p.toSyncJson()).toList(),
      'code',
    );
    if (payload.isEmpty) return true;
    try {
      final uri = Uri.parse(
        '${baseUrl.replaceAll(RegExp(r'/$'), '')}/api/v1/products/batch',
      );
      final response = await http
          .post(
            uri,
            headers: {..._headers, 'content-type': 'application/json'},
            body: jsonEncode({'products': payload}),
          )
          .timeout(const Duration(seconds: 15));
      final success = response.statusCode >= 200 && response.statusCode < 300;
      if (success) _acknowledge('products', payload, 'code', token);
      return success;
    } catch (_) {
      return false;
    }
  }

  Future<List<Map<String, dynamic>>?> pullProducts() async {
    if (!isConfigured) return null;
    try {
      final uri = Uri.parse(
        '${baseUrl.replaceAll(RegExp(r'/$'), '')}/api/v1/products',
      );
      final response = await http
          .get(uri, headers: _headers)
          .timeout(const Duration(seconds: 15));
      if (response.statusCode < 200 || response.statusCode >= 300) return null;
      final payload = jsonDecode(response.body) as Map<String, dynamic>;
      return (payload['products'] as List<dynamic>? ?? const [])
          .cast<Map<String, dynamic>>();
    } catch (_) {
      return null;
    }
  }

  Future<bool> pushStockMovements(
    List<StockMovement> movements,
    Map<int, Product> productsById,
  ) async {
    if (!isConfigured) return false;
    final token = _sessionToken;
    final payload = _changed(
      'movements',
      movements
          .where(
            (movement) =>
                movement.type != 'sync_snapshot' &&
                productsById.containsKey(movement.productId),
          )
          .map(
            (movement) => movement.toSyncJson(
              productCode: productsById[movement.productId]!.code,
            ),
          )
          .toList(),
      'movement_uuid',
    );
    if (payload.isEmpty) return true;
    try {
      final uri = Uri.parse(
        '${baseUrl.replaceAll(RegExp(r'/$'), '')}/api/v1/stock-movements/batch',
      );
      final response = await http
          .post(
            uri,
            headers: {..._headers, 'content-type': 'application/json'},
            body: jsonEncode({'movements': payload}),
          )
          .timeout(const Duration(seconds: 20));
      final success = response.statusCode >= 200 && response.statusCode < 300;
      if (success) _acknowledge('movements', payload, 'movement_uuid', token);
      return success;
    } catch (_) {
      return false;
    }
  }

  Future<List<Map<String, dynamic>>?> pullStockMovements() async {
    if (!isConfigured) return null;
    try {
      final uri = Uri.parse(
        '${baseUrl.replaceAll(RegExp(r'/$'), '')}/api/v1/stock-movements',
      );
      final response = await http
          .get(uri, headers: _headers)
          .timeout(const Duration(seconds: 20));
      if (response.statusCode < 200 || response.statusCode >= 300) return null;
      final payload = jsonDecode(response.body) as Map<String, dynamic>;
      return (payload['movements'] as List<dynamic>? ?? const [])
          .cast<Map<String, dynamic>>();
    } catch (_) {
      return null;
    }
  }

  Future<bool> pushCustomers(List<CustomerRecord> customers) async {
    lastCustomerUploadError = null;
    rejectedCustomerPhones.clear();
    if (!isConfigured) return false;
    final token = _sessionToken;
    final payload = _changed(
      'customers',
      customers.map((c) => c.toSyncJson()).toList(),
      'phone',
    );
    if (payload.isEmpty) return true;
    final invalid = payload
        .where((row) => customerSyncIssues(row).isNotEmpty)
        .toList();
    final valid = payload
        .where((row) => customerSyncIssues(row).isEmpty)
        .toList();
    if (invalid.isNotEmpty) {
      rejectedCustomerPhones.addAll(
        invalid.map((row) => row['phone'].toString()),
      );
      final first = invalid.first;
      final label = first['name']?.toString().trim().isNotEmpty == true
          ? first['name'].toString().trim()
          : first['phone'].toString();
      lastCustomerUploadError =
          '${invalid.length} customer contact${invalid.length == 1 ? '' : 's'} need correction: '
          '$label (${customerSyncIssues(first).join(', ')}). Open Customers to edit. '
          'Saved records remain queued.';
    }
    if (valid.isEmpty) return false;
    try {
      final uri = Uri.parse(
        '${baseUrl.replaceAll(RegExp(r'/$'), '')}/api/v1/customers/batch',
      );
      Future<http.Response> send(List<Map<String, Object?>> rows) => http
          .post(
            uri,
            headers: {..._headers, 'content-type': 'application/json'},
            body: jsonEncode({'customers': rows}),
          )
          .timeout(const Duration(seconds: 15));
      var rows = valid;
      var response = await send(rows);
      if (token != _sessionToken) return false;
      if (response.statusCode == 422) {
        // A rejected customer must not block unrelated valid customers.
        // Keep rejected rows unacknowledged so corrections are retried.
        final detail = (jsonDecode(response.body) as Map)['detail'];
        final rejected = <int>{};
        final fields = <String>{};
        if (detail is List) {
          for (final error in detail.whereType<Map>()) {
            final loc = error['loc'];
            if (loc is List &&
                loc.length >= 3 &&
                loc[0] == 'body' &&
                loc[1] == 'customers' &&
                loc[2] is int) {
              rejected.add(loc[2] as int);
              if (loc.length > 3 &&
                  const {
                    'name',
                    'phone',
                    'company_name',
                    'address',
                    'purchase_count',
                    'total_spent_cents',
                  }.contains(loc[3])) {
                fields.add(loc[3].toString());
              }
            }
          }
        }
        rejectedCustomerPhones.addAll(
          rejected
              .where((index) => index >= 0 && index < valid.length)
              .map((index) => valid[index]['phone'].toString()),
        );
        final firstRejected = rejected.isEmpty ? null : valid[rejected.first];
        lastCustomerUploadError ??=
            'Customer upload needs correction: '
            '${firstRejected?['name'] ?? 'unknown contact'}'
            '${fields.isEmpty ? '' : ' (${fields.join(', ')})'}. '
            'Open Customers to edit. Saved records remain queued.';
        if (rejected.isEmpty) return false;
        rows = [
          for (var i = 0; i < valid.length; i++)
            if (!rejected.contains(i)) valid[i],
        ];
        if (rows.isEmpty) return false;
        response = await send(rows);
      }
      if (token != _sessionToken) return false;
      if (response.statusCode < 200 || response.statusCode >= 300) {
        lastCustomerUploadError ??= 'Customers could not upload. Saved records remain queued for retry.';
        return false;
      }
      final accepted =
          (jsonDecode(response.body) as Map)['accepted_phone_keys'];
      if (accepted is! List) return false;
      final confirmed = rows
          .where(
            (row) => accepted.contains(
              row['phone'].toString().replaceAll(RegExp(r'[^0-9+]'), ''),
            ),
          )
          .toList();
      _acknowledge('customers', confirmed, 'phone', token);
      return confirmed.length == payload.length;
    } catch (_) {
      return false;
    }
  }

  Future<bool> deleteCustomer(String phone) async {
    if (!isConfigured) return false;
    try {
      final key = phone.replaceAll(RegExp(r'[^0-9+]'), '');
      final uri = Uri.parse(
        '${baseUrl.replaceAll(RegExp(r'/$'), '')}/api/v1/customers/${Uri.encodeComponent(key)}',
      );
      final response = await http
          .delete(uri, headers: _headers)
          .timeout(const Duration(seconds: 15));
      return response.statusCode >= 200 && response.statusCode < 300;
    } catch (_) {
      return false;
    }
  }

  Future<List<Map<String, dynamic>>?> pullCustomers() async {
    if (!isConfigured) return null;
    try {
      final uri = Uri.parse(
        '${baseUrl.replaceAll(RegExp(r'/$'), '')}/api/v1/customers',
      );
      final response = await http
          .get(uri, headers: _headers)
          .timeout(const Duration(seconds: 15));
      if (response.statusCode < 200 || response.statusCode >= 300) return null;
      final payload = jsonDecode(response.body) as Map<String, dynamic>;
      return (payload['customers'] as List<dynamic>? ?? const [])
          .cast<Map<String, dynamic>>();
    } catch (_) {
      return null;
    }
  }

  Future<bool> pushStockReceipts(List<StockReceipt> receipts) async {
    if (!isConfigured) return false;
    final token = _sessionToken;
    final payload = _changed(
      'receipts',
      receipts.map((r) => r.toSyncJson()).toList(),
      'receipt_uuid',
    );
    if (payload.isEmpty) return true;
    try {
      final uri = Uri.parse(
        '${baseUrl.replaceAll(RegExp(r'/$'), '')}/api/v1/stock-receipts/batch',
      );
      final response = await http
          .post(
            uri,
            headers: {..._headers, 'content-type': 'application/json'},
            body: jsonEncode({'receipts': payload}),
          )
          .timeout(const Duration(seconds: 15));
      final success = response.statusCode >= 200 && response.statusCode < 300;
      if (success) _acknowledge('receipts', payload, 'receipt_uuid', token);
      return success;
    } catch (_) {
      return false;
    }
  }

  Future<ReceiptTemplateSettings?> pullReceiptTemplateSettings({
    required String companyName,
  }) async {
    if (!isConfigured) return null;
    try {
      final uri = Uri.parse(
        '${baseUrl.replaceAll(RegExp(r'/$'), '')}/api/v1/company/receipt-template',
      );
      final response = await http
          .get(uri, headers: _headers)
          .timeout(const Duration(seconds: 15));
      if (response.statusCode < 200 || response.statusCode >= 300) return null;
      final payload = jsonDecode(response.body) as Map<String, dynamic>;
      return ReceiptTemplateSettings.fromJson(
        (payload['receipt_templates'] as Map?)?.cast<String, dynamic>(),
        companyName: companyName,
        legacyActiveTemplate: (payload['receipt_template'] as Map?)
            ?.cast<String, dynamic>(),
      );
    } catch (_) {
      return null;
    }
  }
}
