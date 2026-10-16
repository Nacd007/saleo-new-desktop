import 'package:flutter/material.dart';

import 'app_controller.dart';
import 'desktop_period_filter.dart';
import 'formatters.dart';
import 'inventory_page.dart';
import 'models.dart';
import 'profit_calculator.dart';
import 'sales_report.dart';

/// Admin-only desktop planning calculator. Actual historical profit is withheld
/// until server-authoritative valuation and sale cost snapshots are available.
class ProfitPage extends StatefulWidget {
  const ProfitPage({super.key, required this.controller});
  final AppController controller;
  @override
  State<ProfitPage> createState() => _ProfitPageState();
}

class _ProfitPageState extends State<ProfitPage> {
  final _quantity = TextEditingController(text: '1');
  final _selling = TextEditingController();
  final _purchase = TextEditingController();
  final _discount = TextEditingController(text: '0');
  final _directCosts = TextEditingController(text: '0');
  int? _productId;
  int? _formId;
  bool _allStock = true;
  String _search = '';
  ReportPeriod _period = ReportPeriod.month;
  DateTimeRange? _customRange;
  String _costNote = 'Enter the purchase cost for the selected selling form.';

  @override
  void dispose() {
    for (final field in [
      _quantity,
      _selling,
      _purchase,
      _discount,
      _directCosts,
    ]) {
      field.dispose();
    }
    super.dispose();
  }

  void _select(Product product, SellingForm? form) {
    final reference = latestPurchaseReference(
      product.id,
      widget.controller.stockReceipts,
    );
    setState(() {
      _productId = product.id;
      _formId = form?.id;
      _selling.text = form == null
          ? ''
          : (form.priceCents / 100).toStringAsFixed(2);
      _purchase.text = reference == null || form == null
          ? ''
          : (referenceFormCost(reference, form) / 100).toStringAsFixed(2);
      _costNote = reference == null
          ? 'Cost missing: enter a verified purchase cost. Blank is not zero.'
          : 'Latest confirmed purchase price, converted to this form. '
                'This is a reference, not weighted-average inventory cost.';
    });
  }

  Widget _field(
    String label,
    TextEditingController field, {
    bool amount = true,
  }) => SizedBox(
    width: 220,
    child: TextField(
      controller: field,
      onChanged: (_) => setState(() {}),
      keyboardType: TextInputType.numberWithOptions(decimal: amount),
      decoration: InputDecoration(
        labelText: label,
        prefixText: amount ? 'GHS ' : null,
      ),
    ),
  );

