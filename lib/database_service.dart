import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sqflite/sqflite.dart' show Sqflite;
import 'package:uuid/uuid.dart';

import 'models.dart';
import 'desktop_storage.dart';
import 'formatters.dart' show money;
import 'product_import_service.dart';

class DatabaseService {
  static const _uuid = Uuid();
  Future<void> queueWorkflow(Map<String, dynamic> item) =>
      db.transaction((txn) async {
        final rows = await txn.query(
          'app_meta',
          where: 'key = ?',
          whereArgs: ['workflow.outbox'],
        );
        final outbox = rows.isEmpty
            ? <dynamic>[]
            : jsonDecode(rows.first['value'] as String) as List;
        outbox.removeWhere((value) => value['uuid'] == item['uuid']);
        outbox.add(item);
        await txn.insert('app_meta', {
          'key': 'workflow.outbox',
          'value': jsonEncode(outbox),
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      });
  Future<void> acknowledgeWorkflow(Map<String, dynamic> item) =>
      db.transaction((txn) async {
        final rows = await txn.query(
          'app_meta',
          where: 'key = ?',
          whereArgs: ['workflow.outbox'],
        );
        final outbox = rows.isEmpty
            ? <dynamic>[]
            : jsonDecode(rows.first['value'] as String) as List;
        outbox.removeWhere((value) => jsonEncode(value) == jsonEncode(item));
        await txn.insert('app_meta', {
          'key': 'workflow.outbox',
          'value': jsonEncode(outbox),
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      });
  Future<void> recordApprovedReceipt(Map<String, dynamic> workflow) =>
      db.transaction((txn) async {
        final receipts = await txn.query(
          'stock_receipts',
          where: 'receipt_uuid = ? AND status = ?',
          whereArgs: [workflow['uuid'], 'draft'],
        );
        if (receipts.isEmpty) return;
        final receiptId = receipts.first['id'];
        final details = workflow['details'] as Map;
        final lines = <Map<String, Object?>>[];
        for (final item in details['items'] as List) {
          final products = await txn.query(
            'products',
            columns: ['id'],
            where: 'code = ?',
            whereArgs: [item['product_code']],
          );
          if (products.isEmpty) {
            throw StateError('Approved product not downloaded yet.');
          }
          lines.add({
            'receipt_id': receiptId,
            'product_id': products.first['id'],
            'product_name': item['product_name'],
            'form_name': item['form_name'],
            'quantity_forms': item['quantity_forms'],
            'units_per_form': item['units_per_form'],
            'quantity_base': item['quantity_base'],
            'purchase_cost_cents': item['purchase_cost_cents'],
            'batch_number': item['batch_number'],
            'expiry_date': item['expiry_date'],
          });
        }
        final history = workflow['history'] as List? ?? [];
        final approved = history
            .where((v) => v['action'] == 'approved')
            .lastOrNull;
        await txn.delete(
          'stock_receipt_items',
          where: 'receipt_id = ?',
          whereArgs: [receiptId],
        );
        for (final line in lines) {
          await txn.insert('stock_receipt_items', line);
        }
        // Ledger rows are imported from the server separately: do not add stock here.
        await txn.update(
          'stock_receipts',
          {
            'status': 'confirmed',
            'confirmed_at':
                approved?['at'] ?? DateTime.now().toUtc().toIso8601String(),
            'supplier_name': details['supplier_name'],
            'invoice_number': details['invoice_number'],
          },
          where: 'id = ?',
          whereArgs: [receiptId],
        );
      });

  Future<String?> readWorkflowMeta(String key) async {
    final rows = await db.query('app_meta', where: 'key = ?', whereArgs: [key]);
    return rows.isEmpty ? null : rows.first['value'] as String;
  }

  Future<void> writeWorkflowMeta(String key, String value) async {
    await db.insert('app_meta', {
      'key': key,
      'value': value,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> notifyWorkflow(Map<String, dynamic> item) => _insertNotification(
    db,
    type: 'approval',
    title:
        '${item['kind'] == 'stock' ? 'Received stock' : 'Sale correction'} — ${item['status']}',
    message:
        'Submitted by ${item['submitted_by'] ?? ''}. Open Approvals to review the details.',
    createdAt: DateTime.now(),
    referenceId: 'workflow-${item['uuid']}-${item['revision']}',
  );
  static const _secureStorage = FlutterSecureStorage();
  Database? _db;
  String? _openedCompanyKey;

  Database get db {
    final database = _db;
    if (database == null) {
      throw StateError('The Saleo local database is locked.');
    }
    return database;
  }

  Future<void> initialize({String? companyId}) async {
    final local = Platform.environment['LOCALAPPDATA'];
    if (local == null || local.isEmpty) {
      throw StateError('Windows application data directory is unavailable.');
    }
    final root = path.join(local, 'Saleo_New_Desktop', 'databases');
    await Directory(root).create(recursive: true);
    final companyKey = _databaseCompanyKey(companyId);
    if (_db != null && _openedCompanyKey == companyKey) return;
    await close();
    _openedCompanyKey = companyKey;
    final password = await _databasePasswordFor(companyKey);
    _db = await databaseFactoryFfi.openDatabase(
      path.join(root, '$companyKey.db'),
      options: OpenDatabaseOptions(
        onConfigure: (db) => configureEncryptedDesktopDatabase(db, password),
        version: 12,
        onCreate: (db, _) async {
          await db.execute('''
          CREATE TABLE users (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            username TEXT NOT NULL UNIQUE,
            password_hash TEXT NOT NULL,
            display_name TEXT NOT NULL,
            role TEXT NOT NULL,
            job_title TEXT NOT NULL DEFAULT 'Receptionist',
            active INTEGER NOT NULL DEFAULT 1,
            archived_at TEXT,
            created_at TEXT NOT NULL
          )
        ''');
          await db.execute('''
          CREATE TABLE products (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
            code TEXT NOT NULL UNIQUE,
            category TEXT NOT NULL,
            base_unit TEXT NOT NULL DEFAULT 'unit',
            low_stock_threshold INTEGER NOT NULL DEFAULT 0,
            image_bytes BLOB,
            active INTEGER NOT NULL DEFAULT 1,
            updated_at TEXT NOT NULL
          )
        ''');
          await db.execute('''
          CREATE TABLE selling_forms (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            product_id INTEGER NOT NULL,
            name TEXT NOT NULL,
            price_cents INTEGER NOT NULL,
            units_per_form INTEGER NOT NULL DEFAULT 1,
            active INTEGER NOT NULL DEFAULT 1,
            updated_at TEXT NOT NULL,
            UNIQUE(product_id, name),
            FOREIGN KEY(product_id) REFERENCES products(id)
          )
        ''');
          await db.execute('''
          CREATE TABLE sales (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            transaction_uuid TEXT NOT NULL UNIQUE,
            receipt_number TEXT NOT NULL UNIQUE,
            receptionist_id INTEGER NOT NULL,
            receptionist_username TEXT NOT NULL,
            receptionist_name TEXT NOT NULL,
            customer_name TEXT,
            customer_phone TEXT,
            customer_company TEXT,
            collected_by TEXT,
            collector_phone TEXT,
            previous_debt_cents INTEGER NOT NULL DEFAULT 0,
            operator_label TEXT NOT NULL DEFAULT 'Operator',
            device_id TEXT NOT NULL,
            created_at TEXT NOT NULL,
            total_cents INTEGER NOT NULL,
            payment_method TEXT NOT NULL DEFAULT 'cash',
            cash_cents INTEGER NOT NULL DEFAULT 0,
            mobile_money_cents INTEGER NOT NULL DEFAULT 0,
            cash_tendered_cents INTEGER NOT NULL DEFAULT 0,
            change_given_cents INTEGER NOT NULL DEFAULT 0,
            debt_cents INTEGER NOT NULL DEFAULT 0,
            debt_paid_cents INTEGER NOT NULL DEFAULT 0,
            debt_due_at TEXT,
            debt_note TEXT,
            sync_status TEXT NOT NULL DEFAULT 'pending',
            voided INTEGER NOT NULL DEFAULT 0,
            void_reason TEXT,
            stock_override INTEGER NOT NULL DEFAULT 0,
            FOREIGN KEY(receptionist_id) REFERENCES users(id)
          )
        ''');
          await db.execute('''
          CREATE TABLE sale_items (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            sale_id INTEGER NOT NULL,
            product_id INTEGER NOT NULL,
            product_code TEXT NOT NULL DEFAULT '',
            product_name TEXT NOT NULL,
            form_name TEXT NOT NULL,
            units_per_form INTEGER NOT NULL DEFAULT 1,
            unit_price_cents INTEGER NOT NULL,
            quantity INTEGER NOT NULL,
            line_total_cents INTEGER NOT NULL,
            FOREIGN KEY(sale_id) REFERENCES sales(id)
          )
        ''');
          await db.execute('''
          CREATE TABLE stock_movements (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            movement_uuid TEXT NOT NULL UNIQUE,
            product_id INTEGER NOT NULL,
            type TEXT NOT NULL,
            quantity_base INTEGER NOT NULL,
            actor_name TEXT NOT NULL,
            note TEXT,
            reference_id TEXT,
            created_at TEXT NOT NULL,
            FOREIGN KEY(product_id) REFERENCES products(id)
          )
        ''');
          await db.execute('''
          CREATE TABLE app_notifications (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            type TEXT NOT NULL,
            title TEXT NOT NULL,
            message TEXT NOT NULL,
            product_id INTEGER,
            sale_id INTEGER,
            reference_id TEXT,
            created_at TEXT NOT NULL,
            is_read INTEGER NOT NULL DEFAULT 0,
            resolved_at TEXT
          )
        ''');
          await _createBusinessTables(db);
          await db.execute('''
          CREATE TABLE app_meta (
            key TEXT PRIMARY KEY,
            value TEXT NOT NULL
          )
        ''');
          await db.execute(
            'CREATE INDEX idx_sales_sync ON sales(sync_status, created_at)',
          );
          await db.execute(
            'CREATE INDEX idx_sales_user ON sales(receptionist_id, created_at)',
          );
          await db.execute(
            'CREATE INDEX idx_stock_product_date ON stock_movements(product_id, created_at)',
          );
          await db.execute(
            'CREATE UNIQUE INDEX idx_stock_reference ON stock_movements(product_id, type, reference_id) WHERE reference_id IS NOT NULL',
          );
          await db.execute(
            'CREATE INDEX idx_notifications_unread ON app_notifications(is_read, created_at)',
          );
        },
        onUpgrade: (db, oldVersion, _) async {
          if (oldVersion < 2) {
            await db.execute(
              "ALTER TABLE sales ADD COLUMN payment_method TEXT NOT NULL DEFAULT 'cash'",
            );
            await db.execute(
              'ALTER TABLE sales ADD COLUMN cash_cents INTEGER NOT NULL DEFAULT 0',
            );
            await db.execute(
              'ALTER TABLE sales ADD COLUMN mobile_money_cents INTEGER NOT NULL DEFAULT 0',
            );
            await db.execute(
              'UPDATE sales SET cash_cents = total_cents WHERE cash_cents = 0',
            );
          }
          if (oldVersion < 3) {
            await db.execute('ALTER TABLE sales ADD COLUMN customer_name TEXT');
          }
          if (oldVersion < 4) {
            await db.execute(
              "ALTER TABLE products ADD COLUMN base_unit TEXT NOT NULL DEFAULT 'unit'",
            );
            await db.execute(
              'ALTER TABLE products ADD COLUMN low_stock_threshold INTEGER NOT NULL DEFAULT 0',
            );
            await db.execute(
              'ALTER TABLE selling_forms ADD COLUMN units_per_form INTEGER NOT NULL DEFAULT 1',
            );
            await db.execute(
              'ALTER TABLE sales ADD COLUMN stock_override INTEGER NOT NULL DEFAULT 0',
            );
            await db.execute(
              "ALTER TABLE sale_items ADD COLUMN product_code TEXT NOT NULL DEFAULT ''",
            );
            await db.execute(
              'ALTER TABLE sale_items ADD COLUMN units_per_form INTEGER NOT NULL DEFAULT 1',
            );
            await db.execute('''
            CREATE TABLE stock_movements (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              movement_uuid TEXT NOT NULL UNIQUE,
              product_id INTEGER NOT NULL,
              type TEXT NOT NULL,
              quantity_base INTEGER NOT NULL,
              actor_name TEXT NOT NULL,
              note TEXT,
              reference_id TEXT,
              created_at TEXT NOT NULL,
              FOREIGN KEY(product_id) REFERENCES products(id)
            )
          ''');
            await db.execute('''
            CREATE TABLE app_notifications (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              type TEXT NOT NULL,
              title TEXT NOT NULL,
              message TEXT NOT NULL,
              product_id INTEGER,
              sale_id INTEGER,
              reference_id TEXT,
              created_at TEXT NOT NULL,
              is_read INTEGER NOT NULL DEFAULT 0
            )
          ''');
            await db.execute(
              'CREATE INDEX idx_stock_product_date ON stock_movements(product_id, created_at)',
            );
            await db.execute(
              'CREATE UNIQUE INDEX idx_stock_reference ON stock_movements(product_id, type, reference_id) WHERE reference_id IS NOT NULL',
            );
            await db.execute(
              'CREATE INDEX idx_notifications_unread ON app_notifications(is_read, created_at)',
            );
          }
          if (oldVersion < 5) {
            await db.execute('ALTER TABLE users ADD COLUMN archived_at TEXT');
          }
          if (oldVersion < 6) {
            await db.execute(
              "ALTER TABLE users ADD COLUMN job_title TEXT NOT NULL DEFAULT 'Receptionist'",
            );
            await db.execute(
              'ALTER TABLE sales ADD COLUMN customer_phone TEXT',
            );
            await db.execute(
              "ALTER TABLE sales ADD COLUMN operator_label TEXT NOT NULL DEFAULT 'Operator'",
            );
            await db.execute(
              'ALTER TABLE app_notifications ADD COLUMN resolved_at TEXT',
            );
            await _createBusinessTables(db);
            final negativeBalances = await db.rawQuery(
              'SELECT product_id, SUM(quantity_base) AS quantity '
              'FROM stock_movements GROUP BY product_id '
              'HAVING SUM(quantity_base) < 0',
            );
            final migratedAt = DateTime.now().toUtc().toIso8601String();
            for (final row in negativeBalances) {
              final productId = row['product_id'] as int;
              final shortage = -((row['quantity'] as num).toInt());
              await db.insert('stock_discrepancies', {
                'product_id': productId,
                'quantity_base': shortage,
                'created_at': migratedAt,
                'created_by': 'Saleo migration',
              });
              await db.insert('stock_movements', {
                'movement_uuid': _uuid.v4(),
                'product_id': productId,
                'type': 'discrepancy_separated',
                'quantity_base': shortage,
                'actor_name': 'Saleo migration',
                'note': 'Moved negative stock into unresolved discrepancies',
                'created_at': migratedAt,
              });
            }
          }
          if (oldVersion < 7) {
            await db.execute(
              'ALTER TABLE sales ADD COLUMN customer_company TEXT',
            );
            await db.execute(
              'ALTER TABLE customers ADD COLUMN company_name TEXT NOT NULL DEFAULT ""',
            );
          }
          if (oldVersion < 8) {
            await db.execute(
              'ALTER TABLE products ADD COLUMN image_bytes BLOB',
            );
            await db.execute(
              'ALTER TABLE sales ADD COLUMN cash_tendered_cents INTEGER NOT NULL DEFAULT 0',
            );
            await db.execute(
              'ALTER TABLE sales ADD COLUMN change_given_cents INTEGER NOT NULL DEFAULT 0',
            );
            await db.execute(
              'UPDATE sales SET cash_tendered_cents = cash_cents WHERE cash_tendered_cents = 0',
            );
          }
          if (oldVersion < 9) {
            await db.execute(
              'ALTER TABLE sales ADD COLUMN debt_cents INTEGER NOT NULL DEFAULT 0',
            );
            await db.execute(
              'ALTER TABLE sales ADD COLUMN debt_paid_cents INTEGER NOT NULL DEFAULT 0',
            );
            await db.execute('ALTER TABLE sales ADD COLUMN debt_due_at TEXT');
            await db.execute('ALTER TABLE sales ADD COLUMN debt_note TEXT');
          }
          if (oldVersion < 10) {
            await db.execute('ALTER TABLE sales ADD COLUMN collected_by TEXT');
            await db.execute(
              'ALTER TABLE sales ADD COLUMN collector_phone TEXT',
            );
            await db.execute(
              'ALTER TABLE sales ADD COLUMN previous_debt_cents INTEGER NOT NULL DEFAULT 0',
            );
            await _createDebtLedgerTables(db);
          }
          if (oldVersion < 11) {
            await db.execute(
              'ALTER TABLE customers ADD COLUMN address TEXT NOT NULL DEFAULT ""',
            );
          }
          if (oldVersion < 12) {
            final columns = await db.rawQuery(
              'PRAGMA table_info(debt_payments)',
            );
            for (final field in {
              'payer_name': 'TEXT',
              'payer_phone': 'TEXT',
              'balance_before_cents': 'INTEGER',
              'balance_after_cents': 'INTEGER',
            }.entries) {
              if (!columns.any((column) => column['name'] == field.key)) {
                await db.execute(
                  'ALTER TABLE debt_payments ADD COLUMN ${field.key} ${field.value}',
                );
              }
            }
          }
        },
      ),
    );
    await _seed();
  }

  Future<void> switchCompany(String companyId) =>
      initialize(companyId: companyId);

  Future<void> lock() async {
    await close();
    _openedCompanyKey = null;
  }

  Future<void> close() async {
    final database = _db;
    _db = null;
    if (database != null) await database.close();
  }

  static String _databaseCompanyKey(String? companyId) {
    final clean = (companyId ?? 'device-setup').trim().toUpperCase().replaceAll(
      RegExp(r'[^A-Z0-9]+'),
      '-',
    );
    final source = clean.isEmpty ? 'device-setup' : clean;
    final digest = sha256.convert(utf8.encode('saleo-db:$source')).toString();
    return 'saleo_$digest';
  }

  static Future<String> _databasePasswordFor(String companyKey) async {
    final storageKey = 'saleo_new_desktop.local_database_key.$companyKey';
    final existing = await _secureStorage.read(key: storageKey);
    if (existing != null && existing.length >= 48) return existing;
    final random = Random.secure();
    final bytes = List<int>.generate(48, (_) => random.nextInt(256));
    final password = base64UrlEncode(bytes);
    await _secureStorage.write(key: storageKey, value: password);
    return password;
  }

  static Future<void> _createBusinessTables(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS customers (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        phone TEXT NOT NULL,
        phone_key TEXT NOT NULL UNIQUE,
        company_name TEXT NOT NULL DEFAULT '',
        address TEXT NOT NULL DEFAULT '',
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        last_purchase_at TEXT,
        purchase_count INTEGER NOT NULL DEFAULT 0,
        total_spent_cents INTEGER NOT NULL DEFAULT 0
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS stock_discrepancies (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        product_id INTEGER NOT NULL,
        quantity_base INTEGER NOT NULL,
        sale_id INTEGER,
        created_at TEXT NOT NULL,
        created_by TEXT NOT NULL,
        resolved_at TEXT,
        resolved_by TEXT,
        resolution_reason TEXT,
        FOREIGN KEY(product_id) REFERENCES products(id),
        FOREIGN KEY(sale_id) REFERENCES sales(id)
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS stock_receipts (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        receipt_uuid TEXT NOT NULL UNIQUE,
        status TEXT NOT NULL DEFAULT 'draft',
        supplier_name TEXT,
        invoice_number TEXT,
        created_at TEXT NOT NULL,
        confirmed_at TEXT,
        created_by TEXT NOT NULL,
        reversed_at TEXT,
        reversal_reason TEXT
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS stock_receipt_items (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        receipt_id INTEGER NOT NULL,
        product_id INTEGER NOT NULL,
        product_name TEXT NOT NULL,
        form_name TEXT NOT NULL,
        quantity_forms INTEGER NOT NULL,
        units_per_form INTEGER NOT NULL,
        quantity_base INTEGER NOT NULL,
        purchase_cost_cents INTEGER,
        batch_number TEXT,
        expiry_date TEXT,
        FOREIGN KEY(receipt_id) REFERENCES stock_receipts(id),
        FOREIGN KEY(product_id) REFERENCES products(id)
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_customers_name ON customers(name)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_discrepancies_product ON stock_discrepancies(product_id, resolved_at)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_stock_receipts_date ON stock_receipts(status, confirmed_at)',
    );
    await _createDebtLedgerTables(db);
  }

  static Future<void> _createDebtLedgerTables(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS debt_payments (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        payment_uuid TEXT NOT NULL UNIQUE,
        customer_name TEXT NOT NULL,
        customer_phone TEXT NOT NULL,
        customer_company TEXT NOT NULL DEFAULT '',
        amount_cents INTEGER NOT NULL,
        cash_cents INTEGER NOT NULL DEFAULT 0,
        mobile_money_cents INTEGER NOT NULL DEFAULT 0,
        payment_method TEXT NOT NULL,
        received_by TEXT NOT NULL,
        payer_name TEXT,
        payer_phone TEXT,
        balance_before_cents INTEGER,
        balance_after_cents INTEGER,
        note TEXT,
        created_at TEXT NOT NULL,
        sync_status TEXT NOT NULL DEFAULT 'pending'
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_debt_payments_customer ON debt_payments(customer_phone, created_at)',
    );
  }

  Future<void> _seed() async {
    final device = await db.query(
      'app_meta',
      where: 'key = ?',
      whereArgs: ['device_id'],
      limit: 1,
    );
    if (device.isEmpty) {
      await db.insert('app_meta', {'key': 'device_id', 'value': _uuid.v4()});
    }
  }

  Future<AppUser> upsertAuthenticatedUser({
    required String username,
    required String displayName,
    required UserRole role,
    String jobTitle = 'Receptionist',
  }) async {
    final normalized = username.trim().toLowerCase();
    final existing = await db.query(
      'users',
      where: 'LOWER(username) = ?',
      whereArgs: [normalized],
      limit: 1,
    );
    if (existing.isEmpty) {
      final id = await db.insert('users', {
        'username': normalized,
        'password_hash': 'server-authenticated',
        'display_name': displayName.trim(),
        'role': role.name,
        'job_title': role == UserRole.admin ? 'Administrator' : jobTitle.trim(),
        'active': 1,
        'created_at': DateTime.now().toUtc().toIso8601String(),
      });
      return AppUser(
        id: id,
        username: normalized,
        displayName: displayName.trim(),
        role: role,
        active: true,
        archivedAt: null,
        jobTitle: role == UserRole.admin ? 'Administrator' : jobTitle.trim(),
      );
    }
    final id = existing.first['id'] as int;
    await db.update(
      'users',
      {
        'password_hash': 'server-authenticated',
        'display_name': displayName.trim(),
        'role': role.name,
        'job_title': role == UserRole.admin ? 'Administrator' : jobTitle.trim(),
        'active': 1,
        'archived_at': null,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
    final refreshed = await db.query(
      'users',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return AppUser.fromMap(refreshed.first);
  }

  Future<List<AppUser>> getUsers() async {
    final rows = await db.query(
      'users',
      orderBy: 'archived_at IS NOT NULL, role, display_name',
    );
    return rows.map(AppUser.fromMap).toList();
  }

  Future<void> setUserActive(int id, bool active) => db.update(
    'users',
    {'active': active ? 1 : 0},
    where: 'id = ?',
    whereArgs: [id],
  );

  Future<void> updateStaffDetails({
    required int id,
    required String username,
    required String displayName,
    required String jobTitle,
  }) => db.update(
    'users',
    {
      'username': username.trim().toLowerCase(),
      'display_name': displayName.trim(),
      'job_title': jobTitle.trim(),
    },
    where: "id = ? AND role = 'receptionist' AND archived_at IS NULL",
    whereArgs: [id],
  );

  Future<void> archiveUser(int id) async {
    final updated = await db.update(
      'users',
      {'active': 0, 'archived_at': DateTime.now().toUtc().toIso8601String()},
      where: 'id = ? AND active = 0 AND archived_at IS NULL',
      whereArgs: [id],
    );
    if (updated == 0) {
      throw StateError('Deactivate this staff member before archiving.');
    }
  }

  Future<void> restoreUser(int id) => db.update(
    'users',
    {'active': 0, 'archived_at': null},
    where: "id = ? AND archived_at IS NOT NULL AND datetime(archived_at, '+90 days') > datetime('now')",
    whereArgs: [id],
  );

  Future<List<Product>> getProducts({bool includeInactive = false}) async {
    final productRows = await db.query(
      'products',
      where: includeInactive ? null : 'active = 1',
      orderBy: 'category, name',
    );
    final products = <Product>[];
    for (final row in productRows) {
      final id = row['id'] as int;
      final stockRows = await db.rawQuery(
        'SELECT COALESCE(SUM(quantity_base), 0) AS quantity '
        'FROM stock_movements WHERE product_id = ?',
        [id],
      );
      final calculatedStock =
          (stockRows.first['quantity'] as num?)?.toInt() ?? 0;
      final currentStock = calculatedStock < 0 ? 0 : calculatedStock;
      final formRows = await db.query(
        'selling_forms',
        where: includeInactive
            ? 'product_id = ?'
            : 'product_id = ? AND active = 1',
        whereArgs: [id],
        orderBy: 'id ASC',
      );
      products.add(
        Product(
          id: id,
          name: row['name'] as String,
          code: row['code'] as String,
          category: row['category'] as String,
          active: (row['active'] as int) == 1,
          forms: formRows.map(SellingForm.fromMap).toList(),
          baseUnit: row['base_unit'] as String? ?? 'unit',
          currentStock: currentStock,
          lowStockThreshold: (row['low_stock_threshold'] as num?)?.toInt() ?? 0,
          imageBytes: row['image_bytes'] as Uint8List?,
        ),
      );
    }
    return products;
  }

  Future<void> addProduct({
    required String name,
    required String code,
    required String category,
    required String formName,
    required int priceCents,
    required String baseUnit,
    required int unitsPerForm,
    required int openingStockBase,
    required int lowStockThreshold,
    required String actorName,
    Uint8List? imageBytes,
  }) async {
    await db.transaction((txn) async {
      final now = DateTime.now().toUtc().toIso8601String();
      final id = await txn.insert('products', {
        'name': name.trim(),
        'code': code.trim().toUpperCase(),
        'category': category.trim(),
        'base_unit': baseUnit.trim().toLowerCase(),
        'low_stock_threshold': lowStockThreshold,
        'image_bytes': imageBytes,
        'active': 1,
        'updated_at': now,
      });
      await txn.insert('selling_forms', {
        'product_id': id,
        'name': formName.trim(),
        'price_cents': priceCents,
        'units_per_form': unitsPerForm,
        'active': 1,
        'updated_at': now,
      });
      if (openingStockBase > 0) {
        await txn.insert('stock_movements', {
          'movement_uuid': _uuid.v4(),
          'product_id': id,
          'type': 'opening',
          'quantity_base': openingStockBase,
          'actor_name': actorName,
          'note': 'Opening stock',
          'created_at': now,
        });
      }
    });
  }

  Future<void> importProducts(List<ProductImportRow> rows) async {
    await db.transaction((txn) async {
      final now = DateTime.now().toUtc().toIso8601String();
      for (final row in rows) {
        final existing = await txn.query(
          'products',
          columns: ['id'],
          where: 'code = ?',
          whereArgs: [row.code],
          limit: 1,
        );
        late final int productId;
        final productValues = {
          'name': row.name.trim(),
          'code': row.code.trim().toUpperCase(),
          'category': row.category.trim(),
          'base_unit': row.baseUnit.trim().toLowerCase(),
          'low_stock_threshold': row.lowStockThreshold,
          'active': row.productActive ? 1 : 0,
          'updated_at': now,
        };
        if (existing.isEmpty) {
          productId = await txn.insert('products', {...productValues});
          if (row.openingStockBase > 0) {
            await txn.insert('stock_movements', {
              'movement_uuid': _uuid.v4(),
              'product_id': productId,
              'type': 'opening',
              'quantity_base': row.openingStockBase,
              'actor_name': 'Product import',
              'note': 'Opening stock from import template',
              'created_at': now,
            });
          }
        } else {
          productId = existing.first['id'] as int;
          await txn.update(
            'products',
            productValues,
            where: 'id = ?',
            whereArgs: [productId],
          );
        }
        await txn.insert('selling_forms', {
          'product_id': productId,
          'name': row.form.trim(),
          'price_cents': row.priceCents,
          'units_per_form': row.unitsPerForm,
          'active': row.formActive ? 1 : 0,
          'updated_at': now,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
    });
  }

  Future<void> setProductActive(int id, bool active) => db.update(
    'products',
    {
      'active': active ? 1 : 0,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    },
    where: 'id = ?',
    whereArgs: [id],
  );

  Future<void> updateProductDetails({
    required int id,
    required String name,
    required String category,
    Uint8List? imageBytes,
    required bool removeImage,
  }) => db.update(
    'products',
    {
      'name': name.trim(),
      'category': category.trim(),
      if (removeImage || imageBytes != null) 'image_bytes': imageBytes,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    },
    where: 'id = ?',
    whereArgs: [id],
  );

  Future<void> addSellingForm({
    required int productId,
    required String name,
    required int priceCents,
    required int unitsPerForm,
  }) => db.insert('selling_forms', {
    'product_id': productId,
    'name': name.trim(),
    'price_cents': priceCents,
    'units_per_form': unitsPerForm,
    'active': 1,
    'updated_at': DateTime.now().toUtc().toIso8601String(),
  });

  Future<void> updateSellingForm({
    required int id,
    required String name,
    required int priceCents,
    required bool active,
    required int unitsPerForm,
    String actorName = 'Administrator',
  }) => db.transaction((txn) async {
    if (name.trim().isEmpty || priceCents <= 0 || unitsPerForm <= 0) {
      throw ArgumentError('Enter a valid name, price and unit count.');
    }
    final rows = await txn.query(
      'selling_forms',
      where: 'id = ?',
      whereArgs: [id],
    );
    if (rows.isEmpty) throw StateError('Selling form no longer exists.');
    final old = rows.single;
    final at = DateTime.now().toUtc().toIso8601String();
    if (old['price_cents'] != priceCents) {
      await txn.insert('app_meta', {
        'key': 'price.history.${old['product_id']}.$at.${_uuid.v4()}',
        'value': jsonEncode({
          'form': name.trim(),
          'old': old['price_cents'],
          'new': priceCents,
          'actor': actorName,
          'at': at,
        }),
      });
    }
    await txn.update(
      'selling_forms',
      {
        'name': name.trim(),
        'price_cents': priceCents,
        'units_per_form': unitsPerForm,
        'active': active ? 1 : 0,
        'updated_at': at,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  });

  Future<List<Map<String, dynamic>>> productPriceHistory(int productId) async {
    final rows = await db.query(
      'app_meta',
      where: 'key LIKE ?',
      whereArgs: ['price.history.$productId.%'],
      orderBy: 'key DESC',
      limit: 200,
    );
    return rows
        .map(
          (r) =>
              (jsonDecode(r['value'] as String) as Map).cast<String, dynamic>(),
        )
        .toList();
  }

  Future<void> bulkUpdateProducts(
    Set<int> ids, {
    bool? active,
    String? category,
  }) => db.transaction((txn) async {
    if (ids.isEmpty || (active == null && category == null)) return;
    if (category != null && category.trim().isEmpty) {
      throw ArgumentError('Choose a category.');
    }
    final at = DateTime.now().toUtc().toIso8601String();
    for (final id in ids) {
      final changed = await txn.update(
        'products',
        {
          if (active != null) 'active': active ? 1 : 0,
          if (category != null) 'category': category.trim(),
          'updated_at': at,
        },
        where: 'id = ?',
        whereArgs: [id],
      );
      if (changed != 1) {
        throw StateError('A selected product no longer exists.');
      }
    }
  });

  Future<Sale> createSale(
    AppUser user,
    List<CartLine> cart, {
    required String paymentMethod,
    required int cashCents,
    required int mobileMoneyCents,
    required int cashTenderedCents,
    required int changeGivenCents,
    String? desktopDraftKey,
    int debtCents = 0,
    int debtPaidCents = 0,
    DateTime? debtDueAt,
    String? debtNote,
    String? customerName,
    String? customerPhone,
    String? customerCompany,
    String? customerAddress,
    String? collectedBy,
    String? collectorPhone,
    String operatorLabel = 'Operator',
    bool allowStockOverride = false,
  }) async {
    if (debtCents > 0 &&
        ((customerCompany?.trim().isEmpty ?? true) ||
            (customerPhone?.trim().isEmpty ?? true) ||
            (customerAddress?.trim().isEmpty ?? true) ||
            (collectedBy?.trim().isEmpty ?? true) ||
            (collectorPhone?.trim().isEmpty ?? true))) {
      throw StateError(
        'Credit sales require company, address and receiver details.',
      );
    }
    final transactionUuid = _uuid.v4();
    final suffix = transactionUuid
        .replaceAll('-', '')
        .substring(0, 8)
        .toUpperCase();
    final receipt = 'RCP-$suffix';
    final createdAt = DateTime.now().toUtc();
    final deviceRows = await db.query(
      'app_meta',
      where: 'key = ?',
      whereArgs: ['device_id'],
      limit: 1,
    );
    final deviceId = deviceRows.first['value'] as String;
    final total = cart.fold<int>(0, (sum, line) => sum + line.lineTotalCents);
    late int saleId;
    var stockOverride = false;
    var previousDebtCents = 0;
    await db.transaction((txn) async {
      final debtPhoneKey = _phoneKey(customerPhone?.trim() ?? '');
      if (debtPhoneKey.isNotEmpty) {
        previousDebtCents = await _outstandingDebtForPhone(txn, debtPhoneKey);
      }
      final requiredByProduct = <int, int>{};
      for (final line in cart) {
        requiredByProduct.update(
          line.product.id,
          (value) => value + (line.quantity * line.form.unitsPerForm),
          ifAbsent: () => line.quantity * line.form.unitsPerForm,
        );
      }
      final stockBefore = <int, int>{};
      final shortageProductIds = <int>[];
      for (final entry in requiredByProduct.entries) {
        final calculated = await _stockForProduct(txn, entry.key);
        final available = calculated < 0 ? 0 : calculated;
        stockBefore[entry.key] = available;
        if (entry.value > available) shortageProductIds.add(entry.key);
      }
      stockOverride = shortageProductIds.isNotEmpty;
      if (stockOverride && !allowStockOverride) {
        throw InventoryShortageException(shortageProductIds);
      }
      saleId = await txn.insert('sales', {
        'transaction_uuid': transactionUuid,
        'receipt_number': receipt,
        'receptionist_id': user.id,
        'receptionist_username': user.username,
        'receptionist_name': user.displayName,
        'customer_name': customerName?.trim().isEmpty ?? true
            ? null
            : customerName!.trim(),
        'customer_phone': customerPhone?.trim().isEmpty ?? true
            ? null
            : customerPhone!.trim(),
        'customer_company': customerCompany?.trim().isEmpty ?? true
            ? null
            : customerCompany!.trim(),
        'collected_by': collectedBy?.trim().isEmpty ?? true
            ? null
            : collectedBy!.trim(),
        'collector_phone': collectorPhone?.trim().isEmpty ?? true
            ? null
            : collectorPhone!.trim(),
        'previous_debt_cents': previousDebtCents,
        'operator_label': operatorLabel.trim().isEmpty
            ? 'Operator'
            : operatorLabel.trim(),
        'device_id': deviceId,
        'created_at': createdAt.toIso8601String(),
        'total_cents': total,
        'payment_method': paymentMethod,
        'cash_cents': cashCents,
        'mobile_money_cents': mobileMoneyCents,
        'cash_tendered_cents': cashTenderedCents,
        'change_given_cents': changeGivenCents,
        'debt_cents': debtCents,
        'debt_paid_cents': debtPaidCents,
        'debt_due_at': debtDueAt?.toUtc().toIso8601String(),
        'debt_note': debtNote?.trim().isEmpty ?? true ? null : debtNote!.trim(),
        'sync_status': 'pending',
        'voided': 0,
        'stock_override': stockOverride ? 1 : 0,
      });
      final cleanPhone = customerPhone?.trim() ?? '';
      if (cleanPhone.isNotEmpty) {
        final cleanName = customerName?.trim().isNotEmpty == true
            ? customerName!.trim()
            : cleanPhone;
        final cleanCompany = customerCompany?.trim() ?? '';
        final cleanAddress = customerAddress?.trim() ?? '';
        final phoneKey = _phoneKey(cleanPhone);
        final existingCustomer = await txn.query(
          'customers',
          columns: ['id'],
          where: 'phone_key = ?',
          whereArgs: [phoneKey],
          limit: 1,
        );
        if (existingCustomer.isEmpty) {
          await txn.insert('customers', {
            'name': cleanName,
            'phone': cleanPhone,
            'phone_key': phoneKey,
            'company_name': cleanCompany,
            'address': cleanAddress,
            'created_at': createdAt.toIso8601String(),
            'updated_at': createdAt.toIso8601String(),
            'last_purchase_at': createdAt.toIso8601String(),
            'purchase_count': 1,
            'total_spent_cents': total,
          });
        } else {
          await txn.rawUpdate(
            'UPDATE customers SET name = ?, phone = ?, updated_at = ?, '
            'company_name = ?, address = ?, last_purchase_at = ?, '
            'purchase_count = purchase_count + 1, '
            'total_spent_cents = total_spent_cents + ? WHERE id = ?',
            [
              cleanName,
              cleanPhone,
              createdAt.toIso8601String(),
              cleanCompany,
              cleanAddress,
              createdAt.toIso8601String(),
              total,
              existingCustomer.first['id'],
            ],
          );
        }
      }
      for (final line in cart) {
        await txn.insert('sale_items', {
          'sale_id': saleId,
          'product_id': line.product.id,
          'product_code': line.product.code,
          'product_name': line.product.name,
          'form_name': line.form.name,
          'units_per_form': line.form.unitsPerForm,
          'unit_price_cents': line.form.priceCents,
          'quantity': line.quantity,
          'line_total_cents': line.lineTotalCents,
        });
      }
      for (final entry in requiredByProduct.entries) {
        final before = stockBefore[entry.key] ?? 0;
        final deducted = entry.value > before ? before : entry.value;
        final discrepancy = entry.value - deducted;
        if (deducted > 0) {
          await _insertStockMovement(
            txn,
            productId: entry.key,
            type: 'sale',
            quantityBase: -deducted,
            actorName: user.displayName,
            note: discrepancy > 0
                ? 'Available stock deducted; shortage recorded separately'
                : 'Sale $receipt',
            referenceId: transactionUuid,
            createdAt: createdAt,
          );
        }
        final product = await txn.query(
          'products',
          columns: ['name', 'base_unit', 'low_stock_threshold'],
          where: 'id = ?',
          whereArgs: [entry.key],
          limit: 1,
        );
        if (product.isEmpty) continue;
        final after = before - deducted;
        final threshold =
            (product.first['low_stock_threshold'] as num?)?.toInt() ?? 0;
        if (discrepancy > 0) {
          await txn.insert('stock_discrepancies', {
            'product_id': entry.key,
            'quantity_base': discrepancy,
            'sale_id': saleId,
            'created_at': createdAt.toIso8601String(),
            'created_by': user.displayName,
          });
          await _insertNotification(
            txn,
            type: 'stock_discrepancy',
            title: 'Stock count needs attention',
            message:
                '$discrepancy ${product.first['base_unit']} of '
                '${product.first['name']} were sold without recorded stock. '
                'Newly received stock will not be reduced by this discrepancy.',
            productId: entry.key,
            saleId: saleId,
            referenceId: 'stock-override-$transactionUuid-${entry.key}',
            createdAt: createdAt,
          );
        } else if (threshold > 0 &&
            before > threshold &&
            after <= threshold &&
            await _preferenceEnabled(
              txn,
              'notify_low_stock',
              defaultValue: true,
            )) {
          await _insertNotification(
            txn,
            type: 'low_stock',
            title: 'Low Stock Alert',
            message:
                '${product.first['name']} is below your stock limit. '
                'Only $after ${product.first['base_unit']} remaining.',
            productId: entry.key,
            saleId: saleId,
            referenceId: 'low-stock-$transactionUuid-${entry.key}',
            createdAt: createdAt,
          );
        }
      }
      if (await _preferenceEnabled(txn, 'notify_every_sale')) {
        await _insertNotification(
          txn,
          type: 'sale',
          title: 'New Sale Recorded',
          message:
              '${cart.fold<int>(0, (count, line) => count + line.quantity)} items sold. '
              'Total: GHS ${money(total)}\nRecorded by ${user.displayName} · $receipt',
          saleId: saleId,
          referenceId: 'sale-$transactionUuid',
          createdAt: createdAt,
        );
      }
      if (desktopDraftKey != null) {
        await txn.delete(
          'app_meta',
          where: 'key = ?',
          whereArgs: [desktopDraftKey],
        );
      }
    });
    return Sale(
      id: saleId,
      transactionUuid: transactionUuid,
      receiptNumber: receipt,
      receptionistId: user.id,
      receptionistUsername: user.username,
      receptionistName: user.displayName,
      customerName: customerName?.trim().isEmpty ?? true
          ? null
          : customerName!.trim(),
      customerPhone: customerPhone?.trim().isEmpty ?? true
          ? null
          : customerPhone!.trim(),
      customerCompany: customerCompany?.trim().isEmpty ?? true
          ? null
          : customerCompany!.trim(),
      collectedBy: collectedBy?.trim().isEmpty ?? true
          ? null
          : collectedBy!.trim(),
      collectorPhone: collectorPhone?.trim().isEmpty ?? true
          ? null
          : collectorPhone!.trim(),
      previousDebtCents: previousDebtCents,
      operatorLabel: operatorLabel.trim().isEmpty
          ? 'Operator'
          : operatorLabel.trim(),
      deviceId: deviceId,
      createdAt: createdAt,
      totalCents: total,
      paymentMethod: paymentMethod,
      cashCents: cashCents,
      mobileMoneyCents: mobileMoneyCents,
      cashTenderedCents: cashTenderedCents,
      changeGivenCents: changeGivenCents,
      debtCents: debtCents,
      debtPaidCents: debtPaidCents,
      debtDueAt: debtDueAt,
      debtNote: debtNote?.trim().isEmpty ?? true ? null : debtNote!.trim(),
      syncStatus: 'pending',
      voided: false,
      stockOverride: stockOverride,
      items: cart
          .map(
            (line) => SaleItem(
              productId: line.product.id,
              productCode: line.product.code,
              productName: line.product.name,
              formName: line.form.name,
              unitsPerForm: line.form.unitsPerForm,
              unitPriceCents: line.form.priceCents,
              quantity: line.quantity,
              lineTotalCents: line.lineTotalCents,
            ),
          )
          .toList(),
    );
  }

  Future<List<Sale>> getSales({String? receptionistUsername}) =>
      _readSales(receptionistUsername: receptionistUsername);

  Future<List<Sale>> _readSales({
    String? receptionistUsername,
    bool pendingOnly = false,
  }) async {
    final rows = await db.query(
      'sales',
      where: pendingOnly
          ? "sync_status != 'synced'"
          : receptionistUsername == null
          ? null
          : 'receptionist_username = ?',
      whereArgs: receptionistUsername == null ? null : [receptionistUsername],
      orderBy: 'created_at DESC',
    );
    // Fetch receipt lines in bounded batches rather than one query per receipt.
    final itemsBySale = <int, List<Map<String, Object?>>>{};
    for (var offset = 0; offset < rows.length; offset += 400) {
      final ids = rows.skip(offset).take(400).map((row) => row['id']).toList();
      final itemRows = await db.query(
        'sale_items',
        where: 'sale_id IN (${List.filled(ids.length, '?').join(',')})',
        whereArgs: ids,
        orderBy: 'id',
      );
      for (final item in itemRows) {
        (itemsBySale[item['sale_id'] as int] ??= []).add(item);
      }
    }
    final sales = <Sale>[];
    for (final row in rows) {
      final itemRows = itemsBySale[row['id']] ?? const [];
      sales.add(
        Sale(
          id: row['id'] as int,
          transactionUuid: row['transaction_uuid'] as String,
          receiptNumber: row['receipt_number'] as String,
          receptionistId: row['receptionist_id'] as int,
          receptionistUsername: row['receptionist_username'] as String,
          receptionistName: row['receptionist_name'] as String,
          customerName: row['customer_name'] as String?,
          customerPhone: row['customer_phone'] as String?,
          customerCompany: row['customer_company'] as String?,
          collectedBy: row['collected_by'] as String?,
          collectorPhone: row['collector_phone'] as String?,
          previousDebtCents: (row['previous_debt_cents'] as num?)?.toInt() ?? 0,
          operatorLabel: row['operator_label'] as String? ?? 'Operator',
          deviceId: row['device_id'] as String,
          createdAt: DateTime.parse(row['created_at'] as String),
          totalCents: row['total_cents'] as int,
          paymentMethod: row['payment_method'] as String? ?? 'cash',
          cashCents:
              (row['cash_cents'] as num?)?.toInt() ??
              (row['total_cents'] as int),
          mobileMoneyCents: (row['mobile_money_cents'] as num?)?.toInt() ?? 0,
          cashTenderedCents:
              (row['cash_tendered_cents'] as num?)?.toInt() ??
              (row['cash_cents'] as num?)?.toInt() ??
              0,
          changeGivenCents: (row['change_given_cents'] as num?)?.toInt() ?? 0,
          debtCents: (row['debt_cents'] as num?)?.toInt() ?? 0,
          debtPaidCents: (row['debt_paid_cents'] as num?)?.toInt() ?? 0,
          debtDueAt: row['debt_due_at'] == null
              ? null
              : DateTime.parse(row['debt_due_at'] as String),
          debtNote: row['debt_note'] as String?,
          syncStatus: row['sync_status'] as String,
          voided: (row['voided'] as int) == 1,
          voidReason: row['void_reason'] as String?,
          stockOverride: (row['stock_override'] as int? ?? 0) == 1,
          items: itemRows
              .map(
                (item) => SaleItem(
                  productId: item['product_id'] as int,
                  productCode: item['product_code'] as String? ?? '',
                  productName: item['product_name'] as String,
                  formName: item['form_name'] as String,
                  unitsPerForm: (item['units_per_form'] as num?)?.toInt() ?? 1,
                  unitPriceCents: item['unit_price_cents'] as int,
                  quantity: item['quantity'] as int,
                  lineTotalCents: item['line_total_cents'] as int,
                ),
              )
              .toList(),
        ),
      );
    }
    return sales;
  }

  Future<List<Sale>> getPendingSales() async => _readSales(pendingOnly: true);

  Future<void> markSalesSynced(Iterable<String> transactionIds) async {
    final ids = transactionIds.toList();
    if (ids.isEmpty) return;
    final placeholders = List.filled(ids.length, '?').join(',');
    await db.rawUpdate(
      "UPDATE sales SET sync_status = 'synced' WHERE transaction_uuid IN ($placeholders)",
      ids,
    );
  }

  Future<List<Map<String, Object?>>> getPendingDebtPayments() async => db.query(
    'debt_payments',
    where: "sync_status != 'synced'",
    orderBy: 'created_at',
  );

  Future<List<CreditPaymentRecord>> getCreditPayments() async =>
      (await db.query(
        'debt_payments',
        orderBy: 'created_at DESC',
      )).map(CreditPaymentRecord.fromMap).toList();

  Future<void> markDebtPaymentsSynced(Iterable<String> paymentUuids) async {
    final ids = paymentUuids.toList();
    if (ids.isEmpty) return;
    final placeholders = List.filled(ids.length, '?').join(',');
    await db.rawUpdate(
      "UPDATE debt_payments SET sync_status = 'synced' "
      'WHERE payment_uuid IN ($placeholders)',
      ids,
    );
  }

  Future<void> upsertRemoteDebtPayments(
    List<Map<String, dynamic>> remotePayments,
  ) async {
    for (final remote in remotePayments) {
      final uuid = remote['payment_uuid']?.toString() ?? '';
      if (uuid.isEmpty) continue;
      await db.insert('debt_payments', {
        'payment_uuid': uuid,
        'customer_name': remote['customer_name']?.toString() ?? 'Customer',
        'customer_phone': remote['customer_phone']?.toString() ?? '',
        'customer_company': remote['customer_company']?.toString() ?? '',
        'amount_cents': (remote['amount_cents'] as num?)?.toInt() ?? 0,
        'cash_cents': (remote['cash_cents'] as num?)?.toInt() ?? 0,
        'mobile_money_cents':
            (remote['mobile_money_cents'] as num?)?.toInt() ?? 0,
        'payment_method': remote['payment_method']?.toString() ?? 'cash',
        'received_by': remote['received_by']?.toString() ?? 'Administrator',
        'payer_name': remote['payer_name'],
        'payer_phone': remote['payer_phone'],
        'balance_before_cents': remote['balance_before_cents'],
        'balance_after_cents': remote['balance_after_cents'],
        'note': remote['note']?.toString(),
        'created_at':
            remote['created_at']?.toString() ??
            DateTime.now().toUtc().toIso8601String(),
        'sync_status': 'synced',
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
    }
  }

  Future<void> upsertRemoteSales(
    List<Map<String, dynamic>> remoteSales, {
    bool applyStockChanges = false,
    bool notifySales = true,
  }) async {
    // An account switch must not redirect a running batch into another tenant.
    final destination = db;
    for (final remote in remoteSales) {
      final transactionId = remote['transaction_uuid']?.toString();
      if (transactionId == null || transactionId.isEmpty) continue;
      await destination.transaction((txn) async {
        final existing = await txn.query(
          'sales',
          columns: ['id', 'voided', 'receptionist_name'],
          where: 'transaction_uuid = ?',
          whereArgs: [transactionId],
          limit: 1,
        );
        if (existing.isNotEmpty) {
          final becameVoided =
              remote['voided'] == true &&
              (existing.first['voided'] as int? ?? 0) == 0;
          await txn.update(
            'sales',
            {
              'sync_status': 'synced',
              'voided': remote['voided'] == true ? 1 : 0,
              'void_reason': remote['void_reason']?.toString(),
              'customer_name': remote['customer_name']?.toString(),
              'customer_phone': remote['customer_phone']?.toString(),
              'customer_company': remote['customer_company']?.toString(),
              'collected_by': remote['collected_by']?.toString(),
              'collector_phone': remote['collector_phone']?.toString(),
              'previous_debt_cents':
                  (remote['previous_debt_cents'] as num?)?.toInt() ?? 0,
              'operator_label':
                  remote['operator_label']?.toString() ?? 'Operator',
              'debt_cents': (remote['debt_cents'] as num?)?.toInt() ?? 0,
              'debt_paid_cents':
                  (remote['debt_paid_cents'] as num?)?.toInt() ?? 0,
              'debt_due_at': remote['debt_due_at']?.toString(),
              'debt_note': remote['debt_note']?.toString(),
              'stock_override': remote['stock_override'] == true ? 1 : 0,
            },
            where: 'id = ?',
            whereArgs: [existing.first['id']],
          );
          if (becameVoided && applyStockChanges) {
            final deductedRows = await txn.rawQuery(
              "SELECT product_id, -SUM(quantity_base) AS quantity "
              "FROM stock_movements WHERE type = 'sale' AND reference_id = ? "
              'GROUP BY product_id',
              [transactionId],
            );
            for (final row in deductedRows) {
              await _insertStockMovement(
                txn,
                productId: row['product_id'] as int,
                type: 'sale_void',
                quantityBase: (row['quantity'] as num).toInt(),
                actorName: 'Administrator',
                note: remote['void_reason']?.toString(),
                referenceId: transactionId,
                createdAt: DateTime.now().toUtc(),
              );
            }
            await _resolveSaleDiscrepancies(
              txn,
              saleId: existing.first['id'] as int,
              resolvedBy: 'Administrator',
              reason: 'Sale voided',
            );
          }
          if (notifySales && remote['voided'] != true) {
            await _notifyRemoteSale(txn, remote, existing.first['id'] as int);
          }
          return;
        }
        // Numeric user IDs belong to the originating device, not this cache.
        // Resolve by the company-scoped username and keep historical operators
        // inactive until they authenticate with the server on this device.
        final operatorUsername = remote['receptionist_username']
            ?.toString()
            .trim()
            .toLowerCase();
        final localUsername =
            operatorUsername == null || operatorUsername.isEmpty
            ? 'remote-history-${remote['receptionist_id'] ?? transactionId}'
            : operatorUsername;
        final localOperators = await txn.query(
          'users',
          columns: ['id'],
          where: 'LOWER(username) = ?',
          whereArgs: [localUsername],
          limit: 1,
        );
        final localOperatorId = localOperators.isNotEmpty
            ? localOperators.first['id'] as int
            : await txn.insert('users', {
                'username': localUsername,
                'password_hash': 'remote-history-no-login',
                'display_name':
                    remote['receptionist_name']?.toString() ??
                    'Historical operator',
                'role': 'receptionist',
                'active': 0,
                'created_at': DateTime.now().toUtc().toIso8601String(),
              });
        final saleId = await txn.insert('sales', {
          'transaction_uuid': transactionId,
          'receipt_number': remote['receipt_number'].toString(),
          'receptionist_id': localOperatorId,
          'receptionist_username':
              remote['receptionist_username']?.toString() ?? 'unknown',
          'receptionist_name':
              remote['receptionist_name']?.toString() ?? 'Unknown receptionist',
          'customer_name': remote['customer_name']?.toString(),
          'customer_phone': remote['customer_phone']?.toString(),
          'customer_company': remote['customer_company']?.toString(),
          'collected_by': remote['collected_by']?.toString(),
          'collector_phone': remote['collector_phone']?.toString(),
          'previous_debt_cents':
              (remote['previous_debt_cents'] as num?)?.toInt() ?? 0,
          'operator_label': remote['operator_label']?.toString() ?? 'Operator',
          'device_id': remote['device_id']?.toString() ?? 'remote',
          'created_at': remote['created_at'].toString(),
          'total_cents': (remote['total_cents'] as num).toInt(),
          'payment_method': remote['payment_method']?.toString() ?? 'cash',
          'cash_cents':
              (remote['cash_cents'] as num?)?.toInt() ??
              (remote['total_cents'] as num).toInt(),
          'mobile_money_cents':
              (remote['mobile_money_cents'] as num?)?.toInt() ?? 0,
          'cash_tendered_cents':
              (remote['cash_tendered_cents'] as num?)?.toInt() ??
              (remote['cash_cents'] as num?)?.toInt() ??
              0,
          'change_given_cents':
              (remote['change_given_cents'] as num?)?.toInt() ?? 0,
          'debt_cents': (remote['debt_cents'] as num?)?.toInt() ?? 0,
          'debt_paid_cents': (remote['debt_paid_cents'] as num?)?.toInt() ?? 0,
          'debt_due_at': remote['debt_due_at']?.toString(),
          'debt_note': remote['debt_note']?.toString(),
          'sync_status': 'synced',
          'voided': remote['voided'] == true ? 1 : 0,
          'void_reason': remote['void_reason']?.toString(),
          'stock_override': remote['stock_override'] == true ? 1 : 0,
        });
        final items = remote['items'] as List<dynamic>? ?? const [];
        final requiredByProduct = <int, int>{};
        for (final value in items) {
          final item = value as Map<String, dynamic>;
          final productCode = item['product_code']?.toString().trim() ?? '';
          List<Map<String, Object?>> localProducts = const [];
          if (productCode.isNotEmpty) {
            localProducts = await txn.query(
              'products',
              columns: ['id'],
              where: 'code = ?',
              whereArgs: [productCode.toUpperCase()],
              limit: 1,
            );
          }
          if (localProducts.isEmpty) {
            final remoteProductId = (item['product_id'] as num?)?.toInt() ?? 0;
            localProducts = await txn.query(
              'products',
              columns: ['id'],
              where: 'id = ?',
              whereArgs: [remoteProductId],
              limit: 1,
            );
          }
          final localProductId = localProducts.isEmpty
              ? 0
              : localProducts.first['id'] as int;
          final unitsPerForm = (item['units_per_form'] as num?)?.toInt() ?? 1;
          final quantity = (item['quantity'] as num).toInt();
          await txn.insert('sale_items', {
            'sale_id': saleId,
            'product_id': localProductId,
            'product_code': productCode,
            'product_name': item['product_name'].toString(),
            'form_name': item['selling_form'].toString(),
            'units_per_form': unitsPerForm,
            'unit_price_cents': (item['unit_price_cents'] as num).toInt(),
            'quantity': quantity,
            'line_total_cents': (item['line_total_cents'] as num).toInt(),
          });
          if (localProductId > 0) {
            requiredByProduct.update(
              localProductId,
              (current) => current + quantity * unitsPerForm,
              ifAbsent: () => quantity * unitsPerForm,
            );
          }
        }
        final createdAt =
            DateTime.tryParse(remote['created_at']?.toString() ?? '')
                ?.toUtc() ??
            DateTime.now().toUtc();
        if (remote['voided'] != true && applyStockChanges) {
          for (final entry in requiredByProduct.entries) {
            final before = max(0, await _stockForProduct(txn, entry.key));
            final deducted = min(before, entry.value);
            final discrepancy = entry.value - deducted;
            final after = before - deducted;
            if (deducted > 0) {
              await _insertStockMovement(
                txn,
                productId: entry.key,
                type: 'sale',
                quantityBase: -deducted,
                actorName:
                    remote['receptionist_name']?.toString() ?? 'Receptionist',
                note: discrepancy > 0
                    ? 'Remote sale; unavailable amount recorded separately'
                    : 'Remote sale ${remote['receipt_number']}',
                referenceId: transactionId,
                createdAt: createdAt,
              );
            }
            final product = await txn.query(
              'products',
              columns: ['name', 'base_unit', 'low_stock_threshold'],
              where: 'id = ?',
              whereArgs: [entry.key],
              limit: 1,
            );
            if (product.isEmpty) continue;
            final threshold =
                (product.first['low_stock_threshold'] as num?)?.toInt() ?? 0;
            if (discrepancy > 0) {
              await txn.insert('stock_discrepancies', {
                'product_id': entry.key,
                'sale_id': saleId,
                'quantity_base': discrepancy,
                'created_at': createdAt.toIso8601String(),
                'created_by':
                    remote['receptionist_name']?.toString() ?? 'Receptionist',
              });
              await _insertNotification(
                txn,
                type: 'stock_discrepancy',
                title: 'Stock count needs attention',
                message:
                    '${product.first['name']} has an unresolved discrepancy of '
                    '$discrepancy ${product.first['base_unit']}. Newly received '
                    'stock will not be deducted.',
                productId: entry.key,
                saleId: saleId,
                referenceId: 'stock-override-$transactionId-${entry.key}',
                createdAt: createdAt,
              );
            } else if (threshold > 0 &&
                before > threshold &&
                after <= threshold &&
                await _preferenceEnabled(
                  txn,
                  'notify_low_stock',
                  defaultValue: true,
                )) {
              await _insertNotification(
                txn,
                type: 'low_stock',
                title: 'Low Stock Alert',
                message:
                    '${product.first['name']} is below your stock limit. '
                    'Only $after ${product.first['base_unit']} remaining.',
                productId: entry.key,
                saleId: saleId,
                referenceId: 'low-stock-$transactionId-${entry.key}',
                createdAt: createdAt,
              );
            }
          }
        }
        if (notifySales &&
            remote['voided'] != true &&
            await _preferenceEnabled(txn, 'notify_every_sale')) {
          await _insertNotification(
            txn,
            type: 'sale',
            title: 'New Sale Recorded',
            message:
                '${items.fold<int>(0, (count, item) => count + ((item as Map)['quantity'] as num).toInt())} items sold. '
                'Total: GHS ${money((remote['total_cents'] as num).toInt())}\n'
                'Recorded by ${remote['receptionist_name'] ?? 'Receptionist'} · ${remote['receipt_number']}',
            saleId: saleId,
            referenceId: 'sale-$transactionId',
            createdAt: createdAt,
          );
        }
      });
    }
  }

  // A live event can arrive after a history sync already imported its receipt.
  // Reference IDs make the alert idempotent regardless of arrival order.
  Future<void> _notifyRemoteSale(
    DatabaseExecutor executor,
    Map<String, dynamic> remote,
    int saleId,
  ) async {
    if (!await _preferenceEnabled(executor, 'notify_every_sale')) return;
    final items = remote['items'] as List<dynamic>? ?? const [];
    final count = items.fold<int>(
      0,
      (sum, item) => sum + ((item as Map)['quantity'] as num).toInt(),
    );
    await _insertNotification(
      executor,
      type: 'sale',
      title: 'New Sale Recorded',
      message:
          '$count items sold. Total: GHS ${money((remote['total_cents'] as num).toInt())}\n'
          'Recorded by ${remote['receptionist_name'] ?? 'Receptionist'} · ${remote['receipt_number']}',
      saleId: saleId,
      referenceId: 'sale-${remote['transaction_uuid']}',
      createdAt:
          DateTime.tryParse(remote['created_at']?.toString() ?? '') ??
          DateTime.now(),
    );
  }

  Future<void> upsertRemoteProducts(
    List<Map<String, dynamic>> remoteProducts, {
    Set<String> preserveCodes = const {},
  }) async {
    for (final remote in remoteProducts) {
      final code = remote['code']?.toString().trim().toUpperCase();
      if (code == null || code.isEmpty) continue;
      if (preserveCodes.contains(code)) continue;
      await db.transaction((txn) async {
        final existing = await txn.query(
          'products',
          columns: ['id'],
          where: 'code = ?',
          whereArgs: [code],
          limit: 1,
        );
        final values = {
          'name': remote['name'].toString(),
          'code': code,
          'category': remote['category'].toString(),
          'base_unit': remote['base_unit']?.toString() ?? 'unit',
          'low_stock_threshold':
              (remote['low_stock_threshold'] as num?)?.toInt() ?? 0,
          'image_bytes': _decodeProductImage(remote['image_base64']),
          'active': remote['active'] == false ? 0 : 1,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        };
        final productId = existing.isEmpty
            ? await txn.insert('products', values)
            : existing.first['id'] as int;
        if (existing.isNotEmpty) {
          await txn.update(
            'products',
            values,
            where: 'id = ?',
            whereArgs: [productId],
          );
        }
        final forms = remote['forms'] as List<dynamic>? ?? const [];
        for (final value in forms) {
          final form = value as Map<String, dynamic>;
          await txn.insert('selling_forms', {
            'product_id': productId,
            'name': form['name'].toString(),
            'price_cents': (form['price_cents'] as num).toInt(),
            'units_per_form': (form['units_per_form'] as num?)?.toInt() ?? 1,
            'active': form['active'] == false ? 0 : 1,
            'updated_at': DateTime.now().toUtc().toIso8601String(),
          }, conflictAlgorithm: ConflictAlgorithm.replace);
        }
        final movementCountRows = await txn.rawQuery(
          'SELECT COUNT(*) AS count FROM stock_movements WHERE product_id = ?',
          [productId],
        );
        final movementCount =
            (movementCountRows.first['count'] as num?)?.toInt() ?? 0;
        final remoteStock = (remote['current_stock'] as num?)?.toInt() ?? 0;
        if (movementCount == 0 && remoteStock > 0) {
          await txn.insert('stock_movements', {
            'movement_uuid': 'remote-stock-snapshot-$code',
            'product_id': productId,
            'type': 'sync_snapshot',
            'quantity_base': remoteStock,
            'actor_name': 'Saleo cloud',
            'note': 'Restored stock balance from the company cloud',
            'reference_id': 'remote-stock-snapshot-$code',
            'created_at': DateTime.now().toUtc().toIso8601String(),
          }, conflictAlgorithm: ConflictAlgorithm.ignore);
        }
      });
    }
  }

  Future<void> upsertRemoteStockMovements(
    List<Map<String, dynamic>> remoteMovements,
  ) async {
    await db.transaction((txn) async {
      for (final remote in remoteMovements) {
        final movementUuid = remote['movement_uuid']?.toString().trim() ?? '';
        final productCode =
            remote['product_code']?.toString().trim().toUpperCase() ?? '';
        if (movementUuid.isEmpty || productCode.isEmpty) continue;
        final products = await txn.query(
          'products',
          columns: ['id'],
          where: 'code = ?',
          whereArgs: [productCode],
          limit: 1,
        );
        if (products.isEmpty) continue;
        await txn.insert('stock_movements', {
          'movement_uuid': movementUuid,
          'product_id': products.first['id'] as int,
          'type': remote['type']?.toString() ?? 'sync',
          'quantity_base': (remote['quantity_base'] as num?)?.toInt() ?? 0,
          'actor_name': remote['actor_name']?.toString() ?? 'Saleo cloud',
          'note': remote['note']?.toString(),
          'reference_id': remote['reference_id']?.toString(),
          'created_at':
              remote['created_at']?.toString() ??
              DateTime.now().toUtc().toIso8601String(),
        }, conflictAlgorithm: ConflictAlgorithm.ignore);
      }
    });
  }

  Future<List<StockShortage>> getStockShortages(List<CartLine> cart) async {
    final requiredByProduct = <int, int>{};
    final productsById = <int, Product>{};
    for (final line in cart) {
      productsById[line.product.id] = line.product;
      requiredByProduct.update(
        line.product.id,
        (value) => value + line.quantity * line.form.unitsPerForm,
        ifAbsent: () => line.quantity * line.form.unitsPerForm,
      );
    }
    final shortages = <StockShortage>[];
    for (final entry in requiredByProduct.entries) {
      final available = await _stockForProduct(db, entry.key);
      if (entry.value > available) {
        shortages.add(
          StockShortage(
            product: productsById[entry.key]!,
            availableBase: available,
            requiredBase: entry.value,
          ),
        );
      }
    }
    return shortages;
  }

  Future<void> addStockMovement({
    required int productId,
    required String type,
    required int quantityBase,
    required String actorName,
    String? note,
  }) async {
    if (quantityBase == 0) return;
    await db.transaction((txn) async {
      final before = await _stockForProduct(txn, productId);
      final now = DateTime.now().toUtc();
      await _insertStockMovement(
        txn,
        productId: productId,
        type: type,
        quantityBase: quantityBase,
        actorName: actorName,
        note: note,
        createdAt: now,
      );
      final after = before + quantityBase;
      if (quantityBase < 0) {
        final rows = await txn.query(
          'products',
          columns: ['name', 'base_unit', 'low_stock_threshold'],
          where: 'id = ?',
          whereArgs: [productId],
          limit: 1,
        );
        if (rows.isNotEmpty) {
          final threshold =
              (rows.first['low_stock_threshold'] as num?)?.toInt() ?? 0;
          if (threshold > 0 &&
              before > threshold &&
              after <= threshold &&
              await _preferenceEnabled(
                txn,
                'notify_low_stock',
                defaultValue: true,
              )) {
            await _insertNotification(
              txn,
              type: 'low_stock',
              title: 'Low Stock Alert',
              message:
                  '${rows.first['name']} is below your stock limit. '
                  'Only $after ${rows.first['base_unit']} remaining.',
              productId: productId,
              referenceId: 'low-stock-${now.microsecondsSinceEpoch}-$productId',
              createdAt: now,
            );
          }
        }
      }
    });
  }

  Future<void> updateInventoryConfiguration({
    required int productId,
    required String baseUnit,
    required int lowStockThreshold,
  }) => db.update(
    'products',
    {
      'base_unit': baseUnit.trim().toLowerCase(),
      'low_stock_threshold': lowStockThreshold,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    },
    where: 'id = ?',
    whereArgs: [productId],
  );

  Future<List<StockMovement>> getStockMovements({int limit = 5000}) async {
    final rows = await db.query(
      'stock_movements',
      orderBy: 'created_at DESC, id DESC',
      limit: limit,
    );
    return rows.map(StockMovement.fromMap).toList();
  }

  Future<List<CustomerRecord>> getCustomers() async {
    final rows = await db.query(
      'customers',
      orderBy: 'last_purchase_at DESC, name COLLATE NOCASE',
    );
    return rows.map(CustomerRecord.fromMap).toList();
  }

  Future<int> _outstandingDebtForPhone(
    DatabaseExecutor executor,
    String phoneKey,
  ) async {
    if (phoneKey.isEmpty) return 0;
    final debtRows = await executor.query(
      'sales',
      columns: ['customer_phone', 'debt_cents', 'debt_paid_cents'],
      where: 'voided = 0 AND debt_cents > 0',
    );
    var debt = 0;
    for (final row in debtRows) {
      if (_phoneKey(row['customer_phone']?.toString() ?? '') == phoneKey) {
        debt += (row['debt_cents'] as num?)?.toInt() ?? 0;
        debt -= (row['debt_paid_cents'] as num?)?.toInt() ?? 0;
      }
    }
    final paymentRows = await executor.query(
      'debt_payments',
      columns: ['customer_phone', 'amount_cents'],
    );
    for (final row in paymentRows) {
      if (_phoneKey(row['customer_phone']?.toString() ?? '') == phoneKey) {
        debt -= (row['amount_cents'] as num?)?.toInt() ?? 0;
      }
    }
    return debt < 0 ? 0 : debt;
  }

  Future<int> outstandingDebtForCustomer(CustomerRecord customer) =>
      _outstandingDebtForPhone(db, _phoneKey(customer.phone));

  Future<List<DebtorSummary>> getDebtorSummaries() async {
    final debtSales = await db.query(
      'sales',
      where: 'voided = 0 AND debt_cents > 0 AND customer_phone IS NOT NULL',
      orderBy: 'created_at',
    );
    final payments = await db.query('debt_payments', orderBy: 'created_at');
    final summaries = <String, _MutableDebtSummary>{};
    for (final row in debtSales) {
      final phone = row['customer_phone']?.toString() ?? '';
      final key = _phoneKey(phone);
      if (key.isEmpty) continue;
      final summary = summaries.putIfAbsent(
        key,
        () => _MutableDebtSummary(
          customerName: row['customer_name']?.toString() ?? phone,
          customerPhone: phone,
          companyName: row['customer_company']?.toString() ?? '',
        ),
      );
      summary.customerName =
          row['customer_name']?.toString() ?? summary.customerName;
      summary.companyName =
          row['customer_company']?.toString() ?? summary.companyName;
      summary.totalDebtCents += (row['debt_cents'] as num?)?.toInt() ?? 0;
      summary.paidCents += (row['debt_paid_cents'] as num?)?.toInt() ?? 0;
      summary.saleCount++;
      final createdAt = DateTime.tryParse(row['created_at']?.toString() ?? '');
      if (createdAt != null &&
          (summary.latestSaleAt == null ||
              createdAt.isAfter(summary.latestSaleAt!))) {
        summary.latestSaleAt = createdAt;
      }
      final dueAt = DateTime.tryParse(row['debt_due_at']?.toString() ?? '');
      if (dueAt != null &&
          (summary.nextDueAt == null || dueAt.isBefore(summary.nextDueAt!))) {
        summary.nextDueAt = dueAt;
      }
    }
    for (final row in payments) {
      final key = _phoneKey(row['customer_phone']?.toString() ?? '');
      final summary = summaries[key];
      if (summary != null) {
        summary.paidCents += (row['amount_cents'] as num?)?.toInt() ?? 0;
      }
    }
    final result = summaries.values
        .map(
          (item) => DebtorSummary(
            customerName: item.customerName,
            customerPhone: item.customerPhone,
            companyName: item.companyName,
            totalDebtCents: item.totalDebtCents,
            paidCents: item.paidCents,
            outstandingCents: (item.totalDebtCents - item.paidCents).clamp(
              0,
              1 << 62,
            ),
            saleCount: item.saleCount,
            latestSaleAt: item.latestSaleAt,
            nextDueAt: item.nextDueAt,
          ),
        )
        .toList();
    result.sort((a, b) => b.outstandingCents.compareTo(a.outstandingCents));
    return result;
  }

  Future<DebtLedgerEntry> recordDebtPayment({
    required DebtorSummary debtor,
    required int amountCents,
    required int cashCents,
    required int mobileMoneyCents,
    required String receivedBy,
    required String payerName,
    required String payerPhone,
    String? note,
  }) async {
    if (payerName.trim().isEmpty || payerPhone.trim().length < 3) {
      throw StateError('Enter the payer’s name and phone number.');
    }
    if (amountCents <= 0 || amountCents > debtor.outstandingCents) {
      throw StateError('Enter a payment up to the outstanding balance.');
    }
    if (cashCents + mobileMoneyCents != amountCents) {
      throw StateError('Cash and MOMO must equal the payment amount.');
    }
    final method = cashCents > 0 && mobileMoneyCents > 0
        ? 'cash_momo'
        : mobileMoneyCents > 0
        ? 'momo'
        : 'cash';
    final uuid = _uuid.v4();
    final created = DateTime.now().toUtc();
    await db.insert('debt_payments', {
      'payment_uuid': uuid,
      'customer_name': debtor.customerName,
      'customer_phone': debtor.customerPhone,
      'customer_company': debtor.companyName,
      'amount_cents': amountCents,
      'cash_cents': cashCents,
      'mobile_money_cents': mobileMoneyCents,
      'payment_method': method,
      'received_by': receivedBy,
      'payer_name': payerName.trim(),
      'payer_phone': payerPhone.trim(),
      'balance_before_cents': debtor.outstandingCents,
      'balance_after_cents': debtor.outstandingCents - amountCents,
      'note': note?.trim().isEmpty ?? true ? null : note!.trim(),
      'created_at': created.toIso8601String(),
      'sync_status': 'pending',
    });
    return DebtLedgerEntry(
      id: uuid,
      entryType: 'payment',
      customerName: debtor.customerName,
      customerPhone: debtor.customerPhone,
      companyName: debtor.companyName,
      amountCents: amountCents,
      balanceBeforeCents: debtor.outstandingCents,
      balanceAfterCents: debtor.outstandingCents - amountCents,
      createdAt: created,
      recordedBy: receivedBy,
      payerName: payerName.trim(),
      payerPhone: payerPhone.trim(),
      paymentMethod: method,
      note: note,
    );
  }

  Future<List<DebtLedgerEntry>> getDebtLedger(DebtorSummary debtor) async {
    final key = _phoneKey(debtor.customerPhone);
    final sales = (await getSales())
        .where(
          (sale) =>
              !sale.voided &&
              sale.debtCents > 0 &&
              _phoneKey(sale.customerPhone ?? '') == key,
        )
        .toList();
    final paymentRows = await db.query('debt_payments', orderBy: 'created_at');
    final raw = <({DateTime date, bool payment, Object value})>[
      ...sales.map(
        (sale) => (date: sale.createdAt, payment: false, value: sale),
      ),
      ...paymentRows
          .where(
            (row) => _phoneKey(row['customer_phone']?.toString() ?? '') == key,
          )
          .map(
            (row) => (
              date: DateTime.parse(row['created_at'] as String),
              payment: true,
              value: row,
            ),
          ),
    ]..sort((a, b) => a.date.compareTo(b.date));
    var balance = 0;
    final entries = <DebtLedgerEntry>[];
    for (final item in raw) {
      if (item.payment) {
        final row = item.value as Map<String, Object?>;
        final amount = (row['amount_cents'] as num).toInt();
        final before =
            (row['balance_before_cents'] as num?)?.toInt() ?? balance;
        balance =
            (row['balance_after_cents'] as num?)?.toInt() ??
            (before - amount).clamp(0, 1 << 62);
        entries.add(
          DebtLedgerEntry(
            id: row['payment_uuid'] as String,
            entryType: 'payment',
            balanceBeforeCents: before,
            recordedBy: row['received_by'] as String?,
            payerName: row['payer_name'] as String?,
            payerPhone: row['payer_phone'] as String?,
            customerName: row['customer_name'] as String,
            customerPhone: row['customer_phone'] as String,
            companyName: row['customer_company'] as String? ?? '',
            amountCents: amount,
            balanceAfterCents: balance,
            createdAt: item.date,
            paymentMethod: row['payment_method'] as String,
            note: row['note'] as String?,
          ),
        );
      } else {
        final sale = item.value as Sale;
        // A ledger records the original credit, not its remaining amount today.
        // A saved opening balance also preserves context when older receipts
        // have not yet been downloaded to this device.
        final before = sale.previousDebtCents > 0
            ? sale.previousDebtCents
            : balance;
        balance = before + sale.debtCents;
        entries.add(
          DebtLedgerEntry(
            id: sale.transactionUuid,
            entryType: 'sale',
            balanceBeforeCents: before,
            purchaseTotalCents: sale.totalCents,
            paidAtPurchaseCents: sale.cashCents + sale.mobileMoneyCents,
            recordedBy: sale.receptionistName,
            customerName: sale.customerName ?? debtor.customerName,
            customerPhone: sale.customerPhone ?? debtor.customerPhone,
            companyName: sale.customerCompany ?? debtor.companyName,
            amountCents: sale.debtCents,
            balanceAfterCents: balance,
            createdAt: sale.createdAt,
            saleId: sale.id,
            receiptNumber: sale.receiptNumber,
            paymentMethod: sale.paymentMethod,
            collectedBy: sale.collectedBy,
            collectorPhone: sale.collectorPhone,
            note: sale.debtNote,
            items: sale.items,
          ),
        );
      }
    }
    return entries.reversed.toList();
  }

  Future<void> upsertRemoteCustomers(
    List<Map<String, dynamic>> remoteCustomers, {
    Set<String> preservePhones = const {},
  }) async {
    final fallback = DateTime.now().toUtc().toIso8601String();
    await db.transaction((txn) async {
      for (final remote in remoteCustomers) {
        final phone = remote['phone']?.toString().trim() ?? '';
        if (phone.isEmpty) continue;
        if (preservePhones.any(
          (value) => _phoneKey(value) == _phoneKey(phone),
        )) {
          continue;
        }
        final phoneKey = _phoneKey(phone);
        final existing = await txn.query(
          'customers',
          columns: ['id'],
          where: 'phone_key = ?',
          whereArgs: [phoneKey],
          limit: 1,
        );
        final values = <String, Object?>{
          'name': remote['name']?.toString().trim().isNotEmpty == true
              ? remote['name'].toString().trim()
              : phone,
          'phone': phone,
          'phone_key': phoneKey,
          'company_name': remote['company_name']?.toString().trim() ?? '',
          'address': remote['address']?.toString().trim() ?? '',
          'created_at': remote['created_at']?.toString() ?? fallback,
          'updated_at': remote['updated_at']?.toString() ?? fallback,
          'last_purchase_at': remote['last_purchase_at']?.toString(),
          'purchase_count': (remote['purchase_count'] as num?)?.toInt() ?? 0,
          'total_spent_cents':
              (remote['total_spent_cents'] as num?)?.toInt() ?? 0,
        };
        if (existing.isEmpty) {
          await txn.insert('customers', values);
        } else {
          await txn.update(
            'customers',
            values,
            where: 'id = ?',
            whereArgs: [existing.first['id']],
          );
        }
      }
    });
  }

  Future<void> updateCustomer(
    CustomerRecord customer, {
    required String name,
    required String phone,
    required String companyName,
    required String address,
  }) async {
    final cleanPhone = phone.trim();
    if (cleanPhone.isEmpty) throw StateError('Enter a phone number.');
    await db.update(
      'customers',
      {
        'name': name.trim().isEmpty ? cleanPhone : name.trim(),
        'phone': cleanPhone,
        'phone_key': _phoneKey(cleanPhone),
        'company_name': companyName.trim(),
        'address': address.trim(),
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [customer.id],
    );
  }

  Future<void> deleteCustomer(int id) =>
      db.delete('customers', where: 'id = ?', whereArgs: [id]);

  Future<List<StockDiscrepancy>> getStockDiscrepancies() async {
    final rows = await db.query(
      'stock_discrepancies',
      orderBy: 'resolved_at IS NOT NULL, created_at DESC',
    );
    return rows.map(StockDiscrepancy.fromMap).toList();
  }

  Future<void> resolveStockDiscrepancy({
    required int id,
    required String resolvedBy,
    required String reason,
  }) async {
    final now = DateTime.now().toUtc().toIso8601String();
    final rows = await db.query(
      'stock_discrepancies',
      columns: ['product_id'],
      where: 'id = ? AND resolved_at IS NULL',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return;
    await db.transaction((txn) async {
      await txn.update(
        'stock_discrepancies',
        {
          'resolved_at': now,
          'resolved_by': resolvedBy,
          'resolution_reason': reason.trim().isEmpty
              ? 'Reviewed and cleared'
              : reason.trim(),
        },
        where: 'id = ?',
        whereArgs: [id],
      );
      await txn.update(
        'app_notifications',
        {'resolved_at': now, 'is_read': 1},
        where: "type = 'stock_discrepancy' AND product_id = ? AND resolved_at IS NULL",
        whereArgs: [rows.first['product_id']],
      );
    });
  }

  Future<int> createStockReceipt({
    required List<StockReceiptDraftItem> items,
    required String createdBy,
    String? supplierName,
    String? invoiceNumber,
    bool confirm = true,
  }) async {
    if (items.isEmpty) throw StateError('Add at least one product.');
    final invoice = invoiceNumber?.trim() ?? '';
    if (invoice.isNotEmpty) {
      final duplicate = await db.query(
        'stock_receipts',
        columns: ['id'],
        where: "LOWER(invoice_number) = ? AND status != 'reversed'",
        whereArgs: [invoice.toLowerCase()],
        limit: 1,
      );
      if (duplicate.isNotEmpty) {
        throw StateError('This invoice number has already been received.');
      }
    }
    final uuid = _uuid.v4();
    final now = DateTime.now().toUtc();
    return db.transaction((txn) async {
      final receiptId = await txn.insert('stock_receipts', {
        'receipt_uuid': uuid,
        'status': confirm ? 'confirmed' : 'draft',
        'supplier_name': supplierName?.trim().isEmpty ?? true
            ? null
            : supplierName!.trim(),
        'invoice_number': invoice.isEmpty ? null : invoice,
        'created_at': now.toIso8601String(),
        'confirmed_at': confirm ? now.toIso8601String() : null,
        'created_by': createdBy,
      });
      for (final item in items) {
        final receiptItemId = await txn.insert('stock_receipt_items', {
          'receipt_id': receiptId,
          'product_id': item.product.id,
          'product_name': item.product.name,
          'form_name': item.form.name,
          'quantity_forms': item.quantityForms,
          'units_per_form': item.form.unitsPerForm,
          'quantity_base': item.quantityBase,
          'purchase_cost_cents': item.purchaseCostCents,
          'batch_number': item.batchNumber?.trim().isEmpty ?? true
              ? null
              : item.batchNumber!.trim(),
          'expiry_date': item.expiryDate?.toIso8601String(),
        });
        if (confirm) {
          await _insertStockMovement(
            txn,
            productId: item.product.id,
            type: 'restock',
            quantityBase: item.quantityBase,
            actorName: createdBy,
            note: invoice.isEmpty
                ? 'Received stock'
                : 'Received stock • Invoice $invoice',
            referenceId: '$uuid-$receiptItemId',
            createdAt: now,
          );
          await _resolveLowStockIfRecovered(txn, item.product.id, now);
        }
      }
      return receiptId;
    });
  }

  Future<void> confirmStockReceipt(int receiptId, String confirmedBy) async {
    await db.transaction((txn) async {
      final receipts = await txn.query(
        'stock_receipts',
        where: "id = ? AND status = 'draft'",
        whereArgs: [receiptId],
        limit: 1,
      );
      if (receipts.isEmpty) {
        throw StateError('This draft is no longer available.');
      }
      final receipt = receipts.first;
      final items = await txn.query(
        'stock_receipt_items',
        where: 'receipt_id = ?',
        whereArgs: [receiptId],
      );
      final now = DateTime.now().toUtc();
      for (final row in items) {
        final productId = row['product_id'] as int;
        await _insertStockMovement(
          txn,
          productId: productId,
          type: 'restock',
          quantityBase: (row['quantity_base'] as num).toInt(),
          actorName: confirmedBy,
          note: 'Confirmed received-stock draft',
          referenceId: '${receipt['receipt_uuid']}-${row['id']}',
          createdAt: now,
        );
        await _resolveLowStockIfRecovered(txn, productId, now);
      }
      await txn.update(
        'stock_receipts',
        {'status': 'confirmed', 'confirmed_at': now.toIso8601String()},
        where: 'id = ?',
        whereArgs: [receiptId],
      );
    });
  }

  Future<void> reverseStockReceipt(
    int receiptId,
    String reason, {
    required String actorName,
  }) async {
    await db.transaction((txn) async {
      final receipts = await txn.query(
        'stock_receipts',
        where: "id = ? AND status = 'confirmed'",
        whereArgs: [receiptId],
        limit: 1,
      );
      if (receipts.isEmpty) {
        throw StateError('Only confirmed stock can be reversed.');
      }
      final receipt = receipts.first;
      final items = await txn.query(
        'stock_receipt_items',
        where: 'receipt_id = ?',
        whereArgs: [receiptId],
      );
      final requiredByProduct = <int, int>{};
      for (final row in items) {
        final productId = row['product_id'] as int;
        final quantity = (row['quantity_base'] as num).toInt();
        requiredByProduct.update(
          productId,
          (current) => current + quantity,
          ifAbsent: () => quantity,
        );
      }
      for (final entry in requiredByProduct.entries) {
        final available = await _stockForProduct(txn, entry.key);
        if (available < entry.value) {
          throw StateError(
            'This receipt cannot be reversed because some of its stock has already been sold.',
          );
        }
      }
      final now = DateTime.now().toUtc();
      for (final row in items) {
        await _insertStockMovement(
          txn,
          productId: row['product_id'] as int,
          type: 'receipt_reversal',
          quantityBase: -((row['quantity_base'] as num).toInt()),
          actorName: actorName,
          note: reason.trim(),
          referenceId: '${receipt['receipt_uuid']}-reverse-${row['id']}',
          createdAt: now,
        );
      }
      await txn.update(
        'stock_receipts',
        {
          'status': 'reversed',
          'reversed_at': now.toIso8601String(),
          'reversal_reason': reason.trim(),
        },
        where: 'id = ?',
        whereArgs: [receiptId],
      );
    });
  }

  Future<List<StockReceipt>> getStockReceipts() async {
    final rows = await db.query(
      'stock_receipts',
      orderBy: 'COALESCE(confirmed_at, created_at) DESC, id DESC',
    );
    final receipts = <StockReceipt>[];
    for (final row in rows) {
      final itemRows = await db.query(
        'stock_receipt_items',
        where: 'receipt_id = ?',
        whereArgs: [row['id']],
        orderBy: 'id',
      );
      receipts.add(
        StockReceipt(
          id: row['id'] as int,
          receiptUuid: row['receipt_uuid'] as String,
          status: StockReceiptStatus.values.firstWhere(
            (value) => value.name == row['status'],
            orElse: () => StockReceiptStatus.draft,
          ),
          supplierName: row['supplier_name'] as String?,
          invoiceNumber: row['invoice_number'] as String?,
          createdAt: DateTime.parse(row['created_at'] as String),
          confirmedAt: row['confirmed_at'] == null
              ? null
              : DateTime.parse(row['confirmed_at'] as String),
          createdBy: row['created_by'] as String,
          reversedAt: row['reversed_at'] == null
              ? null
              : DateTime.parse(row['reversed_at'] as String),
          reversalReason: row['reversal_reason'] as String?,
          items: itemRows.map(StockReceiptItem.fromMap).toList(),
        ),
      );
    }
    return receipts;
  }

  Future<void> setPhysicalStock({
    required int productId,
    required int countedQuantity,
    required String actorName,
    String? note,
  }) async {
    if (countedQuantity < 0) {
      throw StateError('Stock count cannot be negative.');
    }
    await db.transaction((txn) async {
      final current = await _stockForProduct(txn, productId);
      final difference = countedQuantity - current;
      if (difference == 0) return;
      final now = DateTime.now().toUtc();
      await _insertStockMovement(
        txn,
        productId: productId,
        type: difference > 0 ? 'correction_add' : 'correction_remove',
        quantityBase: difference,
        actorName: actorName,
        note: note?.trim().isEmpty ?? true
            ? 'Physical stock count'
            : note!.trim(),
        createdAt: now,
      );
      if (difference > 0) {
        await _resolveLowStockIfRecovered(txn, productId, now);
      }
    });
  }

  Future<InventoryPreferences> getInventoryPreferences() async {
    final values = <String, String>{};
    final rows = await db.query(
      'app_meta',
      where: 'key IN (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
      whereArgs: [
        'notify_every_sale',
        'notify_low_stock',
        'notify_expiry',
        'notify_debt_due',
        'expiry_reminder_days',
        'show_external_notifications',
        'inventory_period',
        'inventory_week_start',
        'inventory_view',
        'app_theme',
        'app_navigation',
        'app_accent',
        'app_custom_accent',
        'app_show_product_images',
        'app_text_scale',
        'collect_customer_details',
        'staff_can_receive_stock',
      ],
    );
    for (final row in rows) {
      values[row['key'] as String] = row['value'] as String;
    }
    final periodName = values['inventory_period'];
    final period = InventoryPeriod.values.firstWhere(
      (value) => value.name == periodName,
      orElse: () => InventoryPeriod.daily,
    );
    final weekStart =
        int.tryParse(values['inventory_week_start'] ?? '') ?? DateTime.monday;
    T enumValue<T extends Enum>(List<T> options, String? name, T fallback) =>
        options.where((value) => value.name == name).firstOrNull ?? fallback;
    return InventoryPreferences(
      notifyEverySale: values['notify_every_sale'] == '1',
      notifyLowStock: values['notify_low_stock'] != '0',
      notifyExpiry: values['notify_expiry'] != '0',
      notifyDebtDue: values['notify_debt_due'] != '0',
      expiryReminderDays:
          int.tryParse(values['expiry_reminder_days'] ?? '') ?? 30,
      showExternalNotifications: values['show_external_notifications'] == '1',
      defaultPeriod: period,
      weekStartsOn: weekStart == DateTime.sunday
          ? DateTime.sunday
          : DateTime.monday,
      inventoryView: enumValue(
        InventoryViewMode.values,
        values['inventory_view'],
        InventoryViewMode.cards,
      ),
      // Migrate legacy system/colour presets into the two supported modes.
      theme:
          values['app_theme'] == 'dark' ||
              values['app_accent'] == 'classicBlack'
          ? AppThemePreference.dark
          : AppThemePreference.light,
      navigation: enumValue(
        AppNavigationPreference.values,
        values['app_navigation'],
        AppNavigationPreference.automatic,
      ),
      accent: enumValue(
        AppAccentPreference.values,
        values['app_accent'],
        AppAccentPreference.blue,
      ),
      showProductImages: values['app_show_product_images'] != '0',
      textScale: (double.tryParse(values['app_text_scale'] ?? '') ?? 1.0).clamp(
        0.9,
        1.2,
      ),
      collectCustomerDetails: values['collect_customer_details'] == '1',
      customAccentArgb:
          int.tryParse(values['app_custom_accent'] ?? '') ?? 0xFF0B72E7,
      staffCanReceiveStock: values['staff_can_receive_stock'] == '1',
    );
  }

  Future<void> saveInventoryPreferences(InventoryPreferences value) async {
    final entries = {
      'notify_every_sale': value.notifyEverySale ? '1' : '0',
      'notify_low_stock': value.notifyLowStock ? '1' : '0',
      'notify_expiry': value.notifyExpiry ? '1' : '0',
      'notify_debt_due': value.notifyDebtDue ? '1' : '0',
      'expiry_reminder_days': '${value.expiryReminderDays}',
      'show_external_notifications': value.showExternalNotifications
          ? '1'
          : '0',
      'inventory_period': value.defaultPeriod.name,
      'inventory_week_start': '${value.weekStartsOn}',
      'inventory_view': value.inventoryView.name,
      'app_theme': value.theme.name,
      'app_navigation': value.navigation.name,
      'app_accent': value.accent.name,
      'app_custom_accent': '${value.customAccentArgb}',
      'app_show_product_images': value.showProductImages ? '1' : '0',
      'app_text_scale': '${value.textScale}',
      'collect_customer_details': value.collectCustomerDetails ? '1' : '0',
      'staff_can_receive_stock': value.staffCanReceiveStock ? '1' : '0',
    };
    await db.transaction((txn) async {
      for (final entry in entries.entries) {
        await txn.insert('app_meta', {
          'key': entry.key,
          'value': entry.value,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
    });
  }

  Future<ReceiptTemplateSettings?> getSavedReceiptTemplateSettings(
    String scope, {
    required String companyName,
  }) async {
    final rows = await db.query(
      'app_meta',
      columns: ['value'],
      where: 'key = ?',
      whereArgs: ['receipt_template.$scope'],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    try {
      final json = (jsonDecode(rows.first['value'] as String) as Map)
          .cast<String, dynamic>();
      final isSettings = json.containsKey('default_template');
      return ReceiptTemplateSettings.fromJson(
        isSettings ? json : null,
        companyName: companyName,
        legacyActiveTemplate: isSettings ? null : json,
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> saveReceiptTemplateSettings(
    String scope,
    ReceiptTemplateSettings settings,
  ) => db.insert('app_meta', {
    'key': 'receipt_template.$scope',
    'value': jsonEncode(settings.toJson()),
  }, conflictAlgorithm: ConflictAlgorithm.replace);

  Future<List<AppNotificationRecord>> getNotifications({
    int limit = 100,
  }) async {
    final rows = await db.query(
      'app_notifications',
      orderBy: 'created_at DESC, id DESC',
      limit: limit,
    );
    return rows.map(AppNotificationRecord.fromMap).toList();
  }

  Future<void> markNotificationRead(int id) => db.update(
    'app_notifications',
    {'is_read': 1},
    where: 'id = ?',
    whereArgs: [id],
  );

  Future<void> markAllNotificationsRead() =>
      db.update('app_notifications', {'is_read': 1}, where: 'is_read = 0');

  Future<void> deleteNotification(int id) =>
      db.delete('app_notifications', where: 'id = ?', whereArgs: [id]);

  Future<void> restoreNotification(AppNotificationRecord notification) =>
      db.insert(
        'app_notifications',
        notification.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

  Future<void> clearNotifications() => db.delete('app_notifications');

  Future<void> voidSale(int saleId, String reason) async {
    await db.transaction((txn) async {
      final rows = await txn.query(
        'sales',
        columns: ['transaction_uuid', 'receptionist_name', 'voided'],
        where: 'id = ?',
        whereArgs: [saleId],
        limit: 1,
      );
      if (rows.isEmpty || (rows.first['voided'] as int) == 1) return;
      await txn.update(
        'sales',
        {'voided': 1, 'void_reason': reason.trim(), 'sync_status': 'pending'},
        where: 'id = ?',
        whereArgs: [saleId],
      );
      final reference = rows.first['transaction_uuid'] as String;
      final deductedRows = await txn.rawQuery(
        "SELECT product_id, -SUM(quantity_base) AS quantity "
        "FROM stock_movements WHERE type = 'sale' AND reference_id = ? "
        'GROUP BY product_id',
        [reference],
      );
      for (final row in deductedRows) {
        await _insertStockMovement(
          txn,
          productId: row['product_id'] as int,
          type: 'sale_void',
          quantityBase: (row['quantity'] as num).toInt(),
          actorName: 'Administrator',
          note: reason.trim(),
          referenceId: reference,
          createdAt: DateTime.now().toUtc(),
        );
      }
      await _resolveSaleDiscrepancies(
        txn,
        saleId: saleId,
        resolvedBy: 'Administrator',
        reason: 'Sale voided',
      );
    });
  }

  Future<DashboardSummary> getDashboardSummary() async {
    final today = await db.rawQuery('''
      SELECT COALESCE(SUM(total_cents), 0) AS total, COUNT(*) AS count
      FROM sales
      WHERE date(created_at, 'localtime') = date('now', 'localtime') AND voided = 0
    ''');
    final pending =
        Sqflite.firstIntValue(
          await db.rawQuery(
            "SELECT COUNT(*) FROM sales WHERE sync_status != 'synced'",
          ),
        ) ??
        0;
    final receptionists =
        Sqflite.firstIntValue(
          await db.rawQuery(
            "SELECT COUNT(*) FROM users WHERE role = 'receptionist' AND active = 1",
          ),
        ) ??
        0;
    return DashboardSummary(
      todayCents: (today.first['total'] as num).toInt(),
      todayTransactions: (today.first['count'] as num).toInt(),
      pendingSync: pending,
      activeReceptionists: receptionists,
    );
  }

  Future<int> _stockForProduct(DatabaseExecutor executor, int productId) async {
    final rows = await executor.rawQuery(
      'SELECT COALESCE(SUM(quantity_base), 0) AS quantity '
      'FROM stock_movements WHERE product_id = ?',
      [productId],
    );
    return (rows.first['quantity'] as num?)?.toInt() ?? 0;
  }

  Future<void> _insertStockMovement(
    DatabaseExecutor executor, {
    required int productId,
    required String type,
    required int quantityBase,
    required String actorName,
    required DateTime createdAt,
    String? note,
    String? referenceId,
  }) => executor.insert('stock_movements', {
    'movement_uuid': _uuid.v4(),
    'product_id': productId,
    'type': type,
    'quantity_base': quantityBase,
    'actor_name': actorName,
    'note': (note?.trim().isEmpty ?? true) ? null : note!.trim(),
    'reference_id': referenceId,
    'created_at': createdAt.toUtc().toIso8601String(),
  }, conflictAlgorithm: ConflictAlgorithm.ignore);

  Future<void> _resolveLowStockIfRecovered(
    DatabaseExecutor executor,
    int productId,
    DateTime resolvedAt,
  ) async {
    final productRows = await executor.query(
      'products',
      columns: ['low_stock_threshold'],
      where: 'id = ?',
      whereArgs: [productId],
      limit: 1,
    );
    if (productRows.isEmpty) return;
    final threshold =
        (productRows.first['low_stock_threshold'] as num?)?.toInt() ?? 0;
    final stock = max(0, await _stockForProduct(executor, productId));
    if (stock <= threshold) return;
    await executor.update(
      'app_notifications',
      {'resolved_at': resolvedAt.toUtc().toIso8601String(), 'is_read': 1},
      where: "type = 'low_stock' AND product_id = ? AND resolved_at IS NULL",
      whereArgs: [productId],
    );
  }

  Future<void> _resolveSaleDiscrepancies(
    DatabaseExecutor executor, {
    required int saleId,
    required String resolvedBy,
    required String reason,
  }) async {
    final now = DateTime.now().toUtc().toIso8601String();
    await executor.update(
      'stock_discrepancies',
      {
        'resolved_at': now,
        'resolved_by': resolvedBy,
        'resolution_reason': reason,
      },
      where: 'sale_id = ? AND resolved_at IS NULL',
      whereArgs: [saleId],
    );
    await executor.update(
      'app_notifications',
      {'resolved_at': now, 'is_read': 1},
      where:
          "type = 'stock_discrepancy' AND sale_id = ? AND resolved_at IS NULL",
      whereArgs: [saleId],
    );
  }

  static String _phoneKey(String phone) =>
      phone.replaceAll(RegExp(r'[^0-9+]'), '').toLowerCase();

  Future<bool> _preferenceEnabled(
    DatabaseExecutor executor,
    String key, {
    bool defaultValue = false,
  }) async {
    final rows = await executor.query(
      'app_meta',
      columns: ['value'],
      where: 'key = ?',
      whereArgs: [key],
      limit: 1,
    );
    if (rows.isEmpty) return defaultValue;
    return rows.first['value'] == '1';
  }

  Future<void> _insertNotification(
    DatabaseExecutor executor, {
    required String type,
    required String title,
    required String message,
    required DateTime createdAt,
    int? productId,
    int? saleId,
    String? referenceId,
  }) async {
    if (referenceId != null) {
      final existing = await executor.query(
        'app_notifications',
        columns: ['id'],
        where: 'reference_id = ?',
        whereArgs: [referenceId],
        limit: 1,
      );
      if (existing.isNotEmpty) return;
    }
    await executor.insert('app_notifications', {
      'type': type,
      'title': title,
      'message': message,
      'product_id': productId,
      'sale_id': saleId,
      'reference_id': referenceId,
      'created_at': createdAt.toUtc().toIso8601String(),
      'is_read': 0,
    });
  }
}

class _MutableDebtSummary {
  _MutableDebtSummary({
    required this.customerName,
    required this.customerPhone,
    required this.companyName,
  });

  String customerName;
  final String customerPhone;
  String companyName;
  int totalDebtCents = 0;
  int paidCents = 0;
  int saleCount = 0;
  DateTime? latestSaleAt;
  DateTime? nextDueAt;
}

class InventoryShortageException implements Exception {
  const InventoryShortageException(this.productIds);

  final List<int> productIds;
}

Uint8List? _decodeProductImage(Object? encoded) {
  final value = encoded?.toString().trim() ?? '';
  if (value.isEmpty) return null;
  try {
    return base64Decode(value);
  } catch (_) {
    return null;
  }
}
