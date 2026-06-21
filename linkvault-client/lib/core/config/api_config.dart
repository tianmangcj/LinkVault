import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

class ApiConfig {
  const ApiConfig._();

  static const configFileName = 'server.json';
  static const bundledConfigPath = 'config/server.json';
  static const defaultBaseUrl = String.fromEnvironment(
    'LINKVAULT_API_BASE_URL',
    defaultValue: 'http://localhost:8080/api/v1',
  );

  static Future<Uri> loadBaseUri() async {
    final externalConfig = await _readExternalConfig();
    if (externalConfig != null) {
      return baseUriFromConfig(externalConfig);
    }

    final bundledConfig = await _readBundledConfig();
    if (bundledConfig != null) {
      return baseUriFromConfig(bundledConfig);
    }

    return Uri.parse(defaultBaseUrl);
  }

  static Future<Map<String, dynamic>?> _readExternalConfig() async {
    for (final file in _externalConfigFiles()) {
      try {
        if (await file.exists()) {
          final content = await file.readAsString();
          return jsonDecode(content) as Map<String, dynamic>;
        }
      } catch (_) {
        return null;
      }
    }
    return null;
  }

  static List<File> _externalConfigFiles() {
    final candidates = <String>{
      'config/$configFileName',
      configFileName,
      '${File(Platform.resolvedExecutable).parent.path}/config/$configFileName',
      '${File(Platform.resolvedExecutable).parent.path}/$configFileName',
    };
    return candidates.map(File.new).toList(growable: false);
  }

  static Future<Map<String, dynamic>?> _readBundledConfig() async {
    try {
      final content = await rootBundle.loadString(bundledConfigPath);
      return jsonDecode(content) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  static Uri baseUriFromConfig(Map<String, dynamic> config) {
    final baseUrl = (config['baseUrl'] as String?)?.trim();
    if (baseUrl != null && baseUrl.isNotEmpty) {
      return Uri.parse(baseUrl);
    }

    final scheme = (config['scheme'] as String?)?.trim();
    final host = (config['host'] as String?)?.trim();
    final port = config['port'];
    final path = (config['apiPath'] as String?)?.trim();
    final normalizedPath = path == null || path.isEmpty
        ? '/api/v1'
        : (path.startsWith('/') ? path : '/$path');

    if (host == null || host.isEmpty) {
      return Uri.parse(defaultBaseUrl);
    }

    return Uri(
      scheme: scheme == null || scheme.isEmpty ? 'http' : scheme,
      host: host,
      port: port is int ? port : int.tryParse(port?.toString() ?? ''),
      path: normalizedPath,
    );
  }
}
