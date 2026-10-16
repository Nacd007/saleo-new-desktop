import 'package:flutter_test/flutter_test.dart';
import 'package:saleo_app/receipt_item_layout.dart';
import 'package:unified_esc_pos_printer/unified_esc_pos_printer.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final size in [PaperSize.mm58, PaperSize.mm80]) {
    test(
      '${size.widthMM}mm rows retain aligned columns and full descriptions',
      () {
        final large = ReceiptItemLayout(size.charsPerLine(FontType.fontA));
        final width = size.charsPerLine(
          large.numbersFit('4', '255.00', '1,020.00')
              ? FontType.fontA
              : FontType.fontB,
        );
        final layout = ReceiptItemLayout(width);
        final lines = layout.lines(
          quantity: '4',
          description: 'Guinness Malt Bottle (Plastic) - Crate',
          unit: '255.00',
          amount: '1,020.00',
        );
        expect(lines.every((line) => line.length == width), isTrue);
        expect(lines.first.indexOf('Guinness'), (width / 13).round());
        expect(lines.first.endsWith('1,020.00'), isTrue);
        final start = (width / 13).round();
        final end = (width * 7 / 13).round();
        expect(
          lines.map((line) => line.substring(start, end).trim()).join(' '),
          'Guinness Malt Bottle (Plastic) - Crate',
        );
        expect(lines.skip(1).every((line) => !line.contains('255.00')), isTrue);
      },
    );
  }

  test(
    'native single-line items use fewer bytes than positioned cells',
    () async {
      final profile = await CapabilityProfile.load();
      final legacy = Ticket(PaperSize.mm80, profile);
      legacy.row([
        PrintColumn(text: '1', flex: 1),
        PrintColumn(text: 'ABC - Crate', flex: 6),
        PrintColumn(text: '200.00', flex: 3, align: PrintAlign.right),
        PrintColumn(text: '200.00', flex: 3, align: PrintAlign.right),
      ]);
      final optimized = Ticket(PaperSize.mm80, profile);
      for (final line in const ReceiptItemLayout(48).lines(
        quantity: '1',
        description: 'ABC - Crate',
        unit: '200.00',
        amount: '200.00',
      )) {
        optimized.text(
          line,
          style: const PrintTextStyle(fontType: FontType.fontA),
        );
      }
      expect(optimized.bytes.length, lessThan(legacy.bytes.length));
    },
  );
}
