import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saleo_app/desktop_design.dart';
import 'package:saleo_app/desktop_settings.dart';
import 'package:saleo_app/models.dart';

void main() {
  test('personal appearance round trips through shared preference payload', () {
    const value = InventoryPreferences(
      theme: AppThemePreference.dark,
      accent: AppAccentPreference.custom,
      customAccentArgb: 0xFFC63545,
      showProductImages: false,
      textScale: 1.1,
    );
    final restored = const InventoryPreferences().applySharedJson(
      value.toSharedJson(),
    );
    expect(restored.theme, value.theme);
    expect(restored.customAccentArgb, value.customAccentArgb);
    expect(restored.accent, AppAccentPreference.custom);
    expect(restored.showProductImages, false);
    expect(restored.textScale, 1.1);
    expect(
      restored.applySharedJson({'notify_low_stock': false}).customAccentArgb,
      value.customAccentArgb,
    );
  });
  test(
    'custom accents remain readable without recolouring error semantics',
    () {
      for (final mode in DesktopMode.values) {
        for (final color in [
          Colors.white,
          Colors.black,
          Colors.yellow,
          Colors.red,
          Colors.green,
        ]) {
          final theme = desktopTheme(mode, accent: color);
          final a = theme.colorScheme.primary.computeLuminance();
          final b = theme.colorScheme.surface.computeLuminance();
          expect(
            a > b ? (a + .05) / (b + .05) : (b + .05) / (a + .05),
            greaterThanOrEqualTo(4.5),
          );
          // Safety/error hue must stay independent of the selected decorative accent.
          expect(theme.colorScheme.error, desktopTheme(mode).colorScheme.error);
        }
      }
    },
  );
  testWidgets('HEX colour picker validates and returns selected colour', (
    tester,
  ) async {
    Color? result;
    await tester.pumpWidget(
      MaterialApp(
        theme: desktopTheme(DesktopMode.white),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                result = await showDialog<Color>(
                  context: context,
                  builder: (_) =>
                      const DesktopColourPicker(initial: Colors.blue),
                );
              },
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'bad');
    await tester.tap(find.text('Use colour'));
    await tester.pump();
    expect(find.text('Enter six HEX digits.'), findsOneWidget);
    await tester.enterText(find.byType(TextField), '187A51');
    await tester.tap(find.text('Use colour'));
    await tester.pumpAndSettle();
    expect(result, const Color(0xFF187A51));
  });
}
