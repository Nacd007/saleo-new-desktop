import 'package:csv/csv.dart';
import 'package:excel_community/excel_community.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saleo_app/company_id_image_service.dart';
import 'package:saleo_app/models.dart';
import 'package:saleo_app/stock_receipt_export_service.dart';

void main() {
  testWidgets('company ID picture is rendered as a PNG', (tester) async {
    final bytes = await tester.runAsync(
      () => const CompanyIdImageService().createPng(
        companyName: 'Akwaaba Wholesale',
        companyId: 'AW-7K4P9',
      ),
    );
    expect(bytes, isNotNull);
    expect(bytes!.length, greaterThan(10000));
    expect(bytes.take(8).toList(), [137, 80, 78, 71, 13, 10, 26, 10]);
  });

  test('receipt template keeps customer phone and staff wording settings', () {
    const template = ReceiptTemplate(
      shopName: 'Akwaaba Wholesale',
      operatorLabel: 'Served by',
      useStaffRole: true,
      showCustomerPhone: true,
    );
    final restored = ReceiptTemplate.fromJson(
      template.toJson(),
      companyName: 'Akwaaba Wholesale',
    );
    expect(restored.operatorLabel, 'Served by');
    expect(restored.useStaffRole, isTrue);
    expect(restored.showCustomerPhone, isTrue);
  });

  test('receiving history exports readable CSV and Excel rows', () {
    final receipt = StockReceipt(
      id: 1,
      receiptUuid: 'receipt-12345678',
      status: StockReceiptStatus.confirmed,
      supplierName: 'Ghana Supplier',
      invoiceNumber: 'INV-100',
      createdAt: DateTime.utc(2026, 9, 14, 10),
      confirmedAt: DateTime.utc(2026, 9, 14, 10),
      createdBy: 'Administrator',
      items: [
        StockReceiptItem(
          id: 1,
          receiptId: 1,
          productId: 1,
          productName: 'Mineral Water',
          formName: 'Box',
          quantityForms: 2,
          unitsPerForm: 24,
          quantityBase: 48,
          purchaseCostCents: 8000,
          batchNumber: 'B-1',
        ),
      ],
    );
    const service = StockReceiptExportService();
    final csvRows = csv.decode(
      String.fromCharCodes(service.csvBytes([receipt])),
    );
    expect(csvRows.length, 2);
    expect(csvRows[1][4], 'Mineral Water');
    expect(csvRows[1][8].toString(), '48');

    final workbook = Excel.decodeBytes(service.excelBytes([receipt]));
    final sheet = workbook.tables['Receiving history'];
    expect(sheet, isNotNull);
    expect(sheet!.maxRows, 2);
    expect(sheet.rows[1][4]?.value.toString(), contains('Mineral Water'));
  });
}
