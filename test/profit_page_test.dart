import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saleo_app/app_controller.dart';
import 'package:saleo_app/auth_service.dart';
import 'package:saleo_app/database_service.dart';
import 'package:saleo_app/models.dart';
import 'package:saleo_app/profit_page.dart';
import 'package:saleo_app/sync_service.dart';

void main() {
  for (final width in [360.0, 412.0, 800.0]) {
    testWidgets('all stock includes loose units and fits width $width', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = Size(width, 1100);
      addTearDown(() {
        tester.view.resetDevicePixelRatio();
        tester.view.resetPhysicalSize();
      });
      final controller = AppController(
        DatabaseService(),
        SyncService(),
        AuthService(),
      );
      controller.currentUser = const AppUser(
        id: 1,
        username: 'owner',
        displayName: 'Owner',
        role: UserRole.admin,
        active: true,
      );
      controller.products = const [
        Product(
          id: 1,
          name: 'Club Mini',
          code: 'CLUB',
          category: 'Drinks',
          active: true,
          currentStock: 252,
          forms: [
            SellingForm(
              id: 1,
              productId: 1,
              name: 'Crate',
              priceCents: 26000,
              active: true,
              unitsPerForm: 24,
            ),
          ],
        ),
      ];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: ProfitPage(controller: controller)),
        ),
      );
      await tester.tap(find.byType(DropdownButtonFormField<int>).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Club Mini').last);
      await tester.pumpAndSettle();
      expect(find.text('Crate'), findsOneWidget);
      expect(find.textContaining('All 252 single units'), findsOneWidget);
      await tester.ensureVisible(find.byType(TextField).at(2));
      await tester.enterText(find.byType(TextField).at(2), '230');
      await tester.pumpAndSettle();
      expect(find.text('GHS 2,730.00'), findsOneWidget);
      expect(find.text('GHS 2,415.00'), findsOneWidget);
      expect(find.text('GHS 315.00'), findsOneWidget);
      expect(tester.takeException(), isNull);
      // This is a what-if calculation, not a sale or a stock adjustment.
      expect(controller.products.single.currentStock, 252);
      expect(controller.sales, isEmpty);
      await tester.ensureVisible(find.text('Custom quantity'));
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Custom quantity'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Custom quantity'));
      await tester.pumpAndSettle();
      expect(find.text('Quantity of forms'), findsOneWidget);
      expect(find.text('GHS 30.00'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