  Widget _metric(String title, String value) => SizedBox(
    width: 220,
    child: Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title),
            const SizedBox(height: 6),
            Text(
              value,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    if (controller.currentUser?.role != UserRole.admin) {
      return const Center(
        child: Text('Profit is available to administrators only.'),
      );
    }
    final products =
        controller.products
            .where((p) => p.active || p.currentStock > 0)
            .toList()
          ..sort(
            (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
          );
    final selected = products.where((p) => p.id == _productId).firstOrNull;
    final forms =
        selected?.forms.where((f) => f.active && f.unitsPerForm > 0).toList() ??
        <SellingForm>[];
    final form = forms.where((f) => f.id == _formId).firstOrNull;
    final quantity = _allStock
        ? selected?.currentStock
        : int.tryParse(_quantity.text.trim());
    final selling = parseProfitMoney(_selling.text);
    final purchase = parseProfitMoney(_purchase.text);
    final discount = parseProfitMoney(_discount.text);
    final direct = parseProfitMoney(_directCosts.text);
    final calculation =
        quantity == null ||
            (_allStock && form == null) ||
            selling == null ||
            purchase == null ||
            discount == null ||
            direct == null
        ? null
        : ProfitCalculation(
            quantity: quantity,
            sellingPriceCents: selling,
            purchaseCostCents: purchase,
            discountCents: discount,
            directCostsCents: direct,
            unitsPerPricedForm: _allStock ? form!.unitsPerForm : 1,
          );
    final valid = calculation != null && calculation.isValid;
    final range = _customRange ?? desktopReportRange(_period, DateTime.now());
    final sales = controller.sales
        .where(
          (sale) => !sale.voided && desktopDateInRange(sale.createdAt, range),
        )
        .toList();
    final revenue = sales.fold<int>(0, (sum, sale) => sum + sale.totalCents);
    final choices = products
        .where(
          (p) =>
              p.id == _productId ||
              '${p.name} ${p.code} ${p.category}'.toLowerCase().contains(
                _search,
              ),
        )
        .toList();
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          spacing: 12,
          runSpacing: 8,
          children: [
            const Text(
              'Profit planner',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
            OutlinedButton.icon(
              icon: const Icon(Icons.warehouse_outlined, size: 18),
              label: const Text('Purchase costs in Inventory'),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => Scaffold(
                    appBar: AppBar(title: const Text('Inventory')),
                    body: InventoryPage(controller: controller),
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        const Text(
          'Estimate the profit from selling all remaining stock of one product, '
          'or enter a custom quantity. No stock or financial records are changed.',
        ),
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 460,
                  child: TextField(
                    onChanged: (value) =>
                        setState(() => _search = value.trim().toLowerCase()),
                    decoration: const InputDecoration(
                      labelText: 'Search products or categories',
                      prefixIcon: Icon(Icons.search),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    SizedBox(
                      width: 320,
                      child: DropdownButtonFormField<int>(
                        initialValue: selected?.id,
                        key: ValueKey('profit-product-${selected?.id}'),
                        isExpanded: true,
                        decoration: const InputDecoration(labelText: 'Product'),
                        items: choices
                            .map(
                              (p) => DropdownMenuItem(
                                value: p.id,
                                child: Text(
                                  p.name,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            )
                            .toList(),
                        onChanged: (id) {
                          final product = products
                              .where((p) => p.id == id)
                              .firstOrNull;
                          if (product != null) {
                            _select(
                              product,
                              product.forms
                                  .where((f) => f.active && f.unitsPerForm > 0)
                                  .firstOrNull,
                            );
                          }
                        },
                      ),
                    ),
                    SizedBox(
                      width: 220,
                      child: DropdownButtonFormField<int>(
                        initialValue: form?.id,
                        key: ValueKey(
                          'profit-form-${selected?.id}-${form?.id}',
                        ),
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'Selling form',
                        ),
                        items: forms
                            .map(
                              (f) => DropdownMenuItem(
                                value: f.id,
                                child: Text(
                                  f.name,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            )
                            .toList(),
                        onChanged: selected == null
                            ? null
                            : (id) => _select(
                                selected,
                                forms.where((f) => f.id == id).firstOrNull,
                              ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    ChoiceChip(
                      label: const Text('All stock for this product'),
                      selected: _allStock,
                      onSelected: (_) => setState(() => _allStock = true),
                    ),
                    ChoiceChip(
                      label: const Text('Custom quantity'),
                      selected: !_allStock,
                      onSelected: (_) => setState(() => _allStock = false),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                if (selected != null) ...[
                  Text(
                    'Available stock: ${productStockText(selected, selected.currentStock)}',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  if (_allStock && form != null)
                    Text(
                      'All ${selected.currentStock} single units are included. '
                      'Selling and purchase prices are per ${form.name} '
                      '(${form.unitsPerForm} single units). Loose units are priced '
                      'proportionally at this form’s rate, not at a separate retail rate.',
                    ),
                  if (_allStock && selected.currentStock <= 0)
                    const Text(
                      'There is no positive stock balance to estimate.',
                    ),
                  const SizedBox(height: 12),
                ],
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    if (!_allStock)
                      _field('Quantity of forms', _quantity, amount: false),
                    _field('Selling price per form', _selling),
                    _field('Purchase cost per form', _purchase),
                    _field('Total sales discount', _discount),
                    _field('Total direct acquisition costs', _directCosts),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  purchase == null
                      ? _costNote
                      : 'Using the purchase cost shown above as an estimate. '
                            'It is not a verified weighted-average inventory valuation.',
                ),
                const Text(
                  'Add acquisition costs only if not already included in purchase cost. '
                  'Use comparable tax-exclusive amounts where applicable.',
                ),
                const SizedBox(height: 16),
                if (valid)
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _metric(
                        _allStock
                            ? 'Estimated stock revenue'
                            : 'Net sales amount',
                        'GHS ${money(calculation.revenueCents)}',
                      ),
                      _metric(
                        _allStock ? 'Estimated stock cost' : 'Cost of goods',
                        'GHS ${money(calculation.goodsCostCents)}',
                      ),
                      _metric(
                        calculation.grossProfitCents < 0
                            ? 'Estimated gross loss'
                            : _allStock
                            ? 'Estimated total stock profit'
                            : 'Estimated gross profit',
                        'GHS ${money(calculation.grossProfitCents)}',
                      ),
                      _metric(
                        'Gross margin',
                        calculation.marginPercent == null
                            ? 'Not applicable'
                            : '${calculation.marginPercent!.toStringAsFixed(1)}%',
                      ),
                    ],
                  )
                else
                  const Text(
                    'Enter valid amounts and a positive whole quantity. '
                    'Maximum quantity: 1,000,000 forms; amounts below GHS 1 billion. '
                    'Discount cannot exceed the selling total.',
                  ),
                const SizedBox(height: 8),
                const Text(
                  'Planning estimate only. Rent, wages and other operating expenses '
                  'are not included; this is not net profit.',
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Recorded sales — not a profit statement',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                DesktopPeriodFilter(
                  period: _period,
                  customRange: _customRange,
                  onChanged: (period, custom) => setState(() {
                    _period = period;
                    _customRange = custom;
                  }),
                ),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _metric('Sales revenue', 'GHS ${money(revenue)}'),
                    _metric('Transactions', '${sales.length}'),
                    _metric('Historical gross profit', 'Cost data unavailable'),
                  ],
                ),
                const SizedBox(height: 8),
                const Text(
                  'Credit sales are included once; debt repayments are not new sales. '
                  'Voided sales are excluded. Historical profit requires saved sale costs '
                  'and a reconciled inventory valuation ledger.',
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
