import 'dart:typed_data';

import 'package:excel_community/excel_community.dart';
import 'package:file_picker/file_picker.dart';

import 'models.dart';
import 'product_import_service.dart';

class ProductExportService {
  const ProductExportService();

  Uint8List excelBytes(List<Product> products) {
    final workbook = Excel.createExcel();
    final sheet = workbook['Products'];
    sheet.appendRow(
      ProductImportService.sampleHeaders.map(TextCellValue.new).toList(),
    );
    for (final product in products) {
      final forms = product.forms.isEmpty ? [null] : product.forms;
      for (final form in forms) {
        sheet.appendRow([
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
    workbook.delete('Sheet1');
    return Uint8List.fromList(workbook.encode()!);
  }

  Future<Uri?> saveExcel(List<Product> products) => FilePicker.saveFile(
    dialogTitle: 'Save Saleo products',
    fileName: 'saleo-products-export.xlsx',
    bytes: excelBytes(products),
    mimeType:
        'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
  );
}
