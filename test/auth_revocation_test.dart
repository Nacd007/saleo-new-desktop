import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:saleo_app/auth_service.dart';
import 'package:saleo_app/models.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async => null);
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });
  test('revocation failure keeps token available for explicit retry', () async {
    var status = 503;
    var requests = 0;
    final auth = AuthService(
      client: MockClient((request) async {
        requests++;
        expect(request.method, 'POST');
        expect(request.url.path, '/api/v1/auth/logout');
        expect(request.headers['authorization'], 'Bearer fixture-token');
        return http.Response(jsonEncode({'signed_out': status == 200}), status);
      }),
    );
    await auth.saveSession(
      AuthenticatedMember(
        token: 'fixture-token',
        username: 'fixture',
        displayName: 'Fixture',
        role: UserRole.admin,
        company: CompanyPreview(companyId: 'ABC-123', name: 'Fixture'),
      ),
    );
    await expectLater(
      auth.revokeCurrentSession(),
      throwsA(isA<AuthException>()),
    );
    status = 200;
    await auth.revokeCurrentSession();
    await auth.clearSession();
    await auth.revokeCurrentSession();
    expect(requests, 2);
  });
}
