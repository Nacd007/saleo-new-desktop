import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saleo_app/desktop_design.dart';

void main() {
  test('one grey theme has exactly light and dark modes', () {
    expect(DesktopMode.values.length, 2);
    final light = desktopTheme(DesktopMode.white);
    final dark = desktopTheme(DesktopMode.dark);
    expect(light.scaffoldBackgroundColor, const Color(0xFFE3E3E3));
    expect(dark.scaffoldBackgroundColor, const Color(0xFF0F0F0F));
    expect(light.colorScheme.surface, const Color(0xFFFCFCFC));
    expect(dark.colorScheme.surface, const Color(0xFF27282A));
    expect(light.cardTheme.color, const Color(0xFFFCFCFC));
    expect(dark.cardTheme.color, const Color(0xFF27282A));
    expect(light.textTheme.bodyMedium?.color, const Color(0xFF151515));
    expect(dark.textTheme.bodyMedium?.color, const Color(0xFFF2F2F2));
    expect(DesktopMode.white.sidebarText, const Color(0xFF151515));
    expect(DesktopMode.dark.sidebarText, const Color(0xFFF2F2F2));
    expect(
      (light.cardTheme.shape as RoundedRectangleBorder).borderRadius,
      BorderRadius.circular(16),
    );
    expect(
      (dark.dialogTheme.shape as RoundedRectangleBorder).borderRadius,
      BorderRadius.circular(28),
    );
    expect(light.textTheme.bodyMedium?.fontFamily, 'Poppins');
  });
}
