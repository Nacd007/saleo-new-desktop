import 'dart:convert';
import 'dart:typed_data';

import 'package:csv/csv.dart';
import 'package:excel_community/excel_community.dart';
import 'package:file_picker/file_picker.dart';

import 'models.dart';

class StockReceiptExportService {
  const StockReceiptExportService();

  static const headers = [
    'date_time',
    'status',
    'supplier',
    'invoice_number',
    'product',
    'form',
    'quantity_forms',
    'units_per_form',
    'quantity_base',
    'purchase_cost',
    'batch_number',
    'expiry_date',
    'created_by',
    'reversal_reason',
  ];

  Uint8List csvBytes(List<StockReceipt> receipts) {
    final content = csv.encode([headers, ..._rows(receipts)]);
    return Uint8List.fromList(utf8.encode(content));
  }

  Uint8List excelBytes(List<StockReceipt> receipts) {
    final workbook = Excel.createExcel();
    final sheet = workbook['Receiving history'];
    sheet.appendRow(headers.map(TextCellValue.new).toList());
    for (final row in _rows(receipts)) {
      sheet.appendRow(
        row.map((value) {
          if (value is int) return IntCellValue(value);
          if (value is double) return DoubleCellValue(value);
          return TextCellValue(value.toString());
        }).toList(),
      );
    }
    workbook.delete('Sheet1');
    return Uint8List.fromList(workbook.encode()!);
  }

  Future<Uri?> saveCsv(List<StockReceipt> receipts) => FilePicker.saveFile(
    dialogTitle: 'Save Saleo receiving history',
    fileName: 'saleo-receiving-history.csv',
    bytes: csvBytes(receipts),
    mimeType: 'text/csv',
  );

  Future<Uri?> saveExcel(List<StockReceipt> receipts) => FilePicker.saveFile(
    dialogTitle: 'Save Saleo receiving history',
    fileName: 'saleo-receiving-history.xlsx',
    bytes: excelBytes(receipts),
    mimeType:
        'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
  );

  List<List<Object>> _rows(List<StockReceipt> receipts) => receipts
      .expand(
        (receipt) => receipt.items.map(
          (item) => <Object>[
            receipt.createdAt.toLocal().toIso8601String(),
            receipt.status.name,
            receipt.supplierName ?? '',
            receipt.invoiceNumber ?? '',
            item.productName,
            item.formName,
            item.quantityForms,
            item.unitsPerForm,
            item.quantityBase,
            item.purchaseCostCents == null ? '' : item.purchaseCostCents! / 100,
            item.batchNumber ?? '',
            item.expiryDate?.toIso8601String().split('T').first ?? '',
            receipt.createdBy,
            receipt.reversalReason ?? '',
          ],
        ),
      )
      .toList();
}
