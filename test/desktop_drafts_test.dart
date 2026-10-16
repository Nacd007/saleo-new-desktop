import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saleo_app/app_controller.dart';
import 'package:saleo_app/auth_service.dart';
import 'package:saleo_app/database_service.dart';
import 'package:saleo_app/desktop_design.dart';
import 'package:saleo_app/desktop_drafts.dart';
import 'package:saleo_app/models.dart';
import 'package:saleo_app/sync_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _DraftDatabase extends DatabaseService {
  _DraftDatabase(this.fixture);
  final Database fixture;
  @override
  Database get db => fixture;
}

void main() {
  testWidgets(
    'independent carts survive navigation and completed draft retires alone',
    (tester) async {
      final db = (await tester.runAsync(
        () => databaseFactoryFfi.openDatabase(
          inMemoryDatabasePath,
          options: OpenDatabaseOptions(singleInstance: false),
        ),
      ))!;
      await tester.runAsync(
        () => db.execute(
          'CREATE TABLE app_meta(key TEXT PRIMARY KEY, value TEXT)',
        ),
      );
      final controller = AppController(
        _DraftDatabase(db),
        SyncService(),
        AuthService(),
      );
      controller.currentUser = AppUser(
        id: 1,
        username: 'draft-test',
        displayName: 'Fixture',
        role: UserRole.receptionist,
        active: true,
      );
      final form = SellingForm(
        id: 1,
        productId: 1,
        name: 'Crate',
        priceCents: 20000,
        unitsPerForm: 24,
        active: true,
      );
      final product = Product(
        id: 1,
        code: 'FIXTURE',
        name: 'Fixture product',
        category: 'Beverages',
        active: true,
        forms: [form],
        currentStock: 240,
      );
      controller.products = [product];
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      Future<void> mount() async {
        await tester.pumpWidget(
          MaterialApp(
            theme: desktopTheme(DesktopMode.white),
            home: Scaffold(body: DesktopSellPage(controller: controller)),
          ),
        );
        await tester.runAsync(
          () async => Future<void>.delayed(const Duration(milliseconds: 30)),
        );
        await tester.pumpAndSettle();
      }

      await mount();
      controller.addToCart(product, form, 2);
      await tester.pump();
      await tester.runAsync(() => controller.flushDesktopDraft!());
      await tester.tap(find.text('New sale').first);
      await tester.runAsync(
        () async => Future<void>.delayed(const Duration(milliseconds: 30)),
      );
      await tester.pumpAndSettle();
      expect(controller.cart, isEmpty);
      controller.addToCart(product, form, 3);
      await tester.pump();
      await tester.runAsync(() => controller.flushDesktopDraft!());
      await tester.tap(find.text('Sale 1'));
      await tester.runAsync(
        () async => Future<void>.delayed(const Duration(milliseconds: 30)),
      );
      await tester.pumpAndSettle();
      expect(controller.cart.single.quantity, 2);
      final completedKey = controller.desktopDraftKey!;
      // Mimic the already-committed sale event; the database commit removes this key.
      await tester.runAsync(
        () =>
            db.delete('app_meta', where: 'key = ?', whereArgs: [completedKey]),
      );
      controller.cart = [];
      controller.completedSalesRevision++;
      controller.notifyListeners();
      await tester.pumpAndSettle();
      expect(controller.cart.single.quantity, 3);
      expect(find.text('Sale 1'), findsNothing);
      await tester.tap(find.byTooltip('Rename Sale 2'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'Draft name'),
        'Customer order',
      );
      await tester.tap(find.text('Save name'));
      await tester.runAsync(
        () async => Future<void>.delayed(const Duration(milliseconds: 30)),
      );
      await tester.pumpAndSettle();
      expect(find.text('Customer order'), findsOneWidget);
      await tester.runAsync(() => controller.flushDesktopDraft!());
      await tester.pumpWidget(const SizedBox());
      await mount();
      expect(controller.cart.single.quantity, 3);
      expect(find.text('Customer order'), findsOneWidget);
      expect(
        await tester.runAsync(
          () =>
              db.query('app_meta', where: 'key = ?', whereArgs: [completedKey]),
        ),
        isEmpty,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(() => db.close());
      controller.dispose();
    },
  );
}
