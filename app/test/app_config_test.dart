import 'package:credit_store_app/core/config/app_config.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  tearDown(() => debugDefaultTargetPlatformOverride = null);

  test('el emulador Android usa 10.0.2.2 para llegar al host', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;

    expect(AppConfig.apiBaseUrl, 'http://10.0.2.2:8081/api/v1');
  });

  test('escritorio usa localhost por defecto', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;

    expect(AppConfig.apiBaseUrl, 'http://localhost:8081/api/v1');
  });
}
