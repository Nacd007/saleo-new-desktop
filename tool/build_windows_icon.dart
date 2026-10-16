import 'dart:io';
import 'dart:typed_data';

import 'package:image/image.dart' as image;

// Mechanical PNG-to-ICO conversion of the existing Saleo brand asset.
void main() {
  final original = image.decodePng(
    File('assets/branding/saleo-logo-symbol-v2.png').readAsBytesSync(),
  )!;
  final sizes = [16, 32, 48, 64, 128, 256];
  final encoded = [
    for (final size in sizes)
      image.encodePng(image.copyResize(original, width: size, height: size)),
  ];
  final header = ByteData(6 + sizes.length * 16)
    ..setUint16(2, 1, Endian.little)
    ..setUint16(4, sizes.length, Endian.little);
  var offset = header.lengthInBytes;
  for (var i = 0; i < sizes.length; i++) {
    final start = 6 + i * 16;
    header.setUint8(start, sizes[i] == 256 ? 0 : sizes[i]);
    header.setUint8(start + 1, sizes[i] == 256 ? 0 : sizes[i]);
    header.setUint16(start + 4, 1, Endian.little);
    header.setUint16(start + 6, 32, Endian.little);
    header.setUint32(start + 8, encoded[i].length, Endian.little);
    header.setUint32(start + 12, offset, Endian.little);
    offset += encoded[i].length;
  }
  File('windows/runner/resources/app_icon.ico').writeAsBytesSync([
    ...header.buffer.asUint8List(),
    for (final png in encoded) ...png,
  ]);
}
