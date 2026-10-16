import 'models.dart';

/// Parses non-negative GHS amounts without binary floating-point rounding.
/// Accepts 11000, 11,000 and 11,000.50; rejects malformed grouping.
int? parseProfitMoney(String text) {
  final value = text.trim();
  if (!RegExp(r'^(?:\d+|\d{1,3}(?:,\d{3})+)(?:\.\d{1,2})?$').hasMatch(value)) {
    return null;
  }
  final parts = value.replaceAll(',', '').split('.');
  final whole = int.tryParse(parts.first);
  if (whole == null || whole > 999999999) return null;
  return whole * 100 +
      (parts.length == 1 ? 0 : int.parse(parts[1].padRight(2, '0')));
}

class ProfitCalculation {
  const ProfitCalculation({
    required this.quantity,
    required this.sellingPriceCents,
    required this.purchaseCostCents,
    this.discountCents = 0,
    this.directCostsCents = 0,
    this.unitsPerPricedForm = 1,
  });

  final int quantity;
  final int sellingPriceCents;
  final int purchaseCostCents;
  final int discountCents;
  final int directCostsCents;

  /// Quantity is base units in stock mode; prices remain per selling form.
  /// Keep the ratio intact and round totals once, not each single unit.
  final int unitsPerPricedForm;

  int _pricedTotal(int cents) => unitsPerPricedForm <= 0
      ? 0
      : (quantity * cents + unitsPerPricedForm ~/ 2) ~/ unitsPerPricedForm;

  bool get isValid =>
      quantity > 0 &&
      quantity <= 1000000 &&
      unitsPerPricedForm > 0 &&
      sellingPriceCents >= 0 &&
      purchaseCostCents >= 0 &&
      discountCents >= 0 &&
      directCostsCents >= 0 &&
      discountCents <= _pricedTotal(sellingPriceCents);
  int get revenueCents => _pricedTotal(sellingPriceCents) - discountCents;
  int get goodsCostCents => _pricedTotal(purchaseCostCents) + directCostsCents;
  int get grossProfitCents => revenueCents - goodsCostCents;
  double? get marginPercent =>
      revenueCents == 0 ? null : grossProfitCents * 100 / revenueCents;
}

/// A purchase-price reference, NOT current inventory valuation or sale COGS.
/// Missing costs are never converted to zero. Ignore drafts/reversed receipts.
StockReceiptItem? latestPurchaseReference(
  int productId,
  List<StockReceipt> receipts,
) {
  final confirmed =
      receipts
          .where((receipt) => receipt.status == StockReceiptStatus.confirmed)
          .toList()
        ..sort(
          (a, b) => (b.confirmedAt ?? b.createdAt).compareTo(
            a.confirmedAt ?? a.createdAt,
          ),
        );
  for (final receipt in confirmed) {
    final items = receipt.items.where((item) => item.productId == productId);
    if (items.isNotEmpty) {
      // A later delivery with no known cost must not fall back to an old price.
      final item = items.last;
      return item.purchaseCostCents == null ||
              item.purchaseCostCents! < 0 ||
              item.unitsPerForm <= 0
          ? null
          : item;
    }
  }
  return null;
}

/// Converts a reference price to another form, rounding only at form level.
int referenceFormCost(StockReceiptItem item, SellingForm form) =>
    (item.purchaseCostCents! * form.unitsPerForm + item.unitsPerForm ~/ 2) ~/
    item.unitsPerForm;
