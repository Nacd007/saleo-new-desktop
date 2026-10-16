import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saleo_app/product_management_view.dart';
import 'package:saleo_app/models.dart';
import 'package:saleo_app/app_controller.dart';
import 'package:saleo_app/auth_service.dart';
import 'package:saleo_app/database_service.dart';
import 'package:saleo_app/sync_service.dart';

class MemoryDatabase extends DatabaseService {
  final meta = <String, String>{};
  @override
  Future<String?> readWorkflowMeta(String key) async => meta[key];
  @override
  Future<void> writeWorkflowMeta(String key, String value) async {
    meta[key] = value;
  }
}

Product product(int id, {bool active = true}) => Product(
  id: id,
  name: 'Product ${id.toString().padLeft(3, "0")}',
  code: 'P$id',
  category: 'Drinks',
  active: active,
  currentStock: 24,
  forms: [
    SellingForm(
      id: id,
      productId: id,
      name: 'Single',
      priceCents: 350,
      active: true,
      unitsPerForm: 1,
    ),
    SellingForm(
      id: id + 1000,
      productId: id,
      name: 'Crate',
      priceCents: 30000,
      active: true,
      unitsPerForm: 24,
    ),
  ],
);
void main() {
  testWidgets('desktop catalogue fits ten rows without bulk selection', (
    tester,
  ) async {
    // The Windows content area is smaller than the monitor after title,
    // search, sync and task bars are accounted for.
    tester.view.physicalSize = const Size(1600, 880);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final c = AppController(MemoryDatabase(), SyncService(), AuthService());
    c.products = List.generate(43, (i) => product(i));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ProductManagementView(
            controller: c,
            initialStatus: 'All',
            onAdd: () async {},
            onImport: () async {},
            onCategory: () async {},
            onSample: () async {},
            onTemplate: (_) async {},
            onEdit: (_) async {},
            onAddForm: (_) async {},
            onEditForm: (_, form) async {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(Checkbox), findsNothing);
    expect(find.text('Product 009'), findsOneWidget);
    expect(tester.getBottomLeft(find.text('Product 009')).dy, lessThan(825));
    expect(find.text('Showing 1–43 of 43 products'), findsOneWidget);
    expect(find.text('Rows per page'), findsNothing);
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -700));
    await tester.pumpAndSettle();
    final headingTop = tester.getTopLeft(find.text('PRODUCT')).dy;
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -300));
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(find.text('PRODUCT')).dy, closeTo(headingTop, 1));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    c.dispose();
  });
  test(
    'product preferences queue durably and ignore signed-out requests',
    () async {
      final db = MemoryDatabase();
      final c = AppController(db, SyncService(), AuthService());
      addTearDown(c.dispose);
      final view = <String, dynamic>{
        'size': 75,
        'status': 'Active',
        'category': null,
      };
      await c.saveProductViewPreferences(view);
      expect(db.meta, isEmpty);
      c.currentUser = const AppUser(
        id: 7,
        username: 'Admin',
        displayName: 'Admin',
        role: UserRole.admin,
        active: true,
      );
      c.loadingCompanyData = true;
      await c.saveProductViewPreferences(view);
      expect(db.meta['product.view.7'], contains('"size":75'));
      expect(db.meta['preferences.admin.outbox'], contains('"product_view"'));
    },
  );
  test('active products precede inactive ones', () {
    expect(
      filterProductCatalogue([product(1, active: false), product(2)]).first.id,
      2,
    );
    expect(
      filterProductCatalogue([product(1), product(2)], query: 'crate').length,
      2,
    );
    expect(filterProductCatalogue([product(1)], status: 'Inactive'), isEmpty);
  });
  test('warn about expensive packs without changing prices', () {
    final p = product(1);
    expect(sellingPriceWarning(p, 1001, 30000, 24), contains('GHS'));
    expect(sellingPriceWarning(p, 1001, 8000, 24), isNull);
    expect(p.forms.last.priceCents, 30000);
  });
  for (final width in [375.0, 390.0, 1280.0]) {
    for (final brightness in Brightness.values) {
      testWidgets(
        'product paging, filters and forms at width $width / $brightness',
        (tester) async {
          tester.view.physicalSize = Size(width, 1000);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final c = AppController(
            MemoryDatabase(),
            SyncService(),
            AuthService(),
          );
          c.products = List.generate(151, (i) => product(i));
          await tester.pumpWidget(
            MaterialApp(
              theme: ThemeData(brightness: brightness),
              home: Scaffold(
                body: ProductManagementView(
                  controller: c,
                  initialStatus: 'All',
                  onAdd: () async {},
                  onImport: () async {},
                  onCategory: () async {},
                  onSample: () async {},
                  onTemplate: (_) async {},
                  onEdit: (_) async {},
                  onAddForm: (_) async {},
                  onEditForm: (_, form) async {},
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(find.text('Showing 1–75 of 151 products'), findsOneWidget);
          expect(find.text('Rows per page'), findsNothing);
          await tester.tap(find.byTooltip('Next page'));
          await tester.pumpAndSettle();
          expect(find.text('Showing 76–150 of 151 products'), findsOneWidget);
          await tester.enterText(find.byType(TextField), 'Product 150');
          await tester.pumpAndSettle();
          expect(find.text('Showing 1–1 of 1 products'), findsOneWidget);
          await tester.tap(find.text('Product 150').last);
          await tester.pumpAndSettle();
          expect(find.text('Selling forms (2)'), findsOneWidget);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
          c.dispose();
        },
      );
    }
  }
  testWidgets('new selling form does not offer an unsaved inactive option', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SellingFormEditor(
            product: product(1),
            form: SellingForm(
              id: -1,
              productId: 1,
              name: 'New form',
              priceCents: 100,
              active: true,
              unitsPerForm: 1,
            ),
          ),
        ),
      ),
    );
    expect(find.byType(SwitchListTile), findsNothing);
    expect(find.text('Save changes'), findsOneWidget);
  });
  testWidgets('invalid price stays in editor with inline error', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SellingFormEditor(
            product: product(1),
            form: product(1).forms.last,
          ),
        ),
      ),
    );
    await tester.enterText(find.byType(TextFormField).at(1), 'NaN');
    await tester.tap(find.text('Save changes'));
    await tester.pumpAndSettle();
    expect(
      find.text('Enter a positive price with at most two decimal places.'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}
