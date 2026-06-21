import 'package:flutter_test/flutter_test.dart';
import 'package:linkvault_client/core/config/api_config.dart';

void main() {
  test('builds base uri from host port and api path', () {
    final uri = ApiConfig.baseUriFromConfig({
      'scheme': 'http',
      'host': '192.168.1.20',
      'port': 8080,
      'apiPath': '/api/v1',
    });

    expect(uri.toString(), 'http://192.168.1.20:8080/api/v1');
  });

  test('baseUrl overrides host port fields', () {
    final uri = ApiConfig.baseUriFromConfig({
      'baseUrl': 'https://api.example.com/linkvault/api/v1',
      'host': 'localhost',
      'port': 8080,
    });

    expect(uri.toString(), 'https://api.example.com/linkvault/api/v1');
  });
}
