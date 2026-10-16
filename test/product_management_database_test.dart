import 'package:flutter_test/flutter_test.dart';
import 'package:saleo_app/database_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class FixtureDatabase extends DatabaseService {
  FixtureDatabase(this.fixture);
  final Database fixture;
  @override
  Database get db => fixture;
}

void main() {
  test(
    'bulk edits are atomic and price audit retains old receipt values',
    () async {
      final db = await databaseFactoryFfi.openDatabase(
        inMemoryDatabasePath,
        options: OpenDatabaseOptions(singleInstance: false),
      );
      addTearDown(db.close);
      await db.execute(
        'CREATE TABLE products(id INTEGER PRIMARY KEY, active INTEGER, category TEXT, updated_at TEXT)',
      );
      await db.execute(
        'CREATE TABLE selling_forms(id INTEGER PRIMARY KEY, product_id INTEGER, name TEXT, price_cents INTEGER, units_per_form INTEGER, active INTEGER, updated_at TEXT)',
      );
      await db.execute(
        'CREATE TABLE app_meta(key TEXT PRIMARY KEY, value TEXT)',
      );
      await db.execute(
        'CREATE TABLE sale_items(id INTEGER PRIMARY KEY, price_cents INTEGER)',
      );
      await db.insert('products', {'id': 1, 'active': 1, 'category': 'Drinks'});
      await db.insert('selling_forms', {
        'id': 1,
        'product_id': 1,
        'name': 'Single',
        'price_cents': 350,
        'units_per_form': 1,
        'active': 1,
      });
      await db.insert('sale_items', {'id': 1, 'price_cents': 350});
      final service = FixtureDatabase(db);
      await expectLater(
        service.bulkUpdateProducts({1, 999}, active: false),
        throwsStateError,
      );
      expect((await db.query('products')).single['active'], 1);
      await service.bulkUpdateProducts(
        {1},
        active: false,
        category: 'Beverages',
      );
      expect((await db.query('products')).single['active'], 0);
      await service.updateSellingForm(
        id: 1,
        name: 'Single',
        priceCents: 450,
        active: false,
        unitsPerForm: 1,
        actorName: 'Test administrator',
      );
      final audit = await service.productPriceHistory(1);
      expect(audit.single['old'], 350);
      expect(audit.single['new'], 450);
      expect(audit.single['actor'], 'Test administrator');
      expect((await db.query('sale_items')).single['price_cents'], 350);
      await service.updateSellingForm(
        id: 1,
        name: 'Single',
        priceCents: 450,
        active: true,
        unitsPerForm: 1,
        actorName: 'Test administrator',
      );
      expect((await service.productPriceHistory(1)).length, 1);
    },
  );
}
