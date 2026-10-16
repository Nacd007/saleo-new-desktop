import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saleo_app/app_controller.dart';
import 'package:saleo_app/auth_service.dart';
import 'package:saleo_app/database_service.dart';
import 'package:saleo_app/desktop_checkout_ui.dart';
import 'package:saleo_app/desktop_design.dart';
import 'package:saleo_app/models.dart';
import 'package:saleo_app/receptionist_home.dart';
import 'package:saleo_app/sync_service.dart';

class _CheckoutController extends AppController {
  _CheckoutController()
    : super(DatabaseService(), SyncService(), AuthService());
  int printCalls = 0, saveCalls = 0;
  @override
  Future<List<StockShortage>> getCartStockShortages() async => [];
  @override
  Future<bool> printReceipt(Sale sale) async {
    printCalls++;
    return true;
  }

  @override
  Future<Sale?> completeSale({
    required String paymentMethod,
    required int cashCents,
    required int mobileMoneyCents,
    required int cashTenderedCents,
    required int changeGivenCents,
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
    bool allowStockOverride = false,
  }) async {
    saveCalls++;
    final total = cartTotalCents;
    cart = [];
    completedSalesRevision++;
    notifyListeners();
    return Sale(
      id: 1,
      transactionUuid: 'fixture',
      receiptNumber: 'RCP-TEST',
      receptionistId: 1,
      receptionistUsername: 'fixture',
      receptionistName: 'Fixture',
      deviceId: 'test',
      createdAt: DateTime(2026),
      totalCents: total,
      paymentMethod: paymentMethod,
      cashCents: cashCents,
      mobileMoneyCents: mobileMoneyCents,
      cashTenderedCents: cashTenderedCents,
      changeGivenCents: changeGivenCents,
      syncStatus: 'pending',
      voided: false,
    );
  }
}

void main() {
  void size(WidgetTester tester) {
    tester.view.physicalSize = const Size(1440, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  testWidgets(
    'desktop receipt print and close retain workspace even when draft screen changes',
    (tester) async {
      size(tester);
      final c = _CheckoutController();
      final form = SellingForm(
        id: 1,
        productId: 1,
        name: 'Crate',
        unitsPerForm: 24,
        priceCents: 20000,
        active: true,
      );
      final p = Product(
        id: 1,
        code: 'FIXTURE',
        name: 'Fixture product',
        category: 'Beverages',
        active: true,
        currentStock: 240,
        forms: [form],
      );
      c.products = [p];
      c.cart = [CartLine(product: p, form: form, quantity: 1)];
      await tester.pumpWidget(
        MaterialApp(
          theme: desktopTheme(DesktopMode.white),
          home: Scaffold(
            body: Builder(
              builder: (host) => AnimatedBuilder(
                animation: c,
                builder: (_, _) => NewSaleScreen(
                  key: ValueKey(c.completedSalesRevision),
                  controller: c,
                  receiptHostContext: host,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Review products and payment'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Confirm products').last);
      await tester.pumpAndSettle();
      expect(find.text('How was this sale paid?'), findsOneWidget);
      await tester.tap(find.text('Complete sale'));
      await tester.pumpAndSettle();
      expect(find.text('Confirm payment received'), findsOneWidget);
      await tester.tap(find.text('Confirm & finalize'));
      await tester.pumpAndSettle();
      expect(c.saveCalls, 1);
      expect(find.text('RCP-TEST'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('Print receipt'),
        150,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.tap(find.text('Print receipt'));
      await tester.pumpAndSettle();
      expect(c.printCalls, 1);
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      expect(find.text('Product catalogue'), findsOneWidget);
      expect(find.text('Current sale'), findsOneWidget);
      expect(find.text('How was this sale paid?'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'company search expands inline at unchanged width and filters all available entries',
    (tester) async {
      size(tester);
      final records = ['Alpha Company', 'Beta Company']
          .asMap()
          .entries
          .map(
            (e) => CustomerRecord(
              id: e.key,
              name: e.value,
              phone: '020000000${e.key}',
              companyName: e.value,
              createdAt: DateTime(2026),
              updatedAt: DateTime(2026),
            ),
          )
          .toList();
      CustomerRecord? selected;
      await tester.pumpWidget(
        MaterialApp(
          theme: desktopTheme(DesktopMode.white),
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 500,
                child: CheckoutCompanyPicker(
                  customers: records,
                  credit: true,
                  onSelected: (v) => selected = v,
                ),
              ),
            ),
          ),
        ),
      );
      final width = tester.getSize(find.byType(CheckoutCompanyPicker)).width;
      await tester.tap(find.text('Search customer or company'));
      await tester.pumpAndSettle();
      expect(find.text('Alpha Company'), findsOneWidget);
      expect(find.text('Beta Company'), findsOneWidget);
      expect(
        tester
            .widget<Card>(find.byKey(const ValueKey('company-search-results')))
            .color,
        desktopTheme(DesktopMode.white).colorScheme.surfaceContainer,
      );
      expect(tester.getSize(find.byType(CheckoutCompanyPicker)).width, width);
      expect(find.byType(AlertDialog), findsNothing);
      await tester.enterText(find.byType(TextField), 'Beta');
      await tester.pump();
      expect(find.text('Alpha Company'), findsNothing);
      await tester.tap(find.text('Beta Company'));
      await tester.pump();
      expect(selected?.companyName, 'Beta Company');
      await tester.tap(find.text('Search customer or company'));
      await tester.pump();
      expect(find.text('Alpha Company'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
