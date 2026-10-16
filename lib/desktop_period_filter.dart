import 'package:flutter/material.dart';

import 'sales_report.dart';

/// Calendar dates are local; the end is exclusive so the last day is complete.
DateTimeRange desktopReportRange(ReportPeriod period, DateTime now) {
  final start = reportStart(period, now);
  final end = switch (period) {
    ReportPeriod.today => DateTime(now.year, now.month, now.day + 1),
    ReportPeriod.week => DateTime(start.year, start.month, start.day + 7),
    ReportPeriod.month => DateTime(now.year, now.month + 1),
    ReportPeriod.year => DateTime(now.year + 1),
  };
  return DateTimeRange(start: start, end: end);
}

bool desktopDateInRange(DateTime date, DateTimeRange range) {
  final local = date.toLocal();
  return !local.isBefore(range.start) && local.isBefore(range.end);
}

String desktopDateLabel(DateTime date) =>
    '${date.day.toString().padLeft(2, '0')}-${date.month.toString().padLeft(2, '0')}-${date.year}';

String desktopRangeLabel(DateTimeRange range) =>
    '${desktopDateLabel(range.start)} to ${desktopDateLabel(range.end.subtract(const Duration(microseconds: 1)))}';

class DesktopPeriodFilter extends StatelessWidget {
  const DesktopPeriodFilter({
    super.key,
    required this.period,
    required this.customRange,
    required this.onChanged,
  });
  final ReportPeriod period;
  final DateTimeRange? customRange;
  final void Function(ReportPeriod period, DateTimeRange? range) onChanged;

  Future<void> _pick(BuildContext context) async {
    final now = DateTime.now();
    final current = customRange ?? desktopReportRange(period, now);
    final selected = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: DateTime(now.year + 10, 12, 31),
      initialDateRange: DateTimeRange(
        start: current.start,
        end: current.end.subtract(const Duration(microseconds: 1)),
      ),
      helpText: 'Select reporting dates (day-month-year)',
      builder: (context, child) =>
          Center(child: SizedBox(width: 680, height: 600, child: child)),
    );
    if (selected != null) {
      onChanged(
        period,
        DateTimeRange(
          start: selected.start,
          end: DateTime(
            selected.end.year,
            selected.end.month,
            selected.end.day + 1,
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 8,
    crossAxisAlignment: WrapCrossAlignment.center,
    children: [
      DropdownButton<String>(
        value: customRange == null ? period.name : 'custom',
        items: [
          for (final p in ReportPeriod.values)
            DropdownMenuItem(
              value: p.name,
              child: Text(switch (p) {
                ReportPeriod.today => 'Day',
                ReportPeriod.week => 'Week',
                ReportPeriod.month => 'Month',
                ReportPeriod.year => 'Year',
              }),
            ),
          const DropdownMenuItem(value: 'custom', child: Text('Custom dates')),
        ],
        onChanged: (value) {
          if (value == 'custom') {
            _pick(context);
          } else if (value != null) {
            onChanged(ReportPeriod.values.byName(value), null);
          }
        },
      ),
      TextButton.icon(
        onPressed: () => _pick(context),
        icon: const Icon(Icons.date_range_outlined, size: 18),
        label: Text(
          customRange == null
              ? 'Select dates'
              : desktopRangeLabel(customRange!),
        ),
      ),
    ],
  );
}
