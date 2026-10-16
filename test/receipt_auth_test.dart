import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saleo_app/app_controller.dart';
import 'package:saleo_app/auth_service.dart';
import 'package:saleo_app/database_service.dart';
import 'package:saleo_app/desktop_design.dart';
import 'package:saleo_app/desktop_icons.dart';
import 'package:saleo_app/main.dart';
import 'package:saleo_app/models.dart';
import 'package:saleo_app/onboarding_screen.dart';
import 'package:saleo_app/receipt_auth_layout.dart';
import 'package:saleo_app/sync_service.dart';

class FakeAuth extends AuthService {
  String? recovered;
  bool fail = false;
  @override
  Future<void> recoverCompanyId(String email) async {
    if (fail) throw AuthException('Please try again later.');
    recovered = email;
  }

  @override
  Future<void> requestAdminPinReset(String email) async {
    recovered = email;
  }

  @override
  Future<CompanyPreview> findCompany(String id) async =>
      CompanyPreview(companyId: id, name: 'Demo shop');
}

void main() {
  testWidgets('logged out theme follows device despite previous preference', (
    t,
  ) async {
    final c = AppController(DatabaseService(), SyncService(), FakeAuth());
    c.inventoryPreferences = const InventoryPreferences(
      theme: AppThemePreference.light,
    );
    t.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    addTearDown(t.platformDispatcher.clearPlatformBrightnessTestValue);
    await t.pumpWidget(SaleoApp(controller: c));
    expect(
      Theme.of(t.element(find.byType(ReceiptSplashScreen))).brightness,
      Brightness.dark,
    );
    expect(
      t.widget<MaterialApp>(find.byType(MaterialApp)).themeMode,
      ThemeMode.system,
    );
    await t.pumpWidget(const SizedBox());
  });

  for (final mode in [DesktopMode.white, DesktopMode.dark]) {
    testWidgets('recovery and PIN navigation works in $mode', (t) async {
      t.view.physicalSize = const Size(1280, 900);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      final auth = FakeAuth();
      final c = AppController(DatabaseService(), SyncService(), auth);
      await t.pumpWidget(
        MaterialApp(
          theme: desktopTheme(mode),
          home: OnboardingScreen(controller: c),
        ),
      );
      await t.tap(find.text('Log in'));
      await t.pumpAndSettle();
      await t.tap(find.text('Forgot company ID?'));
      await t.pumpAndSettle();
      await t.enterText(find.byKey(const ValueKey('recovery-email')), 'bad');
      await t.tap(find.text('Email company ID'));
      await t.pumpAndSettle();
      expect(find.text('Enter a valid email address'), findsOneWidget);
      await t.enterText(
        find.byKey(const ValueKey('recovery-email')),
        'owner@example.com',
      );
      auth.fail = true;
      await t.tap(find.text('Email company ID'));
      await t.pumpAndSettle();
      expect(find.text('Please try again later.'), findsOneWidget);
      auth.fail = false;
      await t.tap(find.text('Email company ID'));
      await t.pumpAndSettle();
      expect(auth.recovered, 'owner@example.com');
      expect(find.text('Check your inbox'), findsOneWidget);
      await t.tap(find.text('Back to sign in'));
      await t.pumpAndSettle();
      await t.enterText(find.byType(TextFormField).first, 'ABC-123');
      await t.tap(find.text('Continue'));
      await t.pumpAndSettle();
      await t.tap(find.text('Forgot admin PIN?'));
      await t.pumpAndSettle();
      await t.enterText(
        find.byKey(const ValueKey('recovery-email')),
        'owner@example.com',
      );
      await t.tap(find.text('Send reset link'));
      await t.pumpAndSettle();
      expect(find.text('Check your inbox'), findsOneWidget);
      await t.tap(find.text('Back to sign in'));
      await t.pumpAndSettle();
      await t.tap(find.text('Receptionist forgot PIN?'));
      await t.pumpAndSettle();
      expect(find.text('Reset your staff PIN'), findsOneWidget);
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
    });
  }

  testWidgets('custom graphics render in both modes and multiple accents', (
    t,
  ) async {
    for (final mode in DesktopMode.values) {
      for (final accent in [Colors.red, Colors.green, Colors.blue]) {
        await t.pumpWidget(
          MaterialApp(
            theme: desktopTheme(mode, accent: accent),
            home: const Scaffold(
              body: Wrap(
                children: [
                  DesktopGraphicIcon('Dashboard'),
                  DesktopGraphicIcon('Sell'),
                  DesktopGraphicIcon('Products'),
                  DesktopGraphicIcon('Inventory'),
                  DesktopGraphicIcon('Sales'),
                  DesktopGraphicIcon('Customers'),
                  DesktopGraphicIcon('Debtors'),
                  DesktopGraphicIcon('Creditors'),
                  DesktopGraphicIcon('Staff'),
                  DesktopGraphicIcon('Reports'),
                  DesktopGraphicIcon('Profit'),
                  DesktopGraphicIcon('Settings'),
                  DesktopGraphicIcon('Receive Stock'),
                ],
              ),
            ),
          ),
        );
        await t.pumpAndSettle();
        expect(t.takeException(), isNull);
      }
    }
  });
}
