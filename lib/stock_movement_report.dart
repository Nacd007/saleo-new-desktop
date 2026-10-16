import 'package:flutter/material.dart';

import 'app_controller.dart';
import 'desktop_period_filter.dart';
import 'sales_report.dart';

class StockMovementReportScreen extends StatefulWidget {
  const StockMovementReportScreen({super.key, required this.controller});
  final AppController controller;
  @override
  State<StockMovementReportScreen> createState() =>
      _StockMovementReportScreenState();
}

class _StockMovementReportScreenState extends State<StockMovementReportScreen> {
  ReportPeriod _period = ReportPeriod.week;
  DateTimeRange? _customRange;
  String _query = '';
  String _type = 'all';

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Stock movement report')),
    body: AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        final now = DateTime.now();
        final range = _customRange ?? desktopReportRange(_period, now);
        final products = {
          for (final product in widget.controller.products) product.id: product,
        };
        final types =
            widget.controller.stockMovements.map((m) => m.type).toSet().toList()
              ..sort();
        final selectedType = types.contains(_type) ? _type : 'all';
        final query = _query.trim().toLowerCase();
        final movements = widget.controller.stockMovements.where((movement) {
          final product = products[movement.productId];
          return desktopDateInRange(movement.createdAt, range) &&
              !movement.createdAt.isAfter(now) &&
              (selectedType == 'all' || movement.type == selectedType) &&
              (query.isEmpty ||
                  [
                    product?.name ?? '',
                    product?.code ?? '',
                    product?.category ?? '',
                    movement.actorName,
                    movement.note ?? '',
                    movement.referenceId ?? '',
                  ].any((text) => text.toLowerCase().contains(query)));
        }).toList()..sort((a, b) => b.createdAt.compareTo(a.createdAt));
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DesktopPeriodFilter(
                period: _period,
                customRange: _customRange,
                onChanged: (period, range) => setState(() {
                  _period = period;
                  _customRange = range;
                }),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              decoration: const InputDecoration(
                labelText: 'Search movements',
                hintText: 'Product, category, staff or reference',
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: (value) => setState(() => _query = value),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              key: ValueKey(selectedType),
              initialValue: selectedType,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Movement type'),
              items: [
                const DropdownMenuItem(
                  value: 'all',
                  child: Text('All movements'),
                ),
                for (final type in types)
                  DropdownMenuItem(value: type, child: Text(_label(type))),
              ],
              onChanged: (value) => setState(() => _type = value ?? 'all'),
            ),
            const SizedBox(height: 12),
            Text(
              '${movements.length} recorded movement${movements.length == 1 ? '' : 's'}',
            ),
            const SizedBox(height: 4),
            const Text(
              'Shows recorded history available on this device. Cloud balance snapshots are not deliveries or sales.',
            ),
            const SizedBox(height: 12),
            if (movements.isEmpty)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(20),
                  child: Text(
                    'No stock movements match this period and search.',
                  ),
                ),
              ),
            for (final movement in movements)
              Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ExpansionTile(
                  title: Text(
                    products[movement.productId]?.name ??
                        'Product #${movement.productId}',
                  ),
                  subtitle: Text(
                    '${_label(movement.type)} • ${_date(movement.createdAt)}\n'
                    '${movement.quantityBase > 0 ? '+' : ''}${movement.quantityBase} single units',
                  ),
                  childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  children: [
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Recorded by: ${movement.actorName}'),
                          if (movement.referenceId?.isNotEmpty ?? false)
                            Text('Reference: ${movement.referenceId}'),
                          if (movement.note?.isNotEmpty ?? false)
                            Text('Note: ${movement.note}'),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
          ],
        );
      },
    ),
  );

  String _date(DateTime date) {
    final local = date.toLocal();
    return '${desktopDateLabel(local)} ${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
  }

  String _label(String type) => switch (type) {
    'restock' => 'Stock received',
    'sale' => 'Stock sold',
    'opening' => 'Opening stock',
    'sale_void' => 'Voided sale reversal',
    'receipt_reversal' => 'Delivery reversal',
    'sync_snapshot' => 'Cloud balance snapshot',
    _ => type.replaceAll('_', ' '),
  };
}
