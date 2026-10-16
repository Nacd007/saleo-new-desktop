import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saleo_app/app_controller.dart';
import 'package:saleo_app/auth_service.dart';
import 'package:saleo_app/database_service.dart';
import 'package:saleo_app/inventory_page.dart';
import 'package:saleo_app/models.dart';
import 'package:saleo_app/sync_service.dart';

class _Controller extends AppController {
  _Controller() : super(DatabaseService(), SyncService(), AuthService()) {
    currentUser = const AppUser(
      id: 1,
      username: 'admin',
      displayName: 'Admin',
      role: UserRole.admin,
      active: true,
    );
    products = const [
      Product(
        id: 1,
        name: 'Club',
        code: 'CLUB',
        category: 'Drinks',
        active: true,
        currentStock: 0,
        forms: [
          SellingForm(
            id: 1,
            productId: 1,
            name: 'Crate',
            priceCents: 20000,
            unitsPerForm: 24,
            active: true,
          ),
        ],
      ),
    ];
  }
  List<StockReceiptDraftItem>? received;
  @override
  Future<void> receiveStock({
    required List<StockReceiptDraftItem> items,
    String? supplierName,
    String? invoiceNumber,
    bool confirm = true,
  }) async {
    received = items;
    expect(confirm, isTrue);
  }
}

Finder field(String label) => find.byWidgetPredicate(
  (widget) => widget is TextField && widget.decoration?.labelText == label,
);

void main() {
  testWidgets(
    'delivery edits preserve the list and admin needs two confirmations',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(800, 1200);
      addTearDown(() {
        tester.view.resetDevicePixelRatio();
        tester.view.resetPhysicalSize();
      });
      final controller = _Controller();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: InventoryPage(controller: controller, receiveOnly: true),
          ),
        ),
      );
      await tester.tap(find.text('Add product to delivery'));
      await tester.pumpAndSettle();
      await tester.enterText(field('Quantity of forms'), '2');
      await tester.tap(find.widgetWithText(FilledButton, 'Add'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Edit item'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(field('Quantity of forms')).controller!.text,
        '2',
      );
      await tester.enterText(field('Quantity of forms'), '3');
      final search = find
          .descendant(
            of: find.byType(DropdownMenu<Product>),
            matching: find.byType(TextField),
          )
          .first;
      await tester.enterText(search, 'old query');
      await tester.tap(find.byTooltip('Search products'));
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(search).controller!.text, isEmpty);
      await tester.tap(find.widgetWithText(FilledButton, 'Save changes'));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Edit item'), findsOneWidget);
      await tester.tap(find.text('Review & confirm'));
      await tester.pumpAndSettle();
      expect(controller.received, isNull);
      await tester.tap(find.widgetWithText(FilledButton, 'Continue'));
      await tester.pumpAndSettle();
      expect(controller.received, isNull);
      await tester.tap(find.widgetWithText(FilledButton, 'Confirm delivery'));
      await tester.pumpAndSettle();
      expect(controller.received!.single.quantityForms, 3);
      expect(tester.takeException(), isNull);
    },
  );
}
