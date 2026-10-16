import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'models.dart';

class DeviceNotificationService {
  const DeviceNotificationService();

  static const _native = MethodChannel('saleo/native');
  static final _taps = StreamController<int>.broadcast();
  Stream<int> get taps => _taps.stream;

  Future<int?> initialize() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return null;
    _native.setMethodCallHandler((call) async {
      if (call.method == 'notificationTapped' && call.arguments is int) {
        _taps.add(call.arguments as int);
      }
    });
    try {
      return await _native.invokeMethod<int>('getInitialNotification');
    } catch (_) {
      return null;
    }
  }

  Future<bool> requestPermission() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return true;
    try {
      return await _native.invokeMethod<bool>(
            'requestNotificationPermission',
          ) ??
          false;
    } catch (_) {
      return false;
    }
  }

  Future<void> show(AppNotificationRecord notification) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    try {
      await _native.invokeMethod<void>('showNotification', {
        'id': notification.id,
        'title': notification.title,
        'message': notification.message,
        'type': notification.type,
      });
    } catch (_) {
      // In-app history remains available when Android blocks an alert.
    }
  }
}
