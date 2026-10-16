import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saleo_app/app_controller.dart';
import 'package:saleo_app/auth_service.dart';
import 'package:saleo_app/database_service.dart';
import 'package:saleo_app/desktop_design.dart';
import 'package:saleo_app/desktop_settings_shell.dart';
import 'package:saleo_app/main.dart';
import 'package:saleo_app/models.dart';
import 'package:saleo_app/printer_settings.dart';
import 'package:saleo_app/sync_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _FixtureDatabase extends DatabaseService {
  _FixtureDatabase(this.fixture);
  final Database fixture;
  @override
  Database get db => fixture;
}

class _Controller extends AppController {
  _Controller(DatabaseService database, {UserRole role = UserRole.receptionist})
    : super(database, SyncService(), AuthService()) {
    initializing = false;
    checkoutReady = true;
    currentCompany = CompanyPreview(companyId: 'FIXTURE', name: 'Demo Company');
    currentUser = AppUser(
      id: 1,
      username: 'fixture',
      displayName: 'Demo Staff',
      role: role,
      active: true,
    );
    syncState = AppSyncState.synced;
  }
  @override
  Future<void> saveInventoryPreferences(InventoryPreferences value) async {
    inventoryPreferences = value;
    notifyListeners();
  }

  @override
  Future<void> loadStaff({bool notify = true}) async {}
}

