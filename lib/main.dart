import 'dart:async';

import 'package:flutter/material.dart';

import 'app_controller.dart';
import 'auth_service.dart';
import 'database_service.dart';
import 'onboarding_screen.dart';
import 'printer_service.dart';
import 'sync_service.dart';
import 'session_widgets.dart';
import 'notification_navigation.dart';
import 'desktop_design.dart';
import 'desktop_workspace.dart';
import 'models.dart';
import 'receipt_auth_layout.dart';

final _saleoNavigatorKey = GlobalKey<NavigatorState>();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  ErrorWidget.builder = (details) => Material(
    color: const Color(0xFFFDF2F2),
    child: SafeArea(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: const [
                Icon(Icons.error_outline, color: Color(0xFFB42318), size: 42),
                SizedBox(height: 12),
                Text(
                  'Something went wrong',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
                ),
                SizedBox(height: 8),
                Text(
                  'Please close this screen and try again. Your saved data is still protected.',
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
  final controller = AppController(
    DatabaseService(),
    SyncService(),
    AuthService(),
  );
  runApp(SaleoApp(controller: controller));
  await controller.initialize();
}

class SaleoApp extends StatelessWidget {
  const SaleoApp({super.key, required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (context, _) {
      return MaterialApp(
        title: 'Saleo New Desktop',
        navigatorKey: _saleoNavigatorKey,
        debugShowCheckedModeBanner: false,
        theme: desktopTheme(
          DesktopMode.white,
          accent: controller.currentUser == null || controller.initializing
              ? null
              : desktopAccent(controller.inventoryPreferences),
        ),
        darkTheme: desktopTheme(
          DesktopMode.dark,
          accent: controller.currentUser == null || controller.initializing
              ? null
              : desktopAccent(controller.inventoryPreferences),
        ),
        themeMode: controller.currentUser == null || controller.initializing
            ? ThemeMode.system
            : controller.inventoryPreferences.theme == AppThemePreference.dark
            ? ThemeMode.dark
            : controller.inventoryPreferences.theme == AppThemePreference.system
            ? ThemeMode.system
            : ThemeMode.light,
        builder: (context, child) {
          final media = MediaQuery.of(context);
          return MediaQuery(
            data: media.copyWith(
              textScaler: TextScaler.linear(
                media.textScaler.scale(1).clamp(.9, 1.2),
              ),
            ),
            child: NotificationNavigation(
              controller: controller,
              navigatorKey: _saleoNavigatorKey,
              child: child ?? const SizedBox.shrink(),
            ),
          );
        },
        home: _BluetoothPromptHost(
          printer: controller.printer,
          child: controller.initializing
              ? const ReceiptSplashScreen()
              : controller.currentUser == null
              ? OnboardingScreen(controller: controller)
              : controller.loadingCompanyData || !controller.checkoutReady
              ? CompanyDataLoadingScreen(controller: controller)
              : DesktopWorkspace(
                  key: ValueKey(
                    '${controller.currentCompany?.companyId}:${controller.currentUser?.username}',
                  ),
                  controller: controller,
                ),
        ),
      );
    },
  );
}

ThemeData legacySaleoTheme(
  Color accent,
  Brightness brightness, {
  bool monochrome = false,
}) {
  final dark = brightness == Brightness.dark;
  final baseScheme = ColorScheme.fromSeed(
    seedColor: accent,
    brightness: brightness,
  );
  final classicBlack = accent.toARGB32() == 0xFF303030;
  var scheme = dark
      ? baseScheme.copyWith(
          surface: classicBlack
              ? const Color(0xFF141414)
              : const Color(0xFF0B213B),
          onSurface: const Color(0xFFF6F9FF),
          onSurfaceVariant: const Color(0xFFCCD8E8),
          surfaceContainerLowest: classicBlack
              ? const Color(0xFF080808)
              : const Color(0xFF06162A),
          surfaceContainerLow: classicBlack
              ? const Color(0xFF101010)
              : const Color(0xFF0A2039),
          surfaceContainer: classicBlack
              ? const Color(0xFF181818)
              : const Color(0xFF0D2744),
          surfaceContainerHigh: classicBlack
              ? const Color(0xFF222222)
              : const Color(0xFF12304F),
          surfaceContainerHighest: classicBlack
              ? const Color(0xFF2C2C2C)
              : const Color(0xFF183957),
          outline: const Color(0xFF8296AD),
          outlineVariant: classicBlack
              ? const Color(0xFF494949)
              : const Color(0xFF405B76),
        )
      : baseScheme;
  if (monochrome) {
    final background = dark ? Colors.black : Colors.white;
    final foreground = dark ? Colors.white : Colors.black;
    scheme = scheme.copyWith(
      primary: foreground,
      onPrimary: background,
      secondary: foreground,
      onSecondary: background,
      tertiary: foreground,
      onTertiary: background,
      primaryContainer: dark
          ? const Color(0xFF242424)
          : const Color(0xFFE8E8E8),
      onPrimaryContainer: foreground,
      secondaryContainer: dark
          ? const Color(0xFF242424)
          : const Color(0xFFE8E8E8),
      onSecondaryContainer: foreground,
      surface: background,
      onSurface: foreground,
      onSurfaceVariant: dark
          ? const Color(0xFFCCCCCC)
          : const Color(0xFF444444),
      surfaceContainerLowest: background,
      surfaceContainerLow: background,
      surfaceContainer: dark
          ? const Color(0xFF141414)
          : const Color(0xFFF5F5F5),
      surfaceContainerHigh: dark
          ? const Color(0xFF202020)
          : const Color(0xFFEDEDED),
      surfaceContainerHighest: dark
          ? const Color(0xFF303030)
          : const Color(0xFFE0E0E0),
      outline: const Color(0xFF888888),
      outlineVariant: dark ? const Color(0xFF444444) : const Color(0xFFCCCCCC),
    );
  }
  final border = scheme.outlineVariant.withValues(alpha: dark ? .65 : .8);
  return ThemeData(
    useMaterial3: true,
    visualDensity: VisualDensity.standard,
    textTheme: const TextTheme(
      bodyLarge: TextStyle(fontSize: 14, height: 1.4),
      bodyMedium: TextStyle(fontSize: 14, height: 1.4),
      bodySmall: TextStyle(fontSize: 12, height: 1.4),
      labelLarge: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
      labelMedium: TextStyle(fontSize: 12),
      labelSmall: TextStyle(fontSize: 11),
      titleLarge: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
      titleMedium: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
      titleSmall: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
      headlineLarge: TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
      headlineMedium: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
      headlineSmall: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
      displayLarge: TextStyle(fontSize: 28),
      displayMedium: TextStyle(fontSize: 24),
      displaySmall: TextStyle(fontSize: 22),
    ).apply(bodyColor: scheme.onSurface, displayColor: scheme.onSurface),
    colorScheme: scheme,
    dataTableTheme: DataTableThemeData(
      headingTextStyle: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: scheme.onSurface,
      ),
      dataTextStyle: TextStyle(fontSize: 13, color: scheme.onSurface),
      headingRowHeight: 40,
      dataRowMinHeight: 40,
      dataRowMaxHeight: 48,
    ),
    listTileTheme: ListTileThemeData(
      titleTextStyle: TextStyle(fontSize: 14, color: scheme.onSurface),
      subtitleTextStyle: TextStyle(
        fontSize: 12,
        color: scheme.onSurfaceVariant,
      ),
      dense: true,
    ),
    scaffoldBackgroundColor: dark
        ? classicBlack
              ? const Color(0xFF080808)
              : const Color(0xFF07182F)
        : const Color(0xFFF7F9FC),
    appBarTheme: AppBarTheme(
      titleTextStyle: TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.w500,
        color: scheme.onSurface,
      ),
      backgroundColor: dark
          ? classicBlack
                ? const Color(0xFF101010)
                : const Color(0xFF08275D)
          : const Color(0xFFF7F9FC),
      foregroundColor: dark ? Colors.white : scheme.onSurface,
      elevation: 0,
      centerTitle: false,
      toolbarHeight: 60,
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      color: dark
          ? classicBlack
                ? const Color(0xFF141414)
                : const Color(0xFF102A46)
          : Colors.white,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: const BorderRadius.all(Radius.circular(8)),
        side: BorderSide(color: border),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      isDense: true,
      filled: true,
      fillColor: dark
          ? classicBlack
                ? const Color(0xFF1B1B1B)
                : const Color(0xFF112C49)
          : Colors.white,
      border: OutlineInputBorder(
        borderRadius: const BorderRadius.all(Radius.circular(12)),
        borderSide: BorderSide(color: border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: const BorderRadius.all(Radius.circular(12)),
        borderSide: BorderSide(color: border),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: dark ? const Color(0xFF08213E) : Colors.white,
      indicatorColor: scheme.primaryContainer,
    ),
    navigationRailTheme: NavigationRailThemeData(
      backgroundColor: dark ? const Color(0xFF08213E) : Colors.white,
      indicatorColor: scheme.primaryContainer,
    ),
    dividerTheme: DividerThemeData(color: border),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(0, 52),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        textStyle: const TextStyle(fontWeight: FontWeight.w700),
      ),
    ),
  );
}

class _BluetoothPromptHost extends StatefulWidget {
  const _BluetoothPromptHost({required this.printer, required this.child});

  final PrinterService printer;
  final Widget child;

  @override
  State<_BluetoothPromptHost> createState() => _BluetoothPromptHostState();
}

class _BluetoothPromptHostState extends State<_BluetoothPromptHost>
    with WidgetsBindingObserver {
  int _handledPromptRevision = 0;
  bool _dialogOpen = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.printer.addListener(_checkForBluetoothPrompt);
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _checkForBluetoothPrompt(),
    );
  }

  @override
  void didUpdateWidget(covariant _BluetoothPromptHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.printer == widget.printer) return;
    oldWidget.printer.removeListener(_checkForBluetoothPrompt);
    widget.printer.addListener(_checkForBluetoothPrompt);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(widget.printer.handleAppResumed());
    }
  }

  void _checkForBluetoothPrompt() {
    if (!mounted ||
        _dialogOpen ||
        !widget.printer.bluetoothOff ||
        widget.printer.bluetoothPromptRevision <= _handledPromptRevision) {
      return;
    }
    _handledPromptRevision = widget.printer.bluetoothPromptRevision;
    _dialogOpen = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final openSettings = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => AlertDialog(
          icon: const Icon(
            Icons.bluetooth_disabled_rounded,
            color: Colors.orange,
            size: 40,
          ),
          title: const Text('Bluetooth is turned off'),
          content: const Text(
            'Turn Bluetooth on so Saleo can find and reconnect to your saved receipt printer.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton.icon(
              onPressed: () => Navigator.pop(dialogContext, true),
              icon: const Icon(Icons.settings_outlined),
              label: const Text('Open Bluetooth settings'),
            ),
          ],
        ),
      );
      if (openSettings == true) {
        await widget.printer.openBluetoothSettings();
      }
      _dialogOpen = false;
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.printer.removeListener(_checkForBluetoothPrompt);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
