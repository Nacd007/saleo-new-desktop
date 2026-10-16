import 'dart:typed_data';

import 'package:excel_community/excel_community.dart';
import 'package:file_picker/file_picker.dart';

import 'formatters.dart';
import 'models.dart';
import 'product_import_service.dart';

class InventoryExportService {
  const InventoryExportService();

  Uint8List excelBytes(List<Product> products) {
    final workbook = Excel.createExcel();
    final productsSheet = workbook['Products'];
    productsSheet.appendRow(
      ProductImportService.sampleHeaders.map(TextCellValue.new).toList(),
    );
    for (final product in products) {
      final forms = product.forms.isEmpty ? [null] : product.forms;
      for (final form in forms) {
        productsSheet.appendRow([
          TextCellValue(product.name),
          TextCellValue(product.code),
          TextCellValue(product.category),
          TextCellValue(product.baseUnit),
          IntCellValue(product.currentStock),
          TextCellValue(form?.name ?? ''),
          IntCellValue(form?.unitsPerForm ?? 1),
          DoubleCellValue(form == null ? 0 : form.priceCents / 100),
          IntCellValue(product.lowStockThreshold),
          TextCellValue(product.active ? 'Active' : 'Inactive'),
          TextCellValue(
            form == null
                ? ''
                : form.active
                ? 'Active'
                : 'Inactive',
          ),
        ]);
      }
    }

    final inventory = workbook['Inventory'];
    inventory.appendRow(
      [
        'store',
        'product_code',
        'product_name',
        'category',
        'base_unit',
        'current_stock',
        'low_stock_threshold',
        'product_status',
        'selling_form',
        'units_per_form',
        'price',
        'form_status',
      ].map(TextCellValue.new).toList(),
    );

    for (final product in products) {
      final forms = product.forms.isEmpty ? [null] : product.forms;
      for (final form in forms) {
        inventory.appendRow([
          TextCellValue('Current store'),
          TextCellValue(product.code),
          TextCellValue(product.name),
          TextCellValue(product.category),
          TextCellValue(product.baseUnit),
          IntCellValue(product.currentStock),
          IntCellValue(product.lowStockThreshold),
          TextCellValue(product.active ? 'Active' : 'Inactive'),
          TextCellValue(form?.name ?? ''),
          IntCellValue(form?.unitsPerForm ?? 0),
          TextCellValue(form == null ? '' : money(form.priceCents)),
          TextCellValue(
            form == null
                ? ''
                : form.active
                ? 'Active'
                : 'Inactive',
          ),
        ]);
      }
    }

    final lowStock = workbook['Low stock'];
    lowStock.appendRow(
      [
        'store',
        'product_code',
        'product_name',
        'current_stock',
        'low_stock_threshold',
        'base_unit',
      ].map(TextCellValue.new).toList(),
    );
    for (final product in products.where((product) => product.isLowStock)) {
      lowStock.appendRow([
        TextCellValue('Current store'),
        TextCellValue(product.code),
        TextCellValue(product.name),
        IntCellValue(product.currentStock),
        IntCellValue(product.lowStockThreshold),
        TextCellValue(product.baseUnit),
      ]);
    }

    workbook.delete('Sheet1');
    return Uint8List.fromList(workbook.encode()!);
  }

  Future<Uri?> saveExcel(List<Product> products) => FilePicker.saveFile(
    dialogTitle: 'Save Saleo inventory export',
    fileName: 'saleo-inventory-export.xlsx',
    bytes: excelBytes(products),
    mimeType:
        'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
  );
}
