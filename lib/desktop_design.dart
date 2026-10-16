import 'package:flutter/material.dart';

import 'models.dart';

enum DesktopMode { white, dark }

extension DesktopModeLabel on DesktopMode {
  String get label => switch (this) {
    DesktopMode.white => 'Light',
    DesktopMode.dark => 'Dark',
  };
  Color get accent => switch (this) {
    DesktopMode.white => const Color(0xFF0869FA),
    DesktopMode.dark => const Color(0xFF0869FA),
  };
  Color get sidebar => switch (this) {
    DesktopMode.white => const Color(0xFFE3E3E3),
    DesktopMode.dark => const Color(0xFF111111),
  };
  Color get sidebarText => this == DesktopMode.dark
      ? const Color(0xFFF2F2F2)
      : const Color(0xFF151515);
  Color get sidebarSelection => this == DesktopMode.dark
      ? const Color(0xFF414244)
      : const Color(0xFFD1D1D1);
}

Color desktopAccent(InventoryPreferences preferences) =>
    switch (preferences.accent) {
      AppAccentPreference.custom => Color(
        preferences.customAccentArgb | 0xFF000000,
      ),
      AppAccentPreference.green => const Color(0xFF187A51),
      AppAccentPreference.teal => const Color(0xFF087F8C),
      AppAccentPreference.indigo => const Color(0xFF6750A4),
      AppAccentPreference.amber => const Color(0xFF995500),
      AppAccentPreference.graphite ||
      AppAccentPreference.classicBlack => const Color(0xFF555555),
      AppAccentPreference.classicWhite => const Color(0xFF777777),
      _ => const Color(0xFF0869FA),
    };

/// Keep a custom colour's hue but make its foreground legible on neutral panels.
Color readableDesktopAccent(Color colour, Color surface) {
  var result = colour.withValues(alpha: 1);
  final target = surface.computeLuminance() < .3 ? Colors.white : Colors.black;
  for (var i = 0; i < 30; i++) {
    final a = result.computeLuminance(), b = surface.computeLuminance();
    final contrast = (a > b ? (a + .05) / (b + .05) : (b + .05) / (a + .05));
    if (contrast >= 4.5) break;
    result = Color.lerp(result, target, .08)!;
  }
  return result;
}

