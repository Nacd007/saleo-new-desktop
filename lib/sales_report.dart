import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'app_controller.dart';
import 'common_widgets.dart';
import 'desktop_period_filter.dart';
import 'formatters.dart';
import 'models.dart';
import 'product_quantity_report.dart';

enum ReportPeriod { today, week, month, year }

class DashboardActivityCard extends StatelessWidget {
  const DashboardActivityCard({super.key, required this.controller});
  final AppController controller;
  @override
  Widget build(BuildContext context) => _WeeklyActivityChart(
    sales: salesForPeriod(
      controller.sales,
      ReportPeriod.week,
    ).where((s) => !s.voided).toList(),
    movements: controller.stockMovements,
    range: desktopReportRange(ReportPeriod.week, DateTime.now()),
  );
}

class SalesCharts extends StatelessWidget {
  const SalesCharts({
    super.key,
    required this.sales,
    required this.movements,
    required this.range,
  });
  final List<Sale> sales;
  final List<StockMovement> movements;
  final DateTimeRange range;
  @override
  Widget build(BuildContext context) {
    final valid = sales.where((s) => !s.voided).toList();
    return Column(
      children: [
        _WeeklyActivityChart(sales: valid, movements: movements, range: range),
        const SizedBox(height: 12),
        _PaymentCard(
          cash: valid.fold(0, (n, s) => n + s.cashCents),
          mobile: valid.fold(0, (n, s) => n + s.mobileMoneyCents),
        ),
      ],
    );
  }
}

extension ReportPeriodLabel on ReportPeriod {
  String get label => switch (this) {
    ReportPeriod.today => 'Today',
    ReportPeriod.week => 'This week',
    ReportPeriod.month => 'This month',
    ReportPeriod.year => 'Year',
  };
}

DateTime reportStart(ReportPeriod period, DateTime now) {
  final today = DateTime(now.year, now.month, now.day);
  return switch (period) {
    ReportPeriod.today => today,
    ReportPeriod.week => today.subtract(Duration(days: now.weekday - 1)),
    ReportPeriod.month => DateTime(now.year, now.month),
    ReportPeriod.year => DateTime(now.year),
  };
}

List<Sale> salesForPeriod(List<Sale> sales, ReportPeriod period) {
  final start = reportStart(period, DateTime.now());
  return sales
      .where((sale) => !sale.createdAt.toLocal().isBefore(start))
      .toList();
}

class SalesReportPage extends StatefulWidget {
  const SalesReportPage({
    super.key,
    required this.sales,
    required this.onRefresh,
    required this.controller,
  });

  final List<Sale> sales;
  final Future<void> Function() onRefresh;
  final AppController controller;

  @override
  State<SalesReportPage> createState() => _SalesReportPageState();
}

class _SalesReportPageState extends State<SalesReportPage> {
  ReportPeriod _period = ReportPeriod.today;
  DateTimeRange? _customRange;
  bool _productTrend = false;
  int? _productId;
  late int _year = DateTime.now().year;

