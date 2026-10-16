import 'package:flutter/material.dart';

/// Compact native vector pictograms; no runtime image download or icon package.
class DesktopGraphicIcon extends StatelessWidget {
  const DesktopGraphicIcon(this.label, {super.key, this.size = 24});
  final String label;
  final double size;
  @override
  Widget build(BuildContext context) => Semantics(
    excludeSemantics: true,
    child: SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _GraphicPainter(
          label,
          Theme.of(context).colorScheme.primary,
          Theme.of(context).colorScheme.onPrimary,
        ),
      ),
    ),
  );
}

class _GraphicPainter extends CustomPainter {
  const _GraphicPainter(this.label, this.colour, this.ink);
  final String label;
  final Color colour;
  final Color ink;
  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 24, size.height / 24);
    final solid = Paint()..color = colour;
    final soft = Paint()..color = colour.withValues(alpha: .28);
    final line = Paint()
      ..color = colour
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8
      ..strokeCap = StrokeCap.round;
    void box(double x, double y, double w, double h, Paint p) =>
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(x, y, w, h),
            const Radius.circular(2),
          ),
          p,
        );
    switch (label) {
      case 'Sell':
        box(4, 7, 16, 15, soft);
        box(4, 11, 16, 11, solid);
        canvas.drawArc(
          const Rect.fromLTWH(8, 2, 8, 12),
          3.14,
          3.14,
          false,
          line,
        );
      case 'Products':
        canvas.drawPath(
          Path()
            ..moveTo(3, 7)
            ..lineTo(12, 2)
            ..lineTo(21, 7)
            ..lineTo(12, 12)
            ..close(),
          soft,
        );
        canvas.drawPath(
          Path()
            ..moveTo(3, 8)
            ..lineTo(11, 13)
            ..lineTo(11, 22)
            ..lineTo(3, 17)
            ..close(),
          solid,
        );
        canvas.drawPath(
          Path()
            ..moveTo(13, 13)
            ..lineTo(21, 8)
            ..lineTo(21, 17)
            ..lineTo(13, 22)
            ..close(),
          soft,
        );
      case 'Customers':
        canvas.drawCircle(const Offset(9, 7), 4, solid);
        canvas.drawCircle(const Offset(18, 9), 3, soft);
        box(2, 13, 14, 9, solid);
        box(16, 15, 7, 7, soft);
      case 'Debtors':
        box(2, 5, 20, 15, soft);
        box(2, 9, 20, 11, solid);
        canvas.drawCircle(const Offset(17, 14), 2, Paint()..color = ink);
      case 'Reports':
      case 'Inventory reports':
        box(2, 13, 5, 9, soft);
        box(9, 8, 5, 14, solid);
        box(16, 2, 5, 20, soft);
      case 'Receive Stock':
        box(2, 4, 17, 17, soft);
        box(2, 8, 17, 13, solid);
        canvas.drawCircle(const Offset(18, 18), 5, solid);
        final white = Paint()
          ..color = ink
          ..strokeWidth = 1.4;
        canvas.drawLine(const Offset(15, 18), const Offset(21, 18), white);
        canvas.drawLine(const Offset(18, 15), const Offset(18, 21), white);
      case 'Printers':
        box(5, 2, 14, 7, soft);
        box(2, 8, 20, 10, solid);
        box(5, 15, 14, 7, soft);
      case 'Settings':
        for (final x in [5.0, 12.0, 19.0]) {
          canvas.drawLine(Offset(x, 3), Offset(x, 21), line);
        }
        box(2, 6, 6, 5, solid);
        box(9, 13, 6, 5, solid);
        box(16, 5, 6, 5, solid);
      case 'Inventory':
        canvas.drawPath(
          Path()
            ..moveTo(2, 9)
            ..lineTo(12, 2)
            ..lineTo(22, 9)
            ..close(),
          soft,
        );
        box(3, 9, 18, 13, line);
        box(6, 15, 5, 6, solid);
        box(13, 15, 5, 6, soft);
        box(10, 10, 5, 4, solid);
      case 'Dashboard':
        box(2, 2, 9, 12, solid);
        box(14, 2, 8, 7, soft);
        box(2, 17, 9, 5, soft);
        box(14, 12, 8, 10, solid);
      case 'Staff':
      case 'Account':
        box(3, 4, 18, 18, soft);
        box(8, 1, 8, 5, solid);
        canvas.drawCircle(const Offset(12, 11), 3, solid);
        box(7, 16, 10, 4, solid);
      case 'Creditors':
        box(7, 2, 10, 6, line);
        box(2, 7, 20, 14, soft);
        box(2, 7, 20, 6, solid);
        box(10, 11, 4, 5, Paint()..color = ink);
      case 'Profit':
        box(2, 14, 5, 8, soft);
        box(10, 10, 5, 12, soft);
        box(18, 5, 4, 17, soft);
        canvas.drawPath(
          Path()
            ..moveTo(3, 11)
            ..lineTo(10, 5)
            ..lineTo(14, 8)
            ..lineTo(21, 2)
            ..moveTo(16, 2)
            ..lineTo(21, 2)
            ..lineTo(21, 7),
          line,
        );
      case 'Sales':
        canvas.drawPath(
          Path()
            ..moveTo(5, 2)
            ..lineTo(19, 2)
            ..lineTo(19, 22)
            ..lineTo(15, 20)
            ..lineTo(12, 22)
            ..lineTo(9, 20)
            ..lineTo(5, 22)
            ..close(),
          soft,
        );
        canvas.drawLine(const Offset(8, 7), const Offset(16, 7), line);
        canvas.drawLine(const Offset(8, 11), const Offset(16, 11), line);
        canvas.drawPath(
          Path()
            ..moveTo(8, 16)
            ..lineTo(11, 18)
            ..lineTo(16, 14),
          line,
        );
      case 'Appearance':
        canvas.drawCircle(const Offset(12, 12), 9, soft);
        canvas.drawCircle(const Offset(12, 12), 5, solid);
        canvas.drawCircle(const Offset(12, 12), 2, Paint()..color = ink);
      default:
        box(5, 2, 14, 20, soft);
        for (var y = 7.0; y < 19; y += 4) {
          canvas.drawLine(Offset(8, y), Offset(16, y), line);
        }
    }
  }

  @override
  bool shouldRepaint(_GraphicPainter old) =>
      old.label != label || old.colour != colour || old.ink != ink;
}
