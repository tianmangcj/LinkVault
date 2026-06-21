import 'dart:io';

import 'package:flutter/services.dart';

class CurrentDevice {
  const CurrentDevice._();

  static const _deviceInfoChannel = MethodChannel(
    'com.linkvault.app/device_info',
  );

  static String get name {
    final hostname = _localHostname;
    if (_isUsableHostname(hostname)) {
      return hostname;
    }
    return _fallbackName;
  }

  static Future<String> resolveName() async {
    if (Platform.isAndroid || Platform.isIOS) {
      final nativeName = await _nativeDeviceName();
      if (_isUsableDeviceName(nativeName)) {
        return nativeName!;
      }

      final hostname = _localHostname;
      if (_isUsableHostname(hostname)) {
        return hostname;
      }

      return _fallbackName;
    }

    return name;
  }

  static String get _localHostname {
    final hostname = Platform.localHostname.trim();
    return hostname;
  }

  static String get _fallbackName {
    if (Platform.isAndroid) {
      return 'Android Device';
    }
    if (Platform.isIOS) {
      return 'iPhone';
    }
    if (Platform.isWindows) {
      return 'Windows PC';
    }
    if (Platform.isMacOS) {
      return 'Mac';
    }
    if (Platform.isLinux) {
      return 'Linux PC';
    }
    return 'LinkVault Device';
  }

  static Future<String?> _nativeDeviceName() async {
    try {
      final deviceName = await _deviceInfoChannel.invokeMethod<String>(
        'currentDeviceName',
      );
      final normalized = deviceName?.trim();
      return normalized == null || normalized.isEmpty ? null : normalized;
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }

  static bool _isUsableDeviceName(String? value) {
    if (value == null || value.isEmpty) {
      return false;
    }
    final normalized = value.toLowerCase();
    return normalized != 'localhost' &&
        normalized != 'localhost.localdomain' &&
        normalized != 'unknown';
  }

  static bool _isUsableHostname(String value) {
    if (value.isEmpty) {
      return false;
    }
    final normalized = value.toLowerCase();
    return normalized != 'localhost' &&
        normalized != 'localhost.localdomain' &&
        normalized != 'unknown';
  }

  static String get platform {
    if (Platform.isAndroid) {
      return 'android';
    }
    if (Platform.isIOS) {
      return 'ios';
    }
    if (Platform.isWindows) {
      return 'windows';
    }
    if (Platform.isMacOS) {
      return 'macos';
    }
    if (Platform.isLinux) {
      return 'linux';
    }
    return 'unknown';
  }
}
