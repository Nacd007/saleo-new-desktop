import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saleo_app/app_controller.dart';
import 'package:saleo_app/auth_service.dart';
import 'package:saleo_app/database_service.dart';
import 'package:saleo_app/desktop_design.dart';
import 'package:saleo_app/desktop_drafts.dart';
import 'package:saleo_app/desktop_settings.dart';
import 'package:saleo_app/desktop_storage.dart';
import 'package:saleo_app/desktop_workspace.dart';
import 'package:saleo_app/models.dart';
import 'package:saleo_app/revenue_buckets.dart';
import 'package:saleo_app/sync_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _Controller extends AppController {
  _Controller(UserRole role)
    : super(DatabaseService(), SyncService(), AuthService()) {
    currentUser = AppUser(
      id: 1,
      username: 'fixture',
      displayName: 'Demo Staff',
      role: role,
      active: true,
    );
    currentCompany = CompanyPreview(companyId: 'FIXTURE', name: 'Demo Company');
  }
}

Sale _sale(DateTime date, int amount, {bool voided = false}) => Sale(
  id: 1,
  transactionUuid: 'fixture',
  receiptNumber: 'RCP-FIXTURE',
  receptionistId: 1,
  receptionistUsername: 'fixture',
  receptionistName: 'Demo Staff',
  deviceId: 'fixture',
  createdAt: date,
  totalCents: amount,
  paymentMethod: 'cash',
  cashCents: amount,
  mobileMoneyCents: 0,
  syncStatus: 'synced',
  voided: voided,
);

void main() {
  test('receptionist has exactly seven pages; Settings is last', () {
    expect(receptionistDesktopPages, [
      'Sell',
      'Products',
      'Receive Stock',
      'Sales',
      'Customers',
      'Debtors',
      'Settings',
    ]);
    expect(adminDesktopPages.last, 'Settings');
    expect(
      adminDesktopPages,
      containsAll(['Dashboard', 'Sell', 'Reports', 'Profit']),
    );
    expect(adminDesktopPages, isNot(contains('Creditors')));
  });
  test('two grey modes have readable sidebars and compact typography', () {
    expect(DesktopMode.values.length, 2);
    expect(DesktopMode.white.sidebar, const Color(0xFFE3E3E3));
    expect(DesktopMode.dark.sidebar, const Color(0xFF111111));
    expect(
      desktopTheme(DesktopMode.dark).scaffoldBackgroundColor,
      const Color(0xFF0F0F0F),
    );
    for (final mode in DesktopMode.values) {
      expect(desktopTheme(mode).textTheme.bodyMedium!.fontSize, 13);
    }
  });
  test(
    'long date ranges retain all revenue rather than clipping after month 24',
    () {
      final range = DateTimeRange(start: DateTime(2020), end: DateTime(2027));
      final buckets = buildRevenueBuckets([
        _sale(DateTime(2020, 2), 20000),
        _sale(DateTime(2026, 10), 35000),
        _sale(DateTime(2021), 90000, voided: true),
      ], range);
      expect(buckets.values.length, lessThanOrEqualTo(24));
      expect(buckets.values.fold<int>(0, (n, v) => n + v), 55000);
    },
  );
  test('date range includes the last day and excludes the following day', () {
    final buckets = buildRevenueBuckets([
      _sale(DateTime(2026, 10, 8, 23, 59), 15000),
      _sale(DateTime(2026, 10, 9), 50000),
    ], DateTimeRange(start: DateTime(2026, 10, 8), end: DateTime(2026, 10, 9)));
    expect(buckets.values, [15000]);
  });
  test('draft preserves unknown products visibly instead of silently deleting them', () {
    final draft = DesktopDraft.fromJson({
      'id': 'fixture',
      'name': 'Sale 1',
      'lines': [
        {
          'product_id': 2,
          'code': 'P2',
          'name': 'Product 2',
          'category': 'Beverages',
          'form_id': 3,
          'form': 'Crate',
          'units': 24,
          'price': 20000,
          'quantity': 2,
        },
      ],
    }, []);
    expect(draft.lines.length, 1);
    expect(draft.lines.first.product.active, isFalse);
    expect(draft.lines.first.form.active, isFalse);
    expect(draft.lines.first.lineTotalCents, 40000);
    expect(DesktopDraft.fromJson(draft.toJson(), []).toJson(), draft.toJson());
  });
  for (final mode in DesktopMode.values) {
    testWidgets('theme selector renders ${mode.label} at desktop size', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          theme: desktopTheme(mode),
          home: DesktopThemesPage(controller: _Controller(UserRole.admin)),
        ),
      );
      expect(find.text('Light'), findsOneWidget);
      expect(find.text('Dark'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('receptionist settings hide company mutation controls', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: desktopTheme(DesktopMode.dark),
        home: Scaffold(
          body: DesktopSettingsPage(
            controller: _Controller(UserRole.receptionist),
          ),
        ),
      ),
    );
    expect(find.text('Company details'), findsNothing);
    expect(find.text('Receipt template'), findsNothing);
    expect(find.text('Reset company'), findsNothing);
    expect(find.text('Pending receipts'), findsOneWidget);
    expect(find.text('No receipts'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  test('Windows SQLite cache is encrypted and rejects the wrong key', () async {
    final directory = await Directory.systemTemp.createTemp(
      'saleo-new-desktop-test-',
    );
    final file = File('${directory.path}/fixture.db');
    try {
      final db = await databaseFactoryFfi.openDatabase(
        file.path,
        options: OpenDatabaseOptions(
          singleInstance: false,
          onConfigure: (db) => configureEncryptedDesktopDatabase(
            db,
            'test-key-not-a-real-account-secret',
          ),
        ),
      );
      await db.execute('CREATE TABLE fixture(value TEXT)');
      await db.insert('fixture', {'value': 'financial-test-record'});
      await db.close();
      expect(
        String.fromCharCodes((await file.readAsBytes()).take(15)),
        isNot(startsWith('SQLite format 3')),
      );
      await expectLater(
        databaseFactoryFfi.openDatabase(
          file.path,
          options: OpenDatabaseOptions(
            singleInstance: false,
            onConfigure: (db) =>
                configureEncryptedDesktopDatabase(db, 'wrong-key'),
          ),
        ),
        throwsStateError,
      );
      final reopened = await databaseFactoryFfi.openDatabase(
        file.path,
        options: OpenDatabaseOptions(
          singleInstance: false,
          onConfigure: (db) => configureEncryptedDesktopDatabase(
            db,
            'test-key-not-a-real-account-secret',
          ),
        ),
      );
      expect(
        (await reopened.query('fixture')).single['value'],
        'financial-test-record',
      );
      await reopened.close();
    } finally {
      await directory.delete(recursive: true);
    }
  });
}