void main() {
  testWidgets(
    'sync notice stays in header and Settings stays visible at 768px',
    (tester) async {
      tester.view.physicalSize = const Size(1366, 768);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final db = (await tester.runAsync(
        () => databaseFactoryFfi.openDatabase(
          inMemoryDatabasePath,
          options: OpenDatabaseOptions(singleInstance: false),
        ),
      ))!;
      await tester.runAsync(
        () => db.execute(
          'CREATE TABLE app_meta(key TEXT PRIMARY KEY, value TEXT)',
        ),
      );
      final c = _Controller(_FixtureDatabase(db), role: UserRole.admin);
      await tester.pumpWidget(SaleoApp(controller: c));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 40)),
      );
      await tester.pumpAndSettle();
      final settings = find.byKey(const ValueKey('pinned-settings'));
      expect(settings, findsOneWidget);
      expect(tester.getRect(settings).bottom, lessThan(768));
      expect(find.text('Creditors'), findsNothing);
      final before = tester.getRect(
        find.byKey(const ValueKey('Dashboard')).last,
      );
      c.syncState = AppSyncState.failed;
      c.syncMessage = 'Could not refresh company data. Saved records have not been deleted.';
      c.notifyListeners();
      await tester.pumpAndSettle();
      expect(
        tester.getRect(find.byKey(const ValueKey('Dashboard')).last),
        before,
      );
      expect(
        tester.getRect(find.byKey(const ValueKey('sync-header-notice'))).bottom,
        lessThanOrEqualTo(68),
      );
      expect(tester.takeException(), isNull);
      await tester.tap(settings);
      await tester.pumpAndSettle();
      expect(find.byType(DesktopSettingsWorkspace), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      c.dispose();
      await tester.runAsync(db.close);
    },
  );
  testWidgets(
    'real app applies mode/accent to workspace, settings, printers and dialogs',
    (tester) async {
      tester.view.physicalSize = const Size(1440, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final db = (await tester.runAsync(
        () => databaseFactoryFfi.openDatabase(
          inMemoryDatabasePath,
          options: OpenDatabaseOptions(singleInstance: false),
        ),
      ))!;
      await tester.runAsync(
        () => db.execute(
          'CREATE TABLE app_meta(key TEXT PRIMARY KEY, value TEXT)',
        ),
      );
      final c = _Controller(_FixtureDatabase(db));
      final boundary = GlobalKey();
      if (const bool.fromEnvironment('SALEO_RENDER_PREVIEWS')) {
        await tester.runAsync(
          () =>
              (FontLoader('Poppins')..addFont(
                    rootBundle.load('assets/fonts/Poppins-Regular.ttf'),
                  ))
                  .load(),
        );
        await tester.runAsync(
          () =>
              (FontLoader('MaterialIcons')..addFont(
                    rootBundle.load('fonts/MaterialIcons-Regular.otf'),
                  ))
                  .load(),
        );
      }
      Future<void> preview(String name) async {
        if (!const bool.fromEnvironment('SALEO_RENDER_PREVIEWS')) return;
        await tester.runAsync(() async {
          final image =
              await (boundary.currentContext!.findRenderObject()!
                      as RenderRepaintBoundary)
                  .toImage();
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          await Directory('build/ui-previews').create(recursive: true);
          await File('build/ui-previews/$name.png')
              .writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }

      await tester.pumpWidget(
        RepaintBoundary(
          key: boundary,
          child: SaleoApp(controller: c),
        ),
      );
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 40)),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Settings').first);
      await tester.pumpAndSettle();
      expect(find.byType(DesktopSettingsWorkspace), findsOneWidget);
      expect(find.text('Sign out'), findsOneWidget);
      expect(find.byKey(const ValueKey('settings-nav-company')), findsNothing);
      await preview('settings-light');
      for (final dark in [true, false]) {
        await tester.tap(find.byKey(const ValueKey('settings-nav-appearance')));
        await tester.pumpAndSettle();
        expect(find.text('Typography'), findsNothing);
        await tester.tap(find.text(dark ? 'Dark' : 'Light'));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('accent-Green')));
        await tester.pumpAndSettle();
        final expected = desktopTheme(
          dark ? DesktopMode.dark : DesktopMode.white,
          accent: const Color(0xFF187A51),
        );
        final appearance = Theme.of(
          tester.element(find.text('Applies throughout the app')),
        );
        expect(appearance.brightness, expected.brightness);
        expect(appearance.colorScheme.primary, expected.colorScheme.primary);
        expect(appearance.textTheme.bodyMedium!.fontFamily, 'Poppins');
        await tester.tap(find.byKey(const ValueKey('settings-nav-printers')));
        await tester.pumpAndSettle();
        expect(find.byType(PrinterSettingsScreen), findsOneWidget);
        expect(
          find.byKey(const ValueKey('settings-nav-corrections')),
          findsOneWidget,
        );
        expect(find.text('Sign out'), findsOneWidget);
        final printerTheme = Theme.of(
          tester.element(find.byType(PrinterSettingsPage)),
        );
        expect(printerTheme.brightness, expected.brightness);
        expect(
          printerTheme.cardTheme.color,
          expected.colorScheme.surfaceContainer,
        );
        expect(printerTheme.colorScheme.primary, expected.colorScheme.primary);
        expect(find.text('Search'), findsNWidgets(2));
        await preview('printers-${dark ? 'dark' : 'light'}');
        await tester.tap(find.text('Sign out'));
        await tester.pumpAndSettle();
        expect(
          Theme.of(tester.element(find.byType(AlertDialog))).brightness,
          expected.brightness,
        );
        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('settings-nav-general')));
        await tester.pumpAndSettle();
        await preview('settings-${dark ? 'dark' : 'light'}');
        await tester.tap(find.text('Back to Saleo'));
        await tester.pumpAndSettle();
        final sidebar = find.byKey(const ValueKey('workspace-sidebar'));
        expect(
          Theme.of(tester.element(sidebar)).brightness,
          expected.brightness,
        );
        final sidebarWidget = tester.widget<AnimatedContainer>(sidebar);
        expect(
          (sidebarWidget.decoration! as BoxDecoration).color,
          expected.colorScheme.surfaceContainerLowest,
        );
        expect(find.text('Current sale'), findsOneWidget);
        await tester.tap(find.text('Settings').first);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(() => db.close());
      c.dispose();
    },
  );

  testWidgets(
    'admin sections are searchable and narrow settings keep navigation',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final c = _Controller(DatabaseService(), role: UserRole.admin);
      await tester.pumpWidget(
        MaterialApp(
          theme: desktopTheme(DesktopMode.white),
          home: Scaffold(
            body: DesktopSettingsWorkspace(controller: c, onClose: () {}),
          ),
        ),
      );
      expect(
        find.byKey(const ValueKey('settings-nav-company')),
        findsOneWidget,
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Find a setting'),
        'correction',
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('settings-nav-corrections')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('settings-nav-company')), findsNothing);
      tester.view.physicalSize = const Size(800, 700);
      await tester.pumpAndSettle();
      expect(find.byType(DropdownButtonFormField<String>), findsOneWidget);
      expect(find.byTooltip('Back to Saleo'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      c.dispose();
    },
  );
}
