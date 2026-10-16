import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

class CompanyIdImageService {
  const CompanyIdImageService();

  Future<Uri?> save({
    required String companyName,
    required String companyId,
    Uint8List? companyLogoBytes,
  }) async {
    final bytes = await createPng(
      companyName: companyName,
      companyId: companyId,
      companyLogoBytes: companyLogoBytes,
    );
    return FilePicker.saveFile(
      dialogTitle: 'Save Saleo company ID picture',
      fileName: 'saleo-company-${companyId.toLowerCase()}.png',
      bytes: bytes,
      mimeType: 'image/png',
    );
  }

  Future<Uint8List> createPng({
    required String companyName,
    required String companyId,
    Uint8List? companyLogoBytes,
  }) async {
    const width = 1080.0;
    const height = 1500.0;
    ui.Image? companyLogo;
    if (companyLogoBytes != null && companyLogoBytes.isNotEmpty) {
      try {
        final codec = await ui.instantiateImageCodec(companyLogoBytes);
        final frame = await codec.getNextFrame();
        companyLogo = frame.image;
        codec.dispose();
      } catch (_) {
        companyLogo = null;
      }
    }
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final bounds = const Rect.fromLTWH(0, 0, width, height);
    canvas.drawRect(
      bounds,
      Paint()
        ..shader = ui.Gradient.linear(
          const Offset(0, 0),
          const Offset(width, height),
          const [Color(0xFF04142D), Color(0xFF071F46), Color(0xFF031027)],
          const [0, .52, 1],
        ),
    );
    canvas.drawCircle(
      const Offset(540, 290),
      470,
      Paint()
        ..shader = ui.Gradient.radial(const Offset(540, 290), 470, [
          const Color(0xFF1687F8).withValues(alpha: .25),
          const Color(0x001687F8),
        ]),
    );
    _drawWatermarks(canvas, width: width, height: height);

    final identityRect = Rect.fromCenter(
      center: const Offset(540, 300),
      width: 230,
      height: 230,
    );
    if (companyLogo != null) {
      final logoRRect = RRect.fromRectAndRadius(
        identityRect,
        const Radius.circular(48),
      );
      canvas.drawRRect(
        logoRRect,
        Paint()..color = Colors.white.withValues(alpha: .97),
      );
      canvas.save();
      canvas.clipRRect(logoRRect.deflate(12));
      paintImage(
        canvas: canvas,
        rect: identityRect.deflate(18),
        image: companyLogo,
        fit: BoxFit.contain,
        filterQuality: FilterQuality.high,
      );
      canvas.restore();
      canvas.drawRRect(
        logoRRect,
        Paint()
          ..color = const Color(0xFF1687F8)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 8,
      );
    } else {
      _drawDefaultShield(canvas, identityRect);
    }

    _text(
      canvas,
      companyName.trim().isEmpty ? 'Your company' : companyName.trim(),
      const Offset(120, 510),
      78,
      Colors.white,
      FontWeight.w900,
      maxWidth: 840,
      align: TextAlign.center,
    );
    _text(
      canvas,
      'Your company ID',
      const Offset(150, 655),
      40,
      const Color(0xFFD5DFED),
      FontWeight.w500,
      maxWidth: 780,
      align: TextAlign.center,
    );
    _text(
      canvas,
      companyId.toUpperCase(),
      const Offset(110, 745),
      96,
      const Color(0xFF20A4FF),
      FontWeight.w900,
      maxWidth: 860,
      align: TextAlign.center,
      letterSpacing: 5,
    );
    _text(
      canvas,
      'Use this ID when signing in',
      const Offset(150, 910),
      40,
      const Color(0xFFF1F5FA),
      FontWeight.w500,
      maxWidth: 780,
      align: TextAlign.center,
    );
    final picture = recorder.endRecording();
    final image = await picture.toImage(width.toInt(), height.toInt());
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    companyLogo?.dispose();
    image.dispose();
    if (data == null) {
      throw StateError('Could not create the company ID image.');
    }
    return data.buffer.asUint8List();
  }

  void _drawWatermarks(
    Canvas canvas, {
    required double width,
    required double height,
  }) {
    canvas.save();
    canvas.translate(width / 2, height / 2);
    canvas.rotate(-math.pi / 6);
    canvas.translate(-width / 2, -height / 2);
    const watermarkColor = Color(0x0DFFFFFF);
    for (double y = -320; y < height + 320; y += 170) {
      final offset = ((y / 170).round().isEven) ? -180.0 : -30.0;
      for (double x = offset; x < width + 320; x += 330) {
        _text(
          canvas,
          'SALEO',
          Offset(x, y),
          54,
          watermarkColor,
          FontWeight.w900,
          maxWidth: 250,
          letterSpacing: 4,
        );
      }
    }
    canvas.restore();
  }

  void _drawDefaultShield(Canvas canvas, Rect rect) {
    final shield = Path()
      ..moveTo(rect.center.dx, rect.top)
      ..cubicTo(
        rect.center.dx - 54,
        rect.top + 34,
        rect.left + 20,
        rect.top + 42,
        rect.left + 20,
        rect.top + 42,
      )
      ..lineTo(rect.left + 24, rect.center.dy + 10)
      ..cubicTo(
        rect.left + 30,
        rect.bottom - 72,
        rect.center.dx - 35,
        rect.bottom - 25,
        rect.center.dx,
        rect.bottom,
      )
      ..cubicTo(
        rect.center.dx + 35,
        rect.bottom - 25,
        rect.right - 30,
        rect.bottom - 72,
        rect.right - 24,
        rect.center.dy + 10,
      )
      ..lineTo(rect.right - 20, rect.top + 42)
      ..cubicTo(
        rect.right - 20,
        rect.top + 42,
        rect.center.dx + 54,
        rect.top + 34,
        rect.center.dx,
        rect.top,
      )
      ..close();
    canvas.drawPath(shield, Paint()..color = const Color(0xFF071B36));
    canvas.drawPath(
      shield,
      Paint()
        ..color = const Color(0xFF20A4FF)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 11
        ..strokeJoin = StrokeJoin.round,
    );
    final check = Path()
      ..moveTo(rect.left + 68, rect.center.dy + 5)
      ..lineTo(rect.center.dx - 12, rect.center.dy + 42)
      ..lineTo(rect.right - 58, rect.center.dy - 45);
    canvas.drawPath(
      check,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 16
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  void _text(
    Canvas canvas,
    String value,
    Offset offset,
    double size,
    Color color,
    FontWeight weight, {
    double maxWidth = 800,
    TextAlign align = TextAlign.left,
    double? letterSpacing,
  }) {
    final painter = TextPainter(
      text: TextSpan(
        text: value,
        style: TextStyle(
          color: color,
          fontSize: size,
          fontWeight: weight,
          letterSpacing: letterSpacing,
          height: 1.25,
        ),
      ),
      textDirection: TextDirection.ltr,
      textAlign: align,
    )..layout(maxWidth: maxWidth);
    painter.paint(canvas, offset);
  }
}