  @override
  Widget build(BuildContext context) {
    final range = _customRange ?? desktopReportRange(_period, DateTime.now());
    final sales = widget.sales
        .where(
          (s) =>
              desktopDateInRange(s.createdAt, range) &&
              !s.createdAt.toLocal().isAfter(DateTime.now()),
        )
        .toList();
    final valid = sales.where((sale) => !sale.voided).toList();
    final total = valid.fold<int>(0, (sum, sale) => sum + sale.totalCents);
    final cash = valid.fold<int>(0, (sum, sale) => sum + sale.cashCents);
    final mobile = valid.fold<int>(
      0,
      (sum, sale) => sum + sale.mobileMoneyCents,
    );
    final received = widget.controller.stockMovements
        .where(
          (movement) =>
              movement.quantityBase > 0 &&
              (movement.type == 'restock' || movement.type == 'opening') &&
              desktopDateInRange(movement.createdAt, range) &&
              !movement.createdAt.toLocal().isAfter(DateTime.now()),
        )
        .fold<int>(0, (sum, movement) => sum + movement.quantityBase);
    final soldUnits = valid
        .expand((sale) => sale.items)
        .fold<int>(0, (sum, item) => sum + item.quantity * item.unitsPerForm);

    return RefreshIndicator(
      onRefresh: widget.onRefresh,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 30),
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: SegmentedButton<bool>(
              segments: const [
                ButtonSegment(
                  value: false,
                  icon: Icon(Icons.dashboard_outlined),
                  label: Text('Overview'),
                ),
                ButtonSegment(
                  value: true,
                  icon: Icon(Icons.bar_chart_rounded),
                  label: Text('Product trend'),
                ),
              ],
              selected: {_productTrend},
              onSelectionChanged: (value) =>
                  setState(() => _productTrend = value.first),
            ),
          ),
          const SizedBox(height: 12),
          if (_productTrend)
            _buildProductTrend(context)
          else ...[
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DesktopPeriodFilter(
                period: _period,
                customRange: _customRange,
                onChanged: (p, r) => setState(() {
                  _period = p;
                  _customRange = r;
                }),
              ),
            ),
            const SizedBox(height: 12),
            GridView.count(
              crossAxisCount: MediaQuery.sizeOf(context).width > 700 ? 4 : 2,
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              mainAxisExtent: MediaQuery.sizeOf(context).width < 900 ? 112 : 96,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              children: [
                _ReportMetric(
                  label: 'Sales value',
                  value: 'GHS ${money(total)}',
                  icon: Icons.receipt_long_outlined,
                ),
                _ReportMetric(
                  label: 'Transactions',
                  value: '${valid.length}',
                  icon: Icons.numbers,
                ),
                _ReportMetric(
                  label: 'Units sold',
                  value: '$soldUnits',
                  icon: Icons.trending_up,
                ),
                _ReportMetric(
                  label: 'Units received',
                  value: '$received',
                  icon: Icons.inventory_2_outlined,
                ),
              ],
            ),
            const SizedBox(height: 12),
            _productQuantities(range, valid),
            const SizedBox(height: 12),
            Card(
              child: ExpansionTile(
                leading: const Icon(Icons.list_alt_outlined),
                title: Text('${valid.length} transactions'),
                subtitle: const Text('Tap to view individual receipts'),
                children: [
                  SizedBox(
                    height: math.min(520, 110.0 * math.max(1, sales.length)),
                    child: SalesList(
                      sales: sales,
                      controller: widget.controller,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            _WeeklyActivityChart(
              sales: valid,
              movements: widget.controller.stockMovements,
              range: range,
            ),
            const SizedBox(height: 12),
            _PaymentCard(cash: cash, mobile: mobile),
          ],
        ],
      ),
    );
  }

  Widget _buildProductTrend(BuildContext context) {
    final products = widget.controller.products;
    final selectedId =
        _productId ?? (products.isEmpty ? null : products.first.id);
    final selected = products.where((p) => p.id == selectedId).firstOrNull;
    final monthly = List<int>.filled(12, 0);
    final monthlyRevenue = List<int>.filled(12, 0);
    if (selected != null) {
      for (final sale in widget.sales.where(
        (sale) => !sale.voided && sale.createdAt.toLocal().year == _year,
      )) {
        for (final item in sale.items.where(
          (item) =>
              item.productId == selected.id ||
              item.productCode == selected.code,
        )) {
          final month = sale.createdAt.toLocal().month - 1;
          monthly[month] += item.quantity * item.unitsPerForm;
          monthlyRevenue[month] += item.lineTotalCents;
        }
      }
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DropdownButtonFormField<int>(
          initialValue: selectedId,
          decoration: const InputDecoration(
            labelText: 'Selected product',
            prefixIcon: Icon(Icons.search),
          ),
          items: products
              .map(
                (product) => DropdownMenuItem(
                  value: product.id,
                  child: Text('${product.name} · ${product.category}'),
                ),
              )
              .toList(),
          onChanged: (value) => setState(() => _productId = value),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            IconButton(
              tooltip: 'Previous year',
              onPressed: () => setState(() => _year--),
              icon: const Icon(Icons.chevron_left),
            ),
            Expanded(
              child: Text(
                'Monthly product performance · $_year',
                textAlign: TextAlign.center,
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
            ),
            IconButton(
              tooltip: 'Next year',
              onPressed: _year >= DateTime.now().year
                  ? null
                  : () => setState(() => _year++),
              icon: const Icon(Icons.chevron_right),
            ),
          ],
        ),
        const SizedBox(height: 8),
        _MonthlyBarChart(values: monthly),
        const SizedBox(height: 10),
        Card(
          child: ListTile(
            leading: const Icon(Icons.insights_outlined),
            title: Text(
              '${monthly.fold<int>(0, (a, b) => a + b)} units sold',
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
            subtitle: Text(
              'GHS ${money(monthlyRevenue.fold<int>(0, (a, b) => a + b))} revenue in $_year',
            ),
          ),
        ),
      ],
    );
  }

