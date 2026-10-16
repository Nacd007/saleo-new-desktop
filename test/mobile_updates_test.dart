import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saleo_app/admin_settings.dart';
import 'package:saleo_app/app_controller.dart';
import 'package:saleo_app/auth_service.dart';
import 'package:saleo_app/credit_collections.dart';
import 'package:saleo_app/database_service.dart';
import 'package:saleo_app/models.dart';
import 'package:saleo_app/onboarding_screen.dart';
import 'package:saleo_app/sales_report.dart';
import 'package:saleo_app/sync_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _Controller extends AppController {
  _Controller() : super(DatabaseService(), SyncService(), AuthService());
  bool loggedOut = false;
  @override
  Future<int> unsyncedRecordCount() async => 0;
  @override
  Future<void> logout() async {
    loggedOut = true;
  }
}

// Isolated fixtures exercise ledger logic without touching encrypted device data.
class _FixtureDb implements Database {
  _FixtureDb(this.tables);
  final Map<String, List<Map<String, Object?>>> tables;
  @override
  Future<List<Map<String, Object?>>> query(
    String table, {
    bool? distinct,
    List<String>? columns,
    String? where,
    List<Object?>? whereArgs,
    String? groupBy,
    String? having,
    String? orderBy,
    int? limit,
    int? offset,
  }) async => tables[table] ?? [];
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _LedgerDb extends DatabaseService {
  _LedgerDb(this.fixture, this.receipts);
  final Database fixture;
  final List<Sale> receipts;
  @override
  Database get db => fixture;
  @override
  Future<List<Sale>> getSales({String? receptionistUsername}) async => receipts;
}

Sale _sale(int id, int debt, int previous, {int paidLater = 0}) => Sale(
  id: id,
  transactionUuid: 'sale-$id',
  receiptNumber: 'RCP-$id',
  receptionistId: 1,
  receptionistUsername: 'gen',
  receptionistName: 'Gen',
  customerName: 'Franko',
  customerCompany: 'Franko Ltd',
  customerPhone: '0249726832',
  collectedBy: 'Ken',
  collectorPhone: '0200000000',
  previousDebtCents: previous,
  deviceId: 'fixture',
  createdAt: DateTime(2026, 10, id),
  totalCents: debt,
  paymentMethod: 'debt',
  cashCents: 0,
  mobileMoneyCents: 0,
  debtCents: debt,
  debtPaidCents: paidLater,
  syncStatus: 'synced',
  voided: false,
);
void main() {
  testWidgets(
    'debtors screen updates after a credit sale is recorded locally',
    (tester) async {
      final controller = _Controller();
      await tester.pumpWidget(
        MaterialApp(home: DebtorsScreen(controller: controller)),
      );
      expect(find.text('No debt sales recorded yet.'), findsOneWidget);
      controller.debtors = const [
        DebtorSummary(
          customerName: 'Test Buyer',
          customerPhone: '0240000000',
          companyName: 'Test Business',
          totalDebtCents: 50000,
          paidCents: 0,
          outstandingCents: 50000,
          saleCount: 1,
        ),
      ];
      controller.notifyListeners();
      await tester.pump();
      expect(find.text('Test Business'), findsOneWidget);
      expect(find.text('No debt sales recorded yet.'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      controller.dispose();
    },
  );
  testWidgets('inventory report links open real reports and omit export', (
    tester,
  ) async {
    final controller = _Controller();
    controller.stockMovements = [
      StockMovement(
        id: 1,
        movementUuid: 'fixture',
        productId: 99,
        type: 'restock',
        quantityBase: 24,
        createdAt: DateTime.now(),
        actorName: 'Gen',
      ),
    ];
    await tester.pumpWidget(
      MaterialApp(home: InventoryReportsScreen(controller: controller)),
    );
    expect(find.text('Export inventory'), findsNothing);
    await tester.scrollUntilVisible(find.text('Product performance'), 200);
    await tester.tap(find.text('Product performance'));
    await tester.pumpAndSettle();
    expect(find.text('High movers'), findsOneWidget);
    expect(find.text('Rank by'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Stock movement report'));
    await tester.pumpAndSettle();
    expect(find.text('Search movements'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Product #99'),
      200,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.text('Product #99'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  test('settled debtors remain stored and listed', () async {
    final db = _LedgerDb(
      _FixtureDb({
        'sales': [
          {
            'customer_phone': '0249726832',
            'customer_name': 'Franko',
            'customer_company': 'Franko Ltd',
            'debt_cents': 20000,
            'debt_paid_cents': 0,
          },
        ],
        'debt_payments': [
          {'customer_phone': '0249726832', 'amount_cents': 20000},
        ],
      }),
      [],
    );
    final result = await db.getDebtorSummaries();
    expect(result, hasLength(1));
    expect(result.single.outstandingCents, 0);
    expect(result.single.paidCents, 20000);
  });
  test(
    'ledger preserves original credit, receiver and previous balance',
    () async {
      final ledger =
          await _LedgerDb(_FixtureDb({}), [
            _sale(1, 20000, 0, paidLater: 20000),
            _sale(2, 15000, 20000),
          ]).getDebtLedger(
            const DebtorSummary(
              customerName: 'Franko',
              customerPhone: '0249726832',
              totalDebtCents: 35000,
              paidCents: 20000,
              outstandingCents: 15000,
              saleCount: 2,
            ),
          );
      expect(ledger.first.balanceBeforeCents, 20000);
      expect(ledger.first.balanceAfterCents, 35000);
      expect(ledger.first.collectedBy, 'Ken');
      expect(ledger.first.recordedBy, 'Gen');
      expect(ledger.last.amountCents, 20000);
    },
  );
  test('repayments are collections, not duplicate sales', () {
    final payment = CreditPaymentRecord(
      id: 'payment',
      companyName: 'Franko Ltd',
      customerName: 'Franko',
      amountCents: 5000,
      cashCents: 5000,
      mobileMoneyCents: 0,
      recordedBy: 'Wim',
      createdAt: DateTime(2026, 10, 3, 8),
      method: 'cash',
    );
    expect(
      moneyCollectedForDay(
        [_sale(1, 20000, 0)],
        [payment],
        DateTime(2026, 10, 3, 12),
      ),
      5000,
    );
    expect(creditPaymentsForDay([payment], DateTime(2026, 10, 4)), isEmpty);
  });
  for (final size in [
    const Size(360, 800),
    const Size(800, 1024),
    const Size(1024, 768),
  ]) {
    testWidgets('welcome, debtors and reports fit $size', (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = size;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final controller = _Controller();
      await tester.pumpWidget(
        MaterialApp(home: OnboardingScreen(controller: controller)),
      );
      expect(tester.takeException(), isNull);
      controller.debtors = const [
        DebtorSummary(
          customerName: 'A company with a long business name',
          companyName: 'A company with a long business name',
          customerPhone: '0249726832',
          totalDebtCents: 20000,
          paidCents: 20000,
          outstandingCents: 0,
          saleCount: 2,
        ),
      ];
      await tester.pumpWidget(
        MaterialApp(home: DebtorsScreen(controller: controller)),
      );
      await tester.scrollUntilVisible(
        find.text('Settled accounts'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Settled accounts'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SalesReportPage(
              sales: [],
              onRefresh: () async {},
              controller: controller,
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Product trend'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('logout requires confirmation and preserves records', (
    tester,
  ) async {
    final controller = _Controller();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AdminSettingsPage(
            controller: controller,
            staffPageBuilder: (_) => const SizedBox(),
          ),
        ),
      ),
    );
    await tester.scrollUntilVisible(find.text('Log out'), 300);
    await tester.tap(find.text('Log out'));
    await tester.pumpAndSettle();
    expect(controller.loggedOut, isFalse);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(controller.loggedOut, isFalse);
    await tester.tap(find.text('Log out'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Continue'));
    await tester.pumpAndSettle();
    expect(controller.loggedOut, isFalse);
    await tester.tap(find.widgetWithText(FilledButton, 'Sign out'));
    await tester.pumpAndSettle();
    expect(controller.loggedOut, isTrue);
  });
}
