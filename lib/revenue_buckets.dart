import 'package:flutter/material.dart';

import 'models.dart';

DateTime _calendar(DateTime d) => DateTime.utc(d.year, d.month, d.day);

class RevenueBuckets {
  RevenueBuckets(this.starts, this.ends, this.values);
  final List<DateTime> starts, ends;
  final List<int> values;
}

RevenueBuckets buildRevenueBuckets(List<Sale> sales, DateTimeRange range) {
  final days = _calendar(range.end).difference(_calendar(range.start)).inDays;
  final monthly = days > 62;
  final total = monthly
      ? ((range.end.year - range.start.year) * 12 +
                range.end.month -
                range.start.month +
                (range.end.day > 1 ? 1 : 0))
            .clamp(1, 100000)
      : days.clamp(1, 100000);
  final step = (total / 24).ceil();
  final count = (total / step).ceil();
  final starts = [
    for (var i = 0; i < count; i++)
      monthly
          ? (i == 0
                ? range.start
                : DateTime(range.start.year, range.start.month + i * step))
          : DateTime(
              range.start.year,
              range.start.month,
              range.start.day + i * step,
            ),
  ];
  final ends = [
    for (var i = 0; i < count; i++) i == count - 1 ? range.end : starts[i + 1],
  ];
  final values = List<int>.filled(count, 0);
  for (final sale in sales) {
    final d = sale.createdAt.toLocal();
    if (sale.voided || d.isBefore(range.start) || !d.isBefore(range.end)) {
      continue;
    }
    final raw = monthly
        ? (d.year - range.start.year) * 12 + d.month - range.start.month
        : _calendar(d).difference(_calendar(range.start)).inDays;
    final i = raw ~/ step;
    if (i >= 0 && i < count) values[i] += sale.totalCents;
  }
  return RevenueBuckets(starts, ends, values);
}
