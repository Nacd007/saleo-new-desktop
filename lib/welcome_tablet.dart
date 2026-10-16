import 'package:flutter/material.dart';

/// Deliberately labelled sample data, never a user's financial records.
class WelcomeTablet extends StatelessWidget {
  const WelcomeTablet({super.key});

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Tablet preview of Saleo with sample data',
    child: AspectRatio(
      aspectRatio: 1.25,
      child: FittedBox(
        child: Container(
          width: 650,
          height: 520,
          padding: const EdgeInsets.all(13),
          decoration: BoxDecoration(
            color: const Color(0xFF092144),
            borderRadius: BorderRadius.circular(30),
            border: Border.all(color: const Color(0xFF385C89), width: 2),
            boxShadow: const [
              BoxShadow(
                color: Color(0x250B2957),
                blurRadius: 30,
                offset: Offset(0, 16),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: Theme(
              data: ThemeData.light().copyWith(
                textTheme: ThemeData.light().textTheme.apply(
                  bodyColor: const Color(0xFF173258),
                  displayColor: const Color(0xFF173258),
                ),
              ),
              child: const _TabletDashboard(),
            ),
          ),
        ),
      ),
    ),
  );
}

class _TabletDashboard extends StatelessWidget {
  const _TabletDashboard();

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: const Color(0xFFF7FAFF),
    child: Row(
      children: [
        Container(
          width: 104,
          padding: const EdgeInsets.fromLTRB(12, 20, 8, 12),
          color: const Color(0xFFF0F5FD),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'saleo',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 22),
              for (final label in [
                'Dashboard',
                'Sales',
                'Inventory',
                'Receipts',
                'Customers',
                'Reports',
                'Settings',
              ])
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    vertical: 8,
                    horizontal: 5,
                  ),
                  margin: const EdgeInsets.only(bottom: 4),
                  decoration: BoxDecoration(
                    color: label == 'Dashboard'
                        ? const Color(0xFFDCEAFF)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(label, style: const TextStyle(fontSize: 11)),
                ),
            ],
          ),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Your business at a glance',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    Text(
                      'Sample data',
                      style: TextStyle(fontSize: 10, color: Color(0xFF51749E)),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                const Row(
                  children: [
                    Expanded(
                      child: _SampleMetric('Today’s sales', 'GH₵ 7,279.07'),
                    ),
                    SizedBox(width: 8),
                    Expanded(child: _SampleMetric('Transactions', '48')),
                    SizedBox(width: 8),
                    Expanded(child: _SampleMetric('Low stock', '3 products')),
                  ],
                ),
                const SizedBox(height: 14),
                Container(
                  height: 166,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Sales overview',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      SizedBox(height: 12),
                      Expanded(
                        child: SizedBox(
                          width: double.infinity,
                          child: CustomPaint(painter: _SampleChart()),
                        ),
                      ),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('Mon', style: TextStyle(fontSize: 10)),
                          Text('Sun', style: TextStyle(fontSize: 10)),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Recent sales',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 10),
                      for (final row in [
                        ('Club Mini', 'GH₵ 260.00'),
                        ('Eagle Black', 'GH₵ 220.00'),
                      ])
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 5),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                row.$1,
                                style: const TextStyle(fontSize: 11),
                              ),
                              Text(
                                row.$2,
                                style: const TextStyle(fontSize: 11),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    ),
  );
}

class _SampleMetric extends StatelessWidget {
  const _SampleMetric(this.label, this.value);
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(10),
    decoration: BoxDecoration(
      color: const Color(0xFFE9F2FF),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 10)),
        const SizedBox(height: 8),
        Text(
          value,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: Color(0xFF0769DC),
          ),
        ),
      ],
    ),
  );
}

class _SampleChart extends CustomPainter {
  const _SampleChart();
  @override
  void paint(Canvas canvas, Size size) {
    final grid = Paint()
      ..color = const Color(0xFFE6EDF7)
      ..strokeWidth = 1;
    for (var i = 0; i < 4; i++) {
      final y = size.height * i / 3;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }
    const values = [.22, .36, .31, .62, .53, .74, .89];
    final path = Path();
    for (var i = 0; i < values.length; i++) {
      final p = Offset(size.width * i / 6, size.height * (1 - values[i]));
      if (i == 0) {
        path.moveTo(p.dx, p.dy);
      } else {
        path.lineTo(p.dx, p.dy);
      }
      canvas.drawCircle(p, 3, Paint()..color = const Color(0xFF0875F5));
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = const Color(0xFF0875F5)
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke,
    );
  }

  @override
  bool shouldRepaint(covariant _SampleChart oldDelegate) => false;
}
