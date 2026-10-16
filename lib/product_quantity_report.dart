import 'models.dart';

class ProductQuantityRow {
  const ProductQuantityRow({
    required this.code,
    required this.name,
    required this.product,
    required this.soldBase,
    required this.receivedBase,
  });
  final String code;
  final String name;
  final Product? product;
  final int soldBase;
  final int receivedBase;
}

/// Closed calendar dates, using local time. Receipts pending approval do not
/// appear: only posted restock movements count as received purchases.
List<ProductQuantityRow> productQuantityReport({
  required List<Product> products,
  required List<Sale> sales,
  required List<StockMovement> movements,
  required DateTime start,
  required DateTime end,
}) {
  final from = DateTime(start.year, start.month, start.day);
  final until = DateTime(end.year, end.month, end.day + 1);
  final now = DateTime.now();
  bool included(DateTime date) {
    final local = date.toLocal();
    return !local.isBefore(from) &&
        local.isBefore(until) &&
        !local.isAfter(now);
  }

  final byCode = {for (final p in products) p.code.trim().toUpperCase(): p};
  final byId = {for (final p in products) p.id: p};
  final sold = <String, int>{};
  final received = <String, int>{};
  final names = <String, String>{};
  for (final sale in sales.where((s) => !s.voided && included(s.createdAt))) {
    for (final item in sale.items) {
      final code = item.productCode.trim().toUpperCase();
      sold.update(
        code,
        (n) => n + item.quantity * item.unitsPerForm,
        ifAbsent: () => item.quantity * item.unitsPerForm,
      );
      names[code] = item.productName;
    }
  }
  for (final movement in movements.where(
    (m) => m.type == 'restock' && m.quantityBase > 0 && included(m.createdAt),
  )) {
    final product = byId[movement.productId];
    if (product == null) continue;
    final code = product.code.trim().toUpperCase();
    received.update(
      code,
      (n) => n + movement.quantityBase,
      ifAbsent: () => movement.quantityBase,
    );
    names[code] = product.name;
  }
  final rows = <ProductQuantityRow>[
    for (final code in {...sold.keys, ...received.keys})
      ProductQuantityRow(
        code: code,
        name: byCode[code]?.name ?? names[code] ?? code,
        product: byCode[code],
        soldBase: sold[code] ?? 0,
        receivedBase: received[code] ?? 0,
      ),
  ];
  rows.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  return rows;
}