  Widget _productQuantities(DateTimeRange range, List<Sale> sales) {
    final rows = productQuantityReport(
      products: widget.controller.products,
      sales: sales,
      movements: widget.controller.stockMovements,
      start: range.start,
      end: range.end,
    );
    String quantity(ProductQuantityRow row, int base) => row.product == null
        ? '$base single units (form unavailable)'
        : productStockText(row.product!, base);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Products sold and bought / received',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 4),
            const Text(
              'Selected period · first selling form + loose units (total single units). Received quantities are posted purchases; opening stock and pending deliveries are excluded. Current form definitions are used.',
            ),
            const SizedBox(height: 12),
            if (rows.isEmpty)
              const Text('No product sales or posted purchases in this period.')
            else
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  columns: const [
                    DataColumn(label: Text('Product')),
                    DataColumn(label: Text('First form')),
                    DataColumn(label: Text('Sold')),
                    DataColumn(label: Text('Bought / received')),
                  ],
                  rows: rows
                      .map(
                        (row) => DataRow(
                          cells: [
                            DataCell(Text('${row.name}\n${row.code}')),
                            DataCell(
                              Text(
                                row.product?.forms.firstOrNull?.name ??
                                    'Unavailable',
                              ),
                            ),
                            DataCell(Text(quantity(row, row.soldBase))),
                            DataCell(Text(quantity(row, row.receivedBase))),
                          ],
                        ),
                      )
                      .toList(),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ReportMetric extends StatelessWidget {
  const _ReportMetric({
    required this.label,
    required this.value,
    required this.icon,
  });
  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) => Card(
    margin: EdgeInsets.zero,
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 19, color: Theme.of(context).colorScheme.primary),
          const SizedBox(height: 6),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w900)),
          Text(label, style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    ),
  );
}

class _WeeklyActivityChart extends StatelessWidget {
  const _WeeklyActivityChart({
    required this.sales,
    required this.movements,
    required this.range,
  });
  final List<Sale> sales;
  final List<StockMovement> movements;
  final DateTimeRange range;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final start = range.start;
    final last = range.end.subtract(const Duration(microseconds: 1));
    final monthly = range.duration.inDays > 62;
    final hourly = DateUtils.isSameDay(start, last);
    final length = monthly
        ? (last.year - start.year) * 12 + last.month - start.month + 1
        : hourly
        ? 24
        : DateUtils.dateOnly(last)
                  .difference(DateUtils.dateOnly(start))
                  .inDays +
              1;
    int indexFor(DateTime date) => monthly
        ? (date.year - start.year) * 12 + date.month - start.month
        : hourly
        ? date.hour
        : DateUtils.dateOnly(date).difference(DateUtils.dateOnly(start)).inDays;
    final labels = List.generate(
      length,
      (i) => monthly
          ? '${(start.month + i - 1) % 12 + 1}/${start.year + (start.month + i - 1) ~/ 12}'
          : hourly
          ? '${i.toString().padLeft(2, '0')}:00'
          : desktopDateLabel(DateTime(start.year, start.month, start.day + i)),
    );
    final sold = List<double>.filled(length, 0);
    final received = List<double>.filled(length, 0);
    for (final sale in sales.where((sale) => !sale.voided)) {
      final date = sale.createdAt.toLocal();
      if (!desktopDateInRange(date, range) || date.isAfter(now)) continue;
      final index = indexFor(date);
      sold[index] += sale.items.fold<int>(
        0,
        (sum, item) => sum + item.quantity * item.unitsPerForm,
      );
    }
    for (final movement in movements) {
      if (movement.quantityBase <= 0 ||
          !['restock', 'opening'].contains(movement.type)) {
        continue;
      }
      final date = movement.createdAt.toLocal();
      if (!desktopDateInRange(date, range) || date.isAfter(now)) continue;
      final index = indexFor(date);
      received[index] += movement.quantityBase;
    }
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Sold vs received • ${desktopRangeLabel(range)}',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text(
              'Single units • Blue = sold · Green = received · Hover for values',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 230,
              child: sold.every((v) => v == 0) && received.every((v) => v == 0)
                  ? const Center(
                      child: Text('No sales or stock received in this period.'),
                    )
                  : _GroupedBars(first: sold, second: received, labels: labels),
            ),
          ],
        ),
      ),
    );
  }
}

