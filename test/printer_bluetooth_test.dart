import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saleo_app/printer_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const native = MethodChannel('saleo/native');
  const bluetooth = MethodChannel(
    'com.elriztechnology.unified_esc_pos_printer/methods',
  );
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  setUp(() => debugDefaultTargetPlatformOverride = TargetPlatform.android);
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    messenger.setMockMethodCallHandler(native, null);
    messenger.setMockMethodCallHandler(bluetooth, null);
  });

  test('Bluetooth off never starts a scan or displays searching', () async {
    messenger.setMockMethodCallHandler(native, (_) async => 'off');
    final service = PrinterService();
    final messages = <String>[];
    service.addListener(() => messages.add(service.message));
    await service.scanBluetooth();
    expect(service.scanning, isFalse);
    expect(service.state, SaleoPrinterState.disconnected);
    expect(service.bluetoothState, SaleoBluetoothState.off);
    expect(service.bluetoothPromptRevision, 1);
    expect(service.message, contains('Bluetooth is off'));
    expect(messages.any((message) => message.contains('Searching')), isFalse);
  });

  test('Bluetooth settings request is sent to Android', () async {
    var opened = false;
    messenger.setMockMethodCallHandler(native, (call) async {
      if (call.method == 'openBluetoothSettings') opened = true;
      return null;
    });
    final service = PrinterService();
    await service.openBluetoothSettings();
    expect(opened, isTrue);
  });

  test('Denied permission does not start a scan', () async {
    messenger.setMockMethodCallHandler(
      native,
      (_) async => 'permission_required',
    );
    var requests = 0;
    messenger.setMockMethodCallHandler(bluetooth, (call) async {
      expect(call.method, 'requestPermissions');
      requests++;
      return false;
    });
    final service = PrinterService();
    await service.scanBluetooth();
    expect(requests, 1);
    expect(service.scanning, isFalse);
    expect(service.message, contains('permission is required'));
  });
}
