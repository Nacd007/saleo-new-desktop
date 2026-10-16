import 'package:flutter/material.dart';

import 'app_controller.dart';
import 'formatters.dart';
import 'models.dart';

class ProductPerformanceCard extends StatefulWidget {
  const ProductPerformanceCard({super.key, required this.controller});

  final AppController controller;

  @override
  State<ProductPerformanceCard> createState() => _ProductPerformanceCardState();
}

class _ProductPerformanceCardState extends State<ProductPerformanceCard> {
  ProductPerformancePeriod _period = ProductPerformancePeriod.today;
  ProductPerformanceView _view = ProductPerformanceView.highMovers;
  String _category = 'All categories';
  bool _rankByQuantity = true;

  @override
  Widget build(BuildContext context) {
    final categories =
        widget.controller.products
            .map((product) => product.category.trim())
            .where((category) => category.isNotEmpty)
            .toSet()
            .toList()
          ..sort();
    if (_category != 'All categories' && !categories.contains(_category)) {
      _category = 'All categories';
    }
    final productById = {
      for (final product in widget.controller.products) product.id: product,
    };
    final productByName = {
      for (final product in widget.controller.products) product.name: product,
    };
    final start = _periodStart(_period);
    final stats = <String, _ProductPerformanceData>{};
    for (final sale in widget.controller.sales) {
      if (sale.voided ||
          sale.createdAt.toLocal().isBefore(start) ||
          sale.createdAt.isAfter(DateTime.now())) {
        continue;
      }
      for (final item in sale.items) {
        final product =
            productById[item.productId] ?? productByName[item.productName];
        if (_category != 'All categories' && product?.category != _category) {
          continue;
        }
        final row = stats.putIfAbsent(
          item.productName,
          () => _ProductPerformanceData(product: product),
        );
        row.quantityBase += item.quantity * item.unitsPerForm;
        row.revenueCents += item.lineTotalCents;
        row.saleIds.add(sale.id);
      }
    }
    if (_view != ProductPerformanceView.highMovers) {
      for (final product in widget.controller.products.where(
        (product) =>
            product.active &&
            (_category == 'All categories' || product.category == _category),
      )) {
        stats.putIfAbsent(
          product.name,
          () => _ProductPerformanceData(product: product),
        );
      }
    }
    final rows = stats.entries.toList();
    int compare(
      MapEntry<String, _ProductPerformanceData> a,
      MapEntry<String, _ProductPerformanceData> b,
    ) {
      final left = _rankByQuantity
          ? a.value.quantityBase
          : a.value.revenueCents;
      final right = _rankByQuantity
          ? b.value.quantityBase
          : b.value.revenueCents;
      return right.compareTo(left);
    }

    rows.sort(compare);
    if (_view == ProductPerformanceView.lowMovers) {
      rows.sort((a, b) => compare(b, a));
    }
    final visibleRows = _view == ProductPerformanceView.all
        ? rows
        : rows.take(8).toList();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: ProductPerformancePeriod.values
                  .map(
                    (period) => ChoiceChip(
                      label: Text(_periodLabel(period)),
                      selected: _period == period,
                      onSelected: (_) => setState(() => _period = period),
                    ),
                  )
                  .toList(),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                SizedBox(
                  width: 210,
                  child: DropdownButtonFormField<ProductPerformanceView>(
                    initialValue: _view,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Movement',
                      isDense: true,
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: ProductPerformanceView.highMovers,
                        child: Text('High movers'),
                      ),
                      DropdownMenuItem(
                        value: ProductPerformanceView.lowMovers,
                        child: Text('Low movers'),
                      ),
                      DropdownMenuItem(
                        value: ProductPerformanceView.all,
                        child: Text('All products sold'),
                      ),
                    ],
                    onChanged: (value) =>
                        setState(() => _view = value ?? _view),
                  ),
                ),
                SizedBox(
                  width: 210,
                  child: DropdownButtonFormField<String>(
                    initialValue: _category,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Category',
                      isDense: true,
                    ),
                    items: ['All categories', ...categories]
                        .map(
                          (category) => DropdownMenuItem(
                            value: category,
                            child: Text(category),
                          ),
                        )
                        .toList(),
                    onChanged: (value) =>
                        setState(() => _category = value ?? _category),
                  ),
                ),
                SizedBox(
                  width: 210,
                  child: DropdownButtonFormField<bool>(
                    initialValue: _rankByQuantity,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Rank by',
                      isDense: true,
                    ),
                    items: const [
                      DropdownMenuItem(value: true, child: Text('Quantity')),
                      DropdownMenuItem(value: false, child: Text('Revenue')),
                    ],
                    onChanged: (value) => setState(
                      () => _rankByQuantity = value ?? _rankByQuantity,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (visibleRows.isEmpty)
              const Padding(
                padding: EdgeInsets.all(20),
                child: Text(
                  'No completed sales in this period.',
                  textAlign: TextAlign.center,
                ),
              )
            else
              ...visibleRows.map(
                (entry) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: CircleAvatar(
                    child: Text('${rows.indexOf(entry) + 1}'),
                  ),
                  title: Text(
                    entry.key,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  subtitle: Text(
                    '${_quantityLabel(entry.value)} • '
                    '${entry.value.saleIds.length} transaction${entry.value.saleIds.length == 1 ? '' : 's'}',
                  ),
                  trailing: Text(
                    'GHS ${money(entry.value.revenueCents)}',
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  DateTime _periodStart(ProductPerformancePeriod period) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return switch (period) {
      ProductPerformancePeriod.today => today,
      ProductPerformancePeriod.week => today.subtract(
        Duration(days: today.weekday - DateTime.monday),
      ),
      ProductPerformancePeriod.month => DateTime(now.year, now.month),
      ProductPerformancePeriod.year => DateTime(now.year),
    };
  }

  String _periodLabel(ProductPerformancePeriod period) => switch (period) {
    ProductPerformancePeriod.today => 'Today',
    ProductPerformancePeriod.week => 'This week',
    ProductPerformancePeriod.month => 'This month',
    ProductPerformancePeriod.year => 'This year',
  };

  String _quantityLabel(_ProductPerformanceData data) {
    final product = data.product;
    if (product == null) return '${data.quantityBase} units sold';
    final forms = product.forms.where((form) => form.unitsPerForm > 1).toList()
      ..sort((a, b) => b.unitsPerForm.compareTo(a.unitsPerForm));
    if (forms.isEmpty) {
      return '${data.quantityBase} ${product.baseUnit} sold';
    }
    final form = forms.first;
    final full = data.quantityBase ~/ form.unitsPerForm;
    final remainder = data.quantityBase % form.unitsPerForm;
    final converted = full == 0
        ? ''
        : ' ($full ${form.name}${remainder == 0 ? '' : ' + $remainder ${product.baseUnit}'})';
    return '${data.quantityBase} ${product.baseUnit} sold$converted';
  }
}

class _ProductPerformanceData {
  _ProductPerformanceData({required this.product});

  final Product? product;
  int quantityBase = 0;
  int revenueCents = 0;
  final Set<int> saleIds = {};
}
