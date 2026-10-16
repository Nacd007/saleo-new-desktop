import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saleo_app/app_controller.dart';
import 'package:saleo_app/auth_service.dart';
import 'package:saleo_app/database_service.dart';
import 'package:saleo_app/desktop_design.dart';
import 'package:saleo_app/desktop_checkout_ui.dart';
import 'package:saleo_app/desktop_settings.dart';
import 'package:saleo_app/models.dart';
import 'package:saleo_app/receptionist_home.dart';
import 'package:saleo_app/sync_service.dart';

class AppearanceController extends AppController {
  AppearanceController()
    : super(DatabaseService(), SyncService(), AuthService());
  @override
  Future<void> saveInventoryPreferences(InventoryPreferences value) async {
    inventoryPreferences = value;
    notifyListeners();
  }
}

void main() {
  testWidgets(
    '15 text-only products and seven cart rows fit the desktop counter',
    (tester) async {
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final c = AppearanceController();
      c.inventoryPreferences = const InventoryPreferences(
        showProductImages: false,
      );
      c.products = List.generate(
        15,
        (i) => Product(
          id: i + 1,
          code: 'P$i',
          name: 'Product ${i + 1}',
          category: 'Drinks',
          active: true,
          currentStock: 120,
          forms: [
            SellingForm(
              id: i + 1,
              productId: i + 1,
              name: 'Box',
              unitsPerForm: 12,
              priceCents: 20000,
              active: true,
            ),
          ],
        ),
      );
      c.cart = [
        for (final p in c.products.take(7))
          CartLine(product: p, form: p.forms.first, quantity: 1),
      ];
      await tester.pumpWidget(
        MaterialApp(
          theme: desktopTheme(DesktopMode.white),
          home: Scaffold(body: NewSaleScreen(controller: c)),
        ),
      );
      await tester.pump();
      expect(find.byType(Image), findsNothing);
      final grid = tester.widget<GridView>(find.byType(GridView));
      expect(
        (grid.gridDelegate as SliverGridDelegateWithFixedCrossAxisCount)
            .crossAxisCount,
        3,
      );
      expect(find.text('Product 15'), findsOneWidget);
      expect(tester.getRect(find.text('Product 15')).bottom, lessThan(900));
      expect(find.byType(DesktopCartRow), findsNWidgets(7));
      expect(
        tester.getRect(find.byType(DesktopCartRow).last).bottom,
        lessThan(tester.getRect(find.text('Total price')).top),
      );
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'appearance publishes mode immediately without typography controls',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final c = AppearanceController();
      await tester.pumpWidget(
        AnimatedBuilder(
          animation: c,
          builder: (_, _) => MaterialApp(
            theme: desktopTheme(
              c.inventoryPreferences.theme == AppThemePreference.dark
                  ? DesktopMode.dark
                  : DesktopMode.white,
            ),
            home: DesktopThemesPage(controller: c),
          ),
        ),
      );
      await tester.tap(find.text('Dark'));
      await tester.pumpAndSettle();
      final theme = Theme.of(
        tester.element(find.text('Applies throughout the app')),
      );
      expect(theme.scaffoldBackgroundColor, const Color(0xFF0F0F0F));
      expect(theme.colorScheme.surface, const Color(0xFF27282A));
      expect(c.inventoryPreferences.theme, AppThemePreference.dark);
      expect(find.text('Typography'), findsNothing);
      expect(find.text('Text size'), findsNothing);
      expect(c.inventoryPreferences.textScale, 1);
      expect(tester.takeException(), isNull);
    },
  );
}
