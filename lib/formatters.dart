import 'package:intl/intl.dart';

import 'models.dart';

final _money = NumberFormat.currency(symbol: '', decimalDigits: 2);
final _dateTime = DateFormat('dd MMM yyyy, HH:mm');

String money(int cents) => _money.format(cents / 100).trim();
String saleDate(DateTime value) => _dateTime.format(value.toLocal());

String productStockText(Product product, int quantity) {
  if (quantity < 0) return '-${productStockText(product, -quantity)}';
  final base = _pluralStock(product.baseUnit, quantity);
  if (quantity == 0 || product.forms.isEmpty) return '$quantity $base';
  final primary = product.forms.first;
  if (primary.unitsPerForm <= 1) return '$quantity $base';
  final formCount = quantity ~/ primary.unitsPerForm;
  final remainder = quantity % primary.unitsPerForm;
  final parts = <String>[];
  if (formCount > 0) {
    parts.add('$formCount ${_pluralStock(primary.name, formCount)}');
  }
  if (remainder > 0 || parts.isEmpty) {
    parts.add('$remainder ${_pluralStock(product.baseUnit, remainder)}');
  }
  return '${parts.join(' + ')} ($quantity $base)';
}

String _pluralStock(String value, int count) {
  if (count == 1) return value;
  final lower = value.toLowerCase();
  if (lower.endsWith('s')) return value;
  if (lower.endsWith('x') || lower.endsWith('ch')) return '${value}es';
  return '${value}s';
}
