import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saleo_app/models.dart';
import 'package:saleo_app/common_widgets.dart';

void main() {
  test('shared settings restore theme, alerts and company permissions', () {
    final settings = const InventoryPreferences().applySharedJson({
      'app_theme': 'dark',
      'notify_every_sale': true,
      'staff_can_receive_stock': true,
      'inventory_period': 'weekly',
    });
    expect(settings.theme, AppThemePreference.dark);
    expect(settings.notifyEverySale, isTrue);
    expect(settings.staffCanReceiveStock, isTrue);
    expect(settings.defaultPeriod, InventoryPeriod.weekly);
    expect(settings.toSharedJson().containsKey('printer_address'), isFalse);
    expect(settings.toSharedJson().containsKey('app_navigation'), isFalse);
  });

  test('legacy device theme serializes as supported light mode', () {
    expect(
      const InventoryPreferences(theme: AppThemePreference.system)
          .toSharedJson()['app_theme'],
      'light',
    );
  });

  testWidgets(
    'tablet side navigation cannot be overridden by old bottom setting',
    (tester) async {
      bool? side;
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(size: Size(800, 1000)),
            child: Builder(
              builder: (context) {
                side = useSideNavigation(
                  context,
                  AppNavigationPreference.bottom,
                );
                return const SizedBox();
              },
            ),
          ),
        ),
      );
      expect(side, isTrue);
    },
  );
}
