import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saleo_app/device_notification_service.dart';
import 'package:saleo_app/models.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const native = MethodChannel('saleo/native');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  setUp(() => debugDefaultTargetPlatformOverride = TargetPlatform.android);
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    messenger.setMockMethodCallHandler(native, null);
  });

  test('requests Android notification permission', () async {
    messenger.setMockMethodCallHandler(native, (call) async {
      expect(call.method, 'requestNotificationPermission');
      return true;
    });

    expect(await const DeviceNotificationService().requestPermission(), isTrue);
  });

  test('reads the notification tapped while the app was closed', () async {
    messenger.setMockMethodCallHandler(native, (call) async {
      expect(call.method, 'getInitialNotification');
      return 41;
    });
    expect(await const DeviceNotificationService().initialize(), 41);
  });

  test('sends notification details to Android', () async {
    MethodCall? received;
    messenger.setMockMethodCallHandler(native, (call) async {
      received = call;
      return null;
    });
    final notification = AppNotificationRecord(
      id: 41,
      type: 'low_stock',
      title: 'Low stock',
      message: 'Alomo Sachet has 9 packs left.',
      createdAt: DateTime.utc(2026, 9, 13),
      isRead: false,
    );

    await const DeviceNotificationService().show(notification);

    expect(received?.method, 'showNotification');
    expect((received?.arguments as Map)['id'], 41);
    expect((received?.arguments as Map)['type'], 'low_stock');
  });
}