class _MonthlyBarChart extends StatelessWidget {
  const _MonthlyBarChart({required this.values});
  final List<int> values;
  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.fromLTRB(14, 18, 14, 12),
      child: SizedBox(
        height: 220,
        child: _SingleBars(values: values.map((v) => v.toDouble()).toList()),
      ),
    ),
  );
}

class _GroupedBars extends StatelessWidget {
  const _GroupedBars({
    required this.first,
    required this.second,
    required this.labels,
    this.showReceived = true,
  });
  final List<double> first;
  final List<double> second;
  final List<String> labels;
  final bool showReceived;
  @override
  Widget build(BuildContext context) {
    final maxValue = [...first, ...second].fold<double>(1, math.max);
    return Row(
      children: [
        SizedBox(
          width: 52,
          child: Padding(
            padding: const EdgeInsets.only(bottom: 28),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var i = 4; i >= 0; i--)
                  Text(
                    (maxValue * i / 4).ceil().toString(),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
              ],
            ),
          ),
        ),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) => SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SizedBox(
                width: math.max(constraints.maxWidth, first.length * 66.0),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: List.generate(first.length, (index) {
                    return Expanded(
                      child: Tooltip(
                        message:
                            '${labels[index]}\nSold: ${first[index].toInt()} units${showReceived ? '\nReceived: ${second[index].toInt()} units' : ''}',
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            Expanded(
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  _Bar(
                                    factor: first[index] / maxValue,
                                    color: Theme.of(context)
                                        .colorScheme
                                        .primary,
                                    width: 20,
                                  ),
                                  if (showReceived) const SizedBox(width: 3),
                                  if (showReceived)
                                    _Bar(
                                      factor: second[index] / maxValue,
                                      color: const Color(0xFF0FA879),
                                      width: 20,
                                    ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 6),
                            SizedBox(
                              height: 22,
                              child: Text(
                                labels[index],
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _SingleBars extends StatelessWidget {
  const _SingleBars({required this.values});
  final List<double> values;
  @override
  Widget build(BuildContext context) {
    if (values.every((v) => v == 0)) {
      return const Center(child: Text('No product sales in this year.'));
    }
    return _GroupedBars(
      first: values,
      second: List.filled(values.length, 0),
      showReceived: false,
      labels: const [
        'Jan',
        'Feb',
        'Mar',
        'Apr',
        'May',
        'Jun',
        'Jul',
        'Aug',
        'Sep',
        'Oct',
        'Nov',
        'Dec',
      ],
    );
  }
}

class _Bar extends StatelessWidget {
  const _Bar({required this.factor, required this.color, this.width = 9});
  final double factor;
  final Color color;
  final double width;
  @override
  Widget build(BuildContext context) => FractionallySizedBox(
    heightFactor: factor.clamp(0.0, 1),
    child: Container(
      width: width,
      decoration: BoxDecoration(
        color: color,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(5)),
      ),
    ),
  );
}

class _PaymentCard extends StatelessWidget {
  const _PaymentCard({required this.cash, required this.mobile});
  final int cash;
  final int mobile;
  @override
  Widget build(BuildContext context) {
    final total = math.max(1, cash + mobile);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            SizedBox(
              width: 86,
              height: 86,
              child: cash + mobile == 0
                  ? const Center(child: Icon(Icons.payments_outlined))
                  : CustomPaint(
                      painter: _DonutPainter(
                        cashPart: cash / total,
                        primary: Theme.of(context).colorScheme.primary,
                      ),
                    ),
            ),
            const SizedBox(width: 18),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Payments on selected sales',
                    style: TextStyle(fontWeight: FontWeight.w900),
                  ),
                  Text('Cash: GHS ${money(cash)}'),
                  Text('MOMO: GHS ${money(mobile)}'),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DonutPainter extends CustomPainter {
  const _DonutPainter({required this.cashPart, required this.primary});
  final double cashPart;
  final Color primary;
  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 14;
    paint.color = const Color(0xFF12B886);
    canvas.drawArc(rect.deflate(8), -math.pi / 2, math.pi * 2, false, paint);
    paint.color = primary;
    canvas.drawArc(
      rect.deflate(8),
      -math.pi / 2,
      math.pi * 2 * cashPart,
      false,
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant _DonutPainter oldDelegate) =>
      oldDelegate.cashPart != cashPart || oldDelegate.primary != primary;
}
