import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saleo_app/admin_home.dart';
import 'package:saleo_app/app_controller.dart';
import 'package:saleo_app/auth_service.dart';
import 'package:saleo_app/database_service.dart';
import 'package:saleo_app/main.dart';
import 'package:saleo_app/models.dart';
import 'package:saleo_app/onboarding_screen.dart';
import 'package:saleo_app/sync_service.dart';

void main() {
  testWidgets('shows the offline database loading state', (tester) async {
    final controller = AppController(
      DatabaseService(),
      SyncService(),
      AuthService(),
    );

    await tester.pumpWidget(SaleoApp(controller: controller));

    expect(find.text('Starting Saleo…'), findsOneWidget);
  });

  testWidgets('shows the upgraded Saleo welcome screen', (tester) async {
    final controller = AppController(
      DatabaseService(),
      SyncService(),
      AuthService(),
    );

    await tester.pumpWidget(
      MaterialApp(home: OnboardingScreen(controller: controller)),
    );

    expect(find.textContaining('Run your business.'), findsOneWidget);
    expect(find.text('Create company'), findsOneWidget);
    expect(find.textContaining('Log in'), findsOneWidget);
  });

  testWidgets('admin dashboard uses compact cards and responsive navigation', (
    tester,
  ) async {
    final controller = AppController(
      DatabaseService(),
      SyncService(),
      AuthService(),
    );
    controller.currentUser = const AppUser(
      id: 1,
      username: 'owner',
      displayName: 'Ama',
      role: UserRole.admin,
      active: true,
    );
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1280, 800);

    await tester.pumpWidget(
      MaterialApp(home: AdminHome(controller: controller)),
    );

    expect(find.byType(NavigationRail), findsOneWidget);
    expect(find.text('Quick actions'), findsOneWidget);
    expect(find.textContaining('Good '), findsOneWidget);

    tester.view.physicalSize = const Size(390, 844);
    await tester.pumpAndSettle();

    expect(find.byType(NavigationBar), findsOneWidget);
    expect(tester.takeException(), isNull);
    final bottom = tester.widget<NavigationBar>(find.byType(NavigationBar));
    expect(
      bottom.destinations
          .cast<NavigationDestination>()
          .map((d) => d.label)
          .toList(),
      ['Dashboard', 'Products', 'Sales', 'More', 'Settings'],
    );
    await tester.tap(find.text('More'));
    await tester.pumpAndSettle();
    expect(find.text('More tools'), findsOneWidget);
    for (final label in [
      'Inventory',
      'Customers',
      'Debtors',
      'Staff',
      'Reports',
    ]) {
      expect(find.widgetWithText(ListTile, label), findsOneWidget);
    }
    await tester.tap(find.widgetWithText(ListTile, 'Debtors'));
    await tester.pumpAndSettle();
    expect(find.text('Credit control'), findsOneWidget);
    expect(
      tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
      3,
    );
    tester.view.physicalSize = const Size(800, 1024);
    await tester.pumpAndSettle();
    final rail = tester.widget<NavigationRail>(find.byType(NavigationRail));
    expect(rail.destinations.map((d) => (d.label as Text).data).toList(), [
      'Dashboard',
      'Products',
      'Inventory',
      'Sales',
      'Customers',
      'Debtors',
      'Staff',
      'Reports',
      'Profit',
      'Approvals',
      'Settings',
    ]);
    expect(rail.selectedIndex, 5);
    expect(tester.takeException(), isNull);
  });
}