ThemeData desktopTheme(
  DesktopMode mode, {
  Color? accent,
  double textScale = 1,
}) {
  final dark = mode == DesktopMode.dark;
  final background = dark ? const Color(0xFF0F0F0F) : const Color(0xFFE3E3E3);
  final surface = dark ? const Color(0xFF27282A) : const Color(0xFFFCFCFC);
  final text = dark ? const Color(0xFFF2F2F2) : const Color(0xFF151515);
  final muted = dark ? const Color(0xFFBEC0C5) : const Color(0xFF62666B);
  final border = dark ? const Color(0xFF414244) : const Color(0xFFDDDDDD);
  final highlight = readableDesktopAccent(accent ?? mode.accent, surface);
  final scheme =
      ColorScheme.fromSeed(
        seedColor: highlight,
        brightness: dark ? Brightness.dark : Brightness.light,
      ).copyWith(
        primary: highlight,
        onPrimary:
            ThemeData.estimateBrightnessForColor(highlight) == Brightness.dark
            ? Colors.white
            : const Color(0xFF151515),
        secondary: text,
        onSecondary: surface,
        secondaryContainer: dark
            ? const Color(0xFF343537)
            : const Color(0xFFF0F0F0),
        onSecondaryContainer: text,
        tertiary: muted,
        onTertiary: surface,
        tertiaryContainer: dark
            ? const Color(0xFF414244)
            : const Color(0xFFEFEFEF),
        onTertiaryContainer: text,
        primaryContainer: Color.alphaBlend(
          highlight.withValues(alpha: .12),
          surface,
        ),
        onPrimaryContainer: text,
        surface: surface,
        onSurface: text,
        onSurfaceVariant: muted,
        surfaceContainerLowest: background,
        surfaceContainerLow: surface,
        surfaceContainer: dark
            ? const Color(0xFF343537)
            : const Color(0xFFF0F0F0),
        surfaceContainerHigh: dark
            ? const Color(0xFF494A4C)
            : const Color(0xFFE7E7E7),
        surfaceContainerHighest: dark
            ? const Color(0xFF515254)
            : const Color(0xFFDDDDDD),
        outlineVariant: border,
        outline: border,
      );
  return ThemeData(
    useMaterial3: true,
    brightness: dark ? Brightness.dark : Brightness.light,
    fontFamily: 'Poppins',
    colorScheme: scheme,
    scaffoldBackgroundColor: background,
    visualDensity: VisualDensity.compact,
    textTheme:
        const TextTheme(
          bodyLarge: TextStyle(fontSize: 13, height: 1.3),
          bodyMedium: TextStyle(fontSize: 13, height: 1.3),
          bodySmall: TextStyle(fontSize: 12, height: 1.4),
          labelLarge: TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
          labelMedium: TextStyle(fontSize: 12),
          labelSmall: TextStyle(fontSize: 11),
          titleLarge: TextStyle(fontSize: 18, fontWeight: FontWeight.w500),
          titleMedium: TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
          titleSmall: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          headlineSmall: TextStyle(fontSize: 18, fontWeight: FontWeight.w500),
          headlineMedium: TextStyle(fontSize: 20, fontWeight: FontWeight.w500),
          headlineLarge: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w600,
            letterSpacing: -.9,
          ),
        ).apply(
          bodyColor: text,
          displayColor: text,
          fontSizeFactor: textScale.clamp(.9, 1.2),
        ),
    appBarTheme: AppBarTheme(
      backgroundColor: surface,
      foregroundColor: text,
      elevation: 0,
      surfaceTintColor: Colors.transparent,
      toolbarHeight: 52,
      titleTextStyle: TextStyle(
        fontFamily: 'Poppins',
        color: text,
        fontSize: 18,
        fontWeight: FontWeight.w500,
      ),
    ),
    cardTheme: CardThemeData(
      color: surface,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: border),
      ),
    ),
    dividerTheme: DividerThemeData(color: border),
    inputDecorationTheme: InputDecorationTheme(
      isDense: true,
      filled: true,
      fillColor: scheme.surfaceContainer,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: highlight, width: 1.5),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: text,
        foregroundColor: surface,
        minimumSize: const Size(0, 38),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(0, 36),
        foregroundColor: text,
        side: BorderSide(color: border),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
    ),
    listTileTheme: ListTileThemeData(
      dense: true,
      iconColor: muted,
      titleTextStyle: TextStyle(
        fontFamily: 'Poppins',
        color: text,
        fontSize: 13,
      ),
      subtitleTextStyle: TextStyle(
        fontFamily: 'Poppins',
        color: muted,
        fontSize: 12,
      ),
    ),
    dataTableTheme: DataTableThemeData(
      headingRowColor: WidgetStatePropertyAll(background),
      dividerThickness: 1,
      horizontalMargin: 20,
      headingRowHeight: 42,
      dataRowMinHeight: 42,
      dataRowMaxHeight: 52,
      headingTextStyle: TextStyle(
        fontFamily: 'Poppins',
        color: text,
        fontSize: 12,
        fontWeight: FontWeight.w600,
      ),
      dataTextStyle: TextStyle(
        fontFamily: 'Poppins',
        color: text,
        fontSize: 13,
      ),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: surface,
      surfaceTintColor: Colors.transparent,
      textStyle: TextStyle(fontFamily: 'Poppins', color: text, fontSize: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: surface,
      surfaceTintColor: Colors.transparent,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: scheme.surfaceContainer,
      selectedColor: scheme.primaryContainer,
      checkmarkColor: highlight,
      side: BorderSide.none,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      labelStyle: TextStyle(fontFamily: 'Poppins', fontSize: 12, color: text),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
    ),
  );
}

class SaleoBrand extends StatelessWidget {
  const SaleoBrand({super.key, this.color});
  final Color? color;
  @override
  Widget build(BuildContext context) => Row(
    children: [
      Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.primary,
          borderRadius: BorderRadius.circular(12),
        ),
        alignment: Alignment.center,
        child: Image.asset(
          'assets/branding/saleo-logo-symbol-v2.png',
          width: 34,
          height: 34,
          fit: BoxFit.contain,
        ),
      ),
      const SizedBox(width: 12),
      Flexible(
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            'saleo',
            style: TextStyle(
              color: color,
              fontSize: 23,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    ],
  );
}
