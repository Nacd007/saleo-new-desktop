import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:saleo_app/database_service.dart';
import 'package:saleo_app/models.dart';
import 'package:saleo_app/sync_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class FixtureDatabase extends DatabaseService {
  FixtureDatabase(this.fixture);
  final Database fixture;
  @override
  Database get db => fixture;
}

void main() {
  test(
    'remote staff IDs cannot break sale and debt imports or grant access',
    () async {
      final db = await databaseFactoryFfi.openDatabase(
        inMemoryDatabasePath,
        options: OpenDatabaseOptions(singleInstance: false),
      );
      addTearDown(db.close);
      await db.execute('PRAGMA foreign_keys = ON');
      // Exercise the actual production schema with its foreign keys enabled.
      final source = File('lib/database_service.dart').readAsStringSync();
      for (final table in ['users', 'sales', 'sale_items']) {
        final sql = RegExp('CREATE TABLE $table \\([\\s\\S]*?\\n          \\)')
            .firstMatch(source)!
            .group(0)!;
        await db.execute(sql);
      }
      await db.execute('CREATE TABLE debt_payments (customer_phone TEXT, amount_cents INTEGER, created_at TEXT)');
      await db.insert('users', {
        'id': 1,
        'username': 'local-admin',
        'password_hash': 'fixture',
        'display_name': 'Admin',
        'role': 'admin',
        'created_at': '2026-10-16T00:00:00Z',
      });
      final service = FixtureDatabase(db);
      final remote = <String, dynamic>{
        'transaction_uuid': 'remote-sale',
        'receipt_number': 'REMOTE-1',
        'receptionist_id': 900,
        'receptionist_username': 'remote-staff',
        'receptionist_name': 'Remote Staff',
        'created_at': '2026-10-16T00:00:00Z',
        'total_cents': 500000,
        'cash_cents': 400000,
        'debt_cents': 100000,
        'customer_phone': '0240000000',
        'items': <dynamic>[],
      };
      await service.upsertRemoteSales([remote], notifySales: false);
      await service.upsertRemoteSales([remote], notifySales: false);
      final sale = (await db.query('sales')).single;
      final staff = (await db.query(
        'users',
        where: 'username = ?',
        whereArgs: ['remote-staff'],
      )).single;
      expect(sale['receptionist_id'], staff['id']);
      expect(sale['receptionist_id'], isNot(900));
      expect(staff['active'], 0);
      expect(sale['debt_cents'], 100000);
      final debtors = await service.getDebtorSummaries();
      expect(debtors, hasLength(1));
      expect(debtors.single.customerPhone, '0240000000');
      expect(debtors.single.outstandingCents, 100000);
      expect(await db.rawQuery('PRAGMA foreign_key_check'), isEmpty);
      await service.upsertRemoteSales([
        {
          ...remote,
          'transaction_uuid': 'admin-sale',
          'receipt_number': 'REMOTE-2',
          'receptionist_username': 'local-admin',
          'receptionist_id': 777,
        },
      ], notifySales: false);
      expect(
        (await db.query(
          'sales',
          where: 'transaction_uuid = ?',
          whereArgs: ['admin-sale'],
        )).single['receptionist_id'],
        1,
      );
      expect((await db.query('users')).length, 2);
    },
  );

  test(
    'invalid customer stays queued while valid customer uploads and retries',
    () async {
      final sync = SyncService()..useSession('fixture');
      CustomerRecord customer(int id, String phone) => CustomerRecord(
        id: id,
        name: 'Fixture',
        phone: phone,
        createdAt: DateTime.utc(2026),
        updatedAt: DateTime.utc(2026),
      );
      final good = customer(1, '0240000000');
      final bad = customer(2, '1');
      var requests = 0;
      await http.runWithClient(
        () async {
          expect(await sync.pushCustomers([good, bad]), isFalse);
          expect(sync.pendingCustomerPhones([good, bad]), {'1'});
          expect(sync.lastCustomerUploadError, contains('phone'));
          expect(sync.lastCustomerUploadError, contains('Fixture'));
          expect(sync.rejectedCustomerPhones, {'1'});
          expect(
            await sync.pushCustomers([good, customer(2, '0240000001')]),
            isTrue,
          );
        },
        () => MockClient((request) async {
          requests++;
          final rows = (jsonDecode(request.body) as Map)['customers'] as List;
          expect(rows.length, 1);
          return http.Response(
            jsonEncode({
              'accepted_phone_keys': [rows.single['phone']],
            }),
            200,
          );
        }),
      );
      expect(requests, 2);
    },
  );
}
