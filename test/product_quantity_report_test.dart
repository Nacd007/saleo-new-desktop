import 'package:flutter_test/flutter_test.dart';
import 'package:saleo_app/models.dart';
import 'package:saleo_app/formatters.dart';
import 'package:saleo_app/product_quantity_report.dart';

const product = Product(
  id: 10,
  name: 'Club',
  code: 'CLUB',
  category: 'Drinks',
  active: true,
  baseUnit: 'bottle',
  forms: [
    SellingForm(
      id: 1,
      productId: 10,
      name: 'Crate',
      priceCents: 20000,
      active: true,
      unitsPerForm: 24,
    ),
  ],
);
Sale sale(DateTime date, {bool voided = false}) => Sale(
  id: 1,
  transactionUuid: 'sale-1',
  receiptNumber: 'RCP-1',
  receptionistId: 1,
  receptionistUsername: 'staff',
  receptionistName: 'Staff',
  deviceId: 'test',
  createdAt: date,
  totalCents: 10000,
  paymentMethod: 'cash',
  cashCents: 10000,
  mobileMoneyCents: 0,
  syncStatus: 'synced',
  voided: voided,
  items: const [
    SaleItem(
      productId: 99,
      productCode: 'club',
      productName: 'Old name',
      formName: 'Half',
      unitPriceCents: 10000,
      quantity: 2,
      lineTotalCents: 20000,
      unitsPerForm: 12,
    ),
    SaleItem(
      productId: 99,
      productCode: 'club',
      productName: 'Old name',
      formName: 'Bottle',
      unitPriceCents: 100,
      quantity: 3,
      lineTotalCents: 300,
    ),
  ],
);
StockMovement movement(DateTime date, String type, int quantity) =>
    StockMovement(
      id: 1,
      movementUuid: '$type-$quantity',
      productId: 10,
      type: type,
      quantityBase: quantity,
      createdAt: date,
      actorName: 'Staff',
    );
void main() {
  final day = DateTime(2025, 8, 6);
  test('sold forms aggregate by stable code and convert to first form', () {
    final rows = productQuantityReport(
      products: [product],
      sales: [sale(day)],
      movements: [],
      start: day,
      end: day,
    );
    expect(rows.single.soldBase, 27);
    expect(rows.single.name, 'Club');
    expect(
      productStockText(product, rows.single.soldBase),
      '1 Crate + 3 bottles (27 bottles)',
    );
  });
  test('inclusive end date; excludes voids and unposted or opening stock', () {
    final rows = productQuantityReport(
      products: [product],
      sales: [
        sale(day, voided: true),
        sale(day.subtract(const Duration(days: 1))),
      ],
      movements: [
        movement(DateTime(2025, 8, 6, 23, 59), 'restock', 50),
        movement(day, 'opening', 100),
        movement(day, 'sale_void', 24),
        movement(DateTime(2025, 8, 7), 'restock', 25),
      ],
      start: day,
      end: day,
    );
    expect(rows.single.soldBase, 0);
    expect(rows.single.receivedBase, 50);
  });
  test('historical products not in catalogue retain sales and names', () {
    final rows = productQuantityReport(
      products: [],
      sales: [sale(day)],
      movements: [],
      start: day,
      end: day,
    );
    expect(rows.single.product, isNull);
    expect(rows.single.name, 'Old name');
    expect(rows.single.soldBase, 27);
  });
  test('custom colour survives copying unrelated preferences', () {
    const preferences = InventoryPreferences(
      accent: AppAccentPreference.custom,
      customAccentArgb: 0xFF112233,
    );
    final copied = preferences.copyWith(theme: AppThemePreference.dark);
    expect(copied.customAccentArgb, 0xFF112233);
    expect(copied.accent, AppAccentPreference.custom);
  });
}
