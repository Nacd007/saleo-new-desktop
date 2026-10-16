import 'dart:convert';
import 'dart:typed_data';

import 'package:excel_community/excel_community.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saleo_app/inventory_export_service.dart';
import 'package:saleo_app/models.dart';
import 'package:saleo_app/product_export_service.dart';
import 'package:saleo_app/product_import_service.dart';

void main() {
  const importer = ProductImportService();

  test('reads valid CSV product rows', () {
    final bytes = Uint8List.fromList(
      utf8.encode(
        'product_name,product_code,category,selling_form,price\n'
        'Mineral Water,WTR-1,Drinks,Carton,48.50\n',
      ),
    );

    final result = importer.parse(bytes, 'csv');

    expect(result.errors, isEmpty);
    expect(result.rows, hasLength(1));
    expect(result.rows.single.code, 'WTR-1');
    expect(result.rows.single.priceCents, 4850);
  });

  test('reads valid Excel product rows', () {
    final workbook = Excel.createExcel();
    final sheet = workbook['Sheet1'];
    sheet.appendRow(
      [
        'product_name',
        'product_code',
        'category',
        'selling_form',
        'price',
      ].map(TextCellValue.new).toList(),
    );
    sheet.appendRow([
      TextCellValue('Cooking Oil'),
      TextCellValue('OIL-1'),
      TextCellValue('Groceries'),
      TextCellValue('Bottle'),
      DoubleCellValue(32.75),
    ]);
    final bytes = Uint8List.fromList(workbook.encode()!);

    final result = importer.parse(bytes, 'xlsx');

    expect(result.errors, isEmpty);
    expect(result.rows, hasLength(1));
    expect(result.rows.single.name, 'Cooking Oil');
    expect(result.rows.single.priceCents, 3275);
  });

  test('blocks incomplete spreadsheets before import', () {
    final bytes = Uint8List.fromList(utf8.encode('name,price\nRice,25'));

    final result = importer.parse(bytes, 'csv');

    expect(result.canImport, isFalse);
    expect(result.errors.single, contains('Missing columns'));
  });

  test('downloadable CSV sample includes stock and box conversion fields', () {
    final result = importer.parse(importer.sampleCsv(), 'csv');

    expect(result.errors, isEmpty);
    expect(result.rows, hasLength(4));
    final alomoBox = result.rows.first;
    expect(alomoBox.code, 'ALO-001');
    expect(alomoBox.baseUnit, 'pack');
    expect(alomoBox.openingStockBase, 90);
    expect(alomoBox.unitsPerForm, 10);
    // Alert levels are entered in the first selling form (20 boxes x 10 packs).
    expect(alomoBox.lowStockThreshold, 200);
  });

  test('downloadable Excel sample can be opened and imported', () {
    final bytes = importer.sampleExcel();
    final result = importer.parse(bytes, 'xlsx');

    expect(bytes, isNotEmpty);
    expect(result.errors, isEmpty);
    expect(result.rows.map((row) => row.form), containsAll(['Box', 'Pack']));
  });

  test('product export can be imported back with statuses', () {
    const products = [
      Product(
        id: 1,
        name: 'Rice',
        code: 'RICE-1',
        category: 'Food',
        active: false,
        baseUnit: 'small bag',
        currentStock: 500,
        lowStockThreshold: 25,
        forms: [
          SellingForm(
            id: 1,
            productId: 1,
            name: 'Big bag',
            priceCents: 10000,
            active: true,
            unitsPerForm: 5,
          ),
          SellingForm(
            id: 2,
            productId: 1,
            name: 'Small bag',
            priceCents: 2200,
            active: false,
          ),
        ],
      ),
    ];

    final exported = const ProductExportService().excelBytes(products);
    final result = importer.parse(exported, 'xlsx');

    expect(result.errors, isEmpty);
    expect(result.rows, hasLength(2));
    expect(result.rows.first.openingStockBase, 500);
    expect(result.rows.first.unitsPerForm, 5);
    expect(result.rows.first.productActive, isFalse);
    expect(result.rows.first.formActive, isTrue);
    expect(result.rows.last.formActive, isFalse);
  });

  test('inventory export includes importable products sheet', () {
    const products = [
      Product(
        id: 1,
        name: 'Full Product',
        code: 'FULL-10',
        category: 'General',
        active: true,
        baseUnit: 'piece',
        currentStock: 200,
        lowStockThreshold: 20,
        forms: [
          SellingForm(
            id: 1,
            productId: 1,
            name: 'Full',
            priceCents: 10000,
            active: true,
            unitsPerForm: 10,
          ),
          SellingForm(
            id: 2,
            productId: 1,
            name: 'Half',
            priceCents: 5500,
            active: true,
            unitsPerForm: 5,
          ),
          SellingForm(
            id: 3,
            productId: 1,
            name: 'Single',
            priceCents: 600,
            active: true,
          ),
        ],
      ),
    ];

    final exported = const InventoryExportService().excelBytes(products);
    final result = importer.parse(exported, 'xlsx');

    expect(result.errors, isEmpty);
    expect(
      result.rows.map((row) => row.form),
      containsAll(['Full', 'Half', 'Single']),
    );
    expect(result.rows.first.openingStockBase, 200);
  });
}
