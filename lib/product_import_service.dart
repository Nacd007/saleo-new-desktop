import 'dart:convert';
import 'dart:typed_data';

import 'package:csv/csv.dart';
import 'package:excel_community/excel_community.dart';

class ProductImportRow {
  const ProductImportRow({
    required this.rowNumber,
    required this.name,
    required this.code,
    required this.category,
    required this.form,
    required this.priceCents,
    this.baseUnit = 'unit',
    this.openingStockBase = 0,
    this.unitsPerForm = 1,
    this.lowStockThreshold = 0,
    this.productActive = true,
    this.formActive = true,
  });

  final int rowNumber;
  final String name;
  final String code;
  final String category;
  final String form;
  final int priceCents;
  final String baseUnit;
  final int openingStockBase;
  final int unitsPerForm;
  final int lowStockThreshold;
  final bool productActive;
  final bool formActive;
}

class ProductImportResult {
  const ProductImportResult({required this.rows, required this.errors});
  final List<ProductImportRow> rows;
  final List<String> errors;
  bool get canImport => rows.isNotEmpty && errors.isEmpty;
}

class ProductImportService {
  const ProductImportService();

  static const sampleHeaders = [
    'product_name',
    'product_code',
    'category',
    'base_unit',
    'opening_stock',
    'selling_form',
    'units_per_form',
    'price',
    'low_stock_threshold',
    'product_status',
    'form_status',
  ];

  static const sampleRows = [
    [
      'Alomo Sachet',
      'ALO-001',
      'Drinks',
      'pack',
      90,
      'Box',
      10,
      120.00,
      20,
      'Active',
      'Active',
    ],
    [
      'Alomo Sachet',
      'ALO-001',
      'Drinks',
      'pack',
      90,
      'Pack',
      1,
      12.50,
      20,
      'Active',
      'Active',
    ],
    [
      'Mineral Water',
      'WTR-001',
      'Drinks',
      'bottle',
      144,
      'Box',
      24,
      96.00,
      24,
      'Active',
      'Active',
    ],
    [
      'Mineral Water',
      'WTR-001',
      'Drinks',
      'bottle',
      144,
      'Bottle',
      1,
      4.50,
      24,
      'Active',
      'Active',
    ],
  ];

  Uint8List sampleCsv() {
    final content = csv.encode([sampleHeaders, ...sampleRows]);
    return Uint8List.fromList(utf8.encode(content));
  }

  Uint8List sampleExcel() {
    final workbook = Excel.createExcel();
    final sheet = workbook['Products'];
    sheet.appendRow(sampleHeaders.map(TextCellValue.new).toList());
    for (final row in sampleRows) {
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

  ProductImportResult parse(Uint8List bytes, String extension) {
    final table = extension.toLowerCase() == 'csv'
        ? csv.decode(utf8.decode(bytes, allowMalformed: false))
        : _excelRows(bytes);
    if (table.isEmpty) {
      return const ProductImportResult(
        rows: [],
        errors: ['The selected file is empty.'],
      );
    }

    final headers = table.first
        .map(
          (value) => _text(value).toLowerCase().replaceAll(RegExp(r'\s+'), '_'),
        )
        .toList();
    const required = [
      'product_name',
      'product_code',
      'category',
      'selling_form',
      'price',
    ];
    final missing = required.where((name) => !headers.contains(name)).toList();
    if (missing.isNotEmpty) {
      return ProductImportResult(
        rows: const [],
        errors: ['Missing columns: ${missing.join(', ')}.'],
      );
    }

    final imported = <ProductImportRow>[];
    final errors = <String>[];
    final seenForms = <String>{};
    final primaryUnitsByCode = <String, int>{};
    for (var index = 1; index < table.length; index++) {
      final values = table[index];
      if (values.every((value) => _text(value).isEmpty)) continue;
      String cell(String header) {
        final position = headers.indexOf(header);
        return position >= 0 && position < values.length
            ? _text(values[position])
            : '';
      }

      final name = cell('product_name');
      final code = cell('product_code').toUpperCase();
      final category = cell('category');
      final form = cell('selling_form');
      final price = double.tryParse(cell('price').replaceAll(',', ''));
      final baseUnit = cell('base_unit').isEmpty
          ? form.toLowerCase()
          : cell('base_unit').toLowerCase();
      final openingStock = int.tryParse(cell('opening_stock')) ?? 0;
      final unitsPerForm = int.tryParse(cell('units_per_form')) ?? 1;
      final lowStockThreshold = int.tryParse(cell('low_stock_threshold')) ?? 0;
      final productActive = _status(cell('product_status'));
      final formActive = _status(cell('form_status'));
      final rowNumber = index + 1;
      if ([name, code, category, form].any((value) => value.isEmpty) ||
          price == null ||
          price <= 0 ||
          openingStock < 0 ||
          unitsPerForm < 1 ||
          lowStockThreshold < 0) {
        errors.add('Row $rowNumber has a missing or invalid value.');
        continue;
      }
      final key = '$code:${form.toLowerCase()}';
      if (!seenForms.add(key)) {
        errors.add('Row $rowNumber duplicates $code / $form.');
        continue;
      }
      imported.add(
        ProductImportRow(
          rowNumber: rowNumber,
          name: name,
          code: code,
          category: category,
          form: form,
          priceCents: (price * 100).round(),
          baseUnit: baseUnit,
          openingStockBase: openingStock,
          unitsPerForm: unitsPerForm,
          lowStockThreshold:
              lowStockThreshold *
              primaryUnitsByCode.putIfAbsent(code, () => unitsPerForm),
          productActive: productActive,
          formActive: formActive,
        ),
      );
    }
    return ProductImportResult(rows: imported, errors: errors);
  }

  List<List<dynamic>> _excelRows(Uint8List bytes) {
    final workbook = Excel.decodeBytes(bytes);
    if (workbook.tables.isEmpty) return const [];
    return workbook.tables.values.first.rows
        .map((row) => row.map((cell) => cell?.value).toList())
        .toList();
  }

  String _text(dynamic value) {
    if (value == null) return '';
    final text = value.toString().trim();
    final match = RegExp(r'^[A-Za-z]+CellValue\((.*)\)$').firstMatch(text);
    return (match?.group(1) ?? text).trim();
  }

  bool _status(String value) {
    final normalized = value.trim().toLowerCase();
    if (normalized.isEmpty) return true;
    return !['inactive', 'off', 'false', '0', 'no'].contains(normalized);
  }
}
