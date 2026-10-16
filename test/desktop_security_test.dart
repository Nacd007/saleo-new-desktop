import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:saleo_app/app_controller.dart';
import 'package:saleo_app/auth_service.dart';
import 'package:saleo_app/database_service.dart';
import 'package:saleo_app/desktop_security.dart';
import 'package:saleo_app/models.dart';
import 'package:saleo_app/sync_service.dart';

class _Database extends DatabaseService {
  int mutations = 0;
  @override
  Future<void> setProductActive(int id, bool active) async {
    mutations++;
  }

  @override
  Future<void> deleteCustomer(int id) async {
    mutations++;
  }
}

class _DelayedAuth extends AuthService {
  final response = Completer<List<StaffMember>>();
  @override
  Future<List<StaffMember>> getStaff() => response.future;
}

class _UnavailableSync extends SyncService {
  @override
  Future<bool> deleteCustomer(String phone) async => false;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('legacy local password entry point cannot authenticate', () async {
    final c = AppController(_Database(), _UnavailableSync(), AuthService());
    await expectLater(c.login('admin', '1234'), throwsA(isA<AuthException>()));
    expect(c.currentUser, isNull);
    c.dispose();
  });
  test(
    'late staff responses cannot cross an account or company switch',
    () async {
      final auth = _DelayedAuth();
      final c = AppController(_Database(), _UnavailableSync(), auth);
      c.currentUser = AppUser(
        id: 1,
        username: 'admin-a',
        displayName: 'A',
        role: UserRole.admin,
        active: true,
      );
      c.currentCompany = CompanyPreview(companyId: 'COMPANYA', name: 'A');
      final pending = c.loadStaff(notify: false);
      c.currentUser = AppUser(
        id: 2,
        username: 'admin-b',
        displayName: 'B',
        role: UserRole.admin,
        active: true,
      );
      c.currentCompany = CompanyPreview(companyId: 'COMPANYB', name: 'B');
      c.staff = const [
        StaffMember(id: 2, username: 'staff-b', displayName: 'B', active: true),
      ];
      auth.response.complete(const [
        StaffMember(id: 1, username: 'staff-a', displayName: 'A', active: true),
      ]);
      await pending;
      expect(c.staff.single.username, 'staff-b');
      c.dispose();
    },
  );
  final product = Product(
    id: 1,
    code: 'P1',
    name: 'Fixture',
    category: 'Test',
    active: true,
    forms: [],
  );
  AppController controller(
    _Database db, {
    UserRole? role,
    bool active = true,
    bool company = true,
  }) {
    final c = AppController(db, _UnavailableSync(), AuthService());
    if (role != null) {
      c.currentUser = AppUser(
        id: 1,
        username: 'fixture',
        displayName: 'Fixture',
        role: role,
        active: active,
      );
    }
    if (company) {
      c.currentCompany = CompanyPreview(
        companyId: 'COMPANY1',
        name: 'Fixture company',
      );
    }
    return c;
  }

  test('HTTPS and a single matching server are mandatory', () {
    expect(
      () => validateServerConfiguration(
        'https://api.example.com/',
        'https://api.example.com',
      ),
      returnsNormally,
    );
    for (final pair in [
      ['http://api.example.com', 'http://api.example.com'],
      ['https://api.example.com', 'https://other.example.com'],
      [
        'https://user:secret@api.example.com',
        'https://user:secret@api.example.com',
      ],
      [
        'https://api.example.com?token=value',
        'https://api.example.com?token=value',
      ],
    ]) {
      expect(
        () => validateServerConfiguration(pair[0], pair[1]),
        throwsStateError,
      );
    }
  });
  for (final role in [null, UserRole.receptionist]) {
    test('catalog mutation denies $role before touching storage', () async {
      final db = _Database();
      final c = controller(db, role: role);
      await expectLater(c.setProductActive(product, false), throwsStateError);
      expect(db.mutations, 0);
      c.dispose();
    });
  }
  test('inactive or companyless administrator cannot mutate catalog', () async {
    final db = _Database();
    for (final c in [
      controller(db, role: UserRole.admin, active: false),
      controller(db, role: UserRole.admin, company: false),
    ]) {
      await expectLater(c.setProductActive(product, false), throwsStateError);
      c.dispose();
    }
    expect(db.mutations, 0);
  });
  test('receptionist cannot change company permissions locally', () async {
    final c = controller(_Database(), role: UserRole.receptionist);
    final previous = c.inventoryPreferences;
    await expectLater(
      c.saveInventoryPreferences(
        previous.copyWith(staffCanReceiveStock: !previous.staffCanReceiveStock),
      ),
      throwsStateError,
    );
    expect(
      c.inventoryPreferences.staffCanReceiveStock,
      previous.staffCanReceiveStock,
    );
    c.dispose();
  });
  test(
    'receptionist with receiving disabled cannot create a delivery',
    () async {
      final c = controller(_Database(), role: UserRole.receptionist);
      c.inventoryPreferences = c.inventoryPreferences.copyWith(
        staffCanReceiveStock: false,
      );
      await expectLater(c.receiveStock(items: []), throwsStateError);
      c.dispose();
    },
  );
  test('failed server deletion keeps the local customer intact', () async {
    final db = _Database();
    final c = controller(db, role: UserRole.admin);
    final customer = CustomerRecord(
      id: 1,
      name: 'Fixture',
      phone: '0200000000',
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );
    await expectLater(c.deleteCustomer(customer), throwsStateError);
    expect(db.mutations, 0);
    c.dispose();
  });
  test(
    'invalid company session is refused before database switching',
    () async {
      final c = controller(_Database());
      await expectLater(
        c.acceptAuthenticatedMember(
          AuthenticatedMember(
            token: 'fixture',
            username: 'fixture',
            displayName: 'Fixture',
            role: UserRole.admin,
            company: CompanyPreview(companyId: '../COMPANY1', name: 'Fixture'),
          ),
        ),
        throwsA(isA<AuthException>()),
      );
      c.dispose();
    },
  );
}
