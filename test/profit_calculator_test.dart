import 'package:flutter_test/flutter_test.dart';
import 'package:saleo_app/models.dart';
import 'package:saleo_app/profit_calculator.dart';

void main() {
  test('all stock estimate includes full crates and loose units', () {
    const result = ProfitCalculation(
      quantity: 252,
      unitsPerPricedForm: 24,
      sellingPriceCents: 26000,
      purchaseCostCents: 23000,
    );
    expect(result.isValid, isTrue);
    expect(result.revenueCents, 273000);
    expect(result.goodsCostCents, 241500);
    expect(result.grossProfitCents, 31500);
  });
  test(
    'stock estimate rounds totals once and applies total adjustments once',
    () {
      const result = ProfitCalculation(
        quantity: 3,
        unitsPerPricedForm: 24,
        sellingPriceCents: 10000,
        purchaseCostCents: 8000,
        discountCents: 50,
        directCostsCents: 100,
      );
      expect(result.revenueCents, 1200);
      expect(result.goodsCostCents, 1100);
      expect(result.grossProfitCents, 100);
    },
  );
  test('invalid or empty stock does not produce a profit estimate', () {
    for (final quantity in [0, -1]) {
      expect(
        ProfitCalculation(
          quantity: quantity,
          sellingPriceCents: 26000,
          purchaseCostCents: 23000,
          unitsPerPricedForm: 24,
        ).isValid,
        isFalse,
      );
    }
    expect(
      const ProfitCalculation(
        quantity: 10,
        sellingPriceCents: 26000,
        purchaseCostCents: 23000,
        unitsPerPricedForm: 0,
      ).isValid,
      isFalse,
    );
    expect(
      const ProfitCalculation(
        quantity: 1,
        sellingPriceCents: 2400,
        purchaseCostCents: 2300,
        unitsPerPricedForm: 24,
        discountCents: 101,
      ).isValid,
      isFalse,
    );
  });
  test('money parsing preserves cents and validates comma grouping', () {
    expect(parseProfitMoney('11,000.50'), 1100050);
    expect(parseProfitMoney('7,000'), 700000);
    expect(parseProfitMoney('0.01'), 1);
    expect(parseProfitMoney('0'), 0);
    for (final invalid in [
      '',
      '-2',
      'NaN',
      '1,00',
      '1.234',
      '1e3',
      '99999999999999999999999999999999',
    ]) {
      expect(parseProfitMoney(invalid), isNull);
    }
  });
  test('profit, discount and margin use the same quantity and cost basis', () {
    const result = ProfitCalculation(
      quantity: 10,
      sellingPriceCents: 20000,
      purchaseCostCents: 15000,
      discountCents: 10000,
      directCostsCents: 5000,
    );
    expect(result.isValid, isTrue);
    expect(result.revenueCents, 190000);
    expect(result.goodsCostCents, 155000);
    expect(result.grossProfitCents, 35000);
    expect(result.marginPercent, closeTo(18.4210526, .00001));
  });
  test('losses remain negative and zero revenue has no margin', () {
    const loss = ProfitCalculation(
      quantity: 1,
      sellingPriceCents: 100,
      purchaseCostCents: 200,
    );
    expect(loss.grossProfitCents, -100);
    const free = ProfitCalculation(
      quantity: 1,
      sellingPriceCents: 0,
      purchaseCostCents: 200,
    );
    expect(free.marginPercent, isNull);
    const invalid = ProfitCalculation(
      quantity: 1,
      sellingPriceCents: 100,
      purchaseCostCents: 20,
      discountCents: 101,
    );
    expect(invalid.isValid, isFalse);
  });
  test('form conversion rounds once, not separately for every bottle', () {
    const reference = StockReceiptItem(
      id: 1,
      receiptId: 1,
      productId: 1,
      productName: 'Drink',
      formName: 'Crate',
      quantityForms: 1,
      unitsPerForm: 24,
      quantityBase: 24,
      purchaseCostCents: 10000,
    );
    const half = SellingForm(
      id: 1,
      productId: 1,
      name: 'Half crate',
      priceCents: 7000,
      active: true,
      unitsPerForm: 12,
    );
    expect(referenceFormCost(reference, half), 5000);
  });
  test('unknown later costs do not silently reuse old purchase prices', () {
    StockReceipt receipt(int id, int? cost, StockReceiptStatus status) =>
        StockReceipt(
          id: id,
          receiptUuid: 'receipt-$id',
          status: status,
          createdAt: DateTime(2026, 10, id),
          createdBy: 'Admin',
          items: [
            StockReceiptItem(
              id: id,
              receiptId: id,
              productId: 1,
              productName: 'Drink',
              formName: 'Crate',
              quantityForms: 1,
              unitsPerForm: 24,
              quantityBase: 24,
              purchaseCostCents: cost,
            ),
          ],
        );
    final old = receipt(1, 10000, StockReceiptStatus.confirmed);
    expect(latestPurchaseReference(1, [old])?.purchaseCostCents, 10000);
    expect(
      latestPurchaseReference(1, [
        old,
        receipt(2, null, StockReceiptStatus.confirmed),
      ]),
      isNull,
    );
    expect(
      latestPurchaseReference(1, [
        old,
        receipt(3, 15000, StockReceiptStatus.draft),
      ])?.purchaseCostCents,
      10000,
    );
    expect(
      latestPurchaseReference(1, [
        old,
        receipt(3, 15000, StockReceiptStatus.reversed),
      ])?.purchaseCostCents,
      10000,
    );
  });
}
