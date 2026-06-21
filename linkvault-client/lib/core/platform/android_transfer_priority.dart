import 'dart:io';

import 'package:flutter/services.dart';

class AndroidTransferPriority {
  const AndroidTransferPriority._();

  static const _channel = MethodChannel(
    'com.linkvault.app/transfer_priority',
  );

  static bool get isSupported => Platform.isAndroid;

  static Future<void> setForegroundRequestActive(bool active) async {
    if (!isSupported) {
      return;
    }
    await _channel.invokeMethod<void>('setForegroundRequestActive', {
      'active': active,
    });
  }
}
