import 'package:flutter/foundation.dart';

/// Configuración global de la aplicación.
///
/// La URL del API se puede sobreescribir al compilar:
/// `flutter run --dart-define=API_BASE_URL=http://192.168.1.10:8081/api/v1`
abstract final class AppConfig {
  static const String appName = 'CrediStore';
  static const String appSubtitle = 'Sistema de ventas a crédito';
  static const String appVersion = '1.0.0';

  static const String _configuredApiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
  );

  /// En Android el emulador accede a la máquina anfitriona mediante 10.0.2.2.
  /// En web y escritorio se usa localhost.
  static String get apiBaseUrl {
    if (_configuredApiBaseUrl.trim().isNotEmpty) {
      return _normalize(_configuredApiBaseUrl.trim());
    }
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      return 'http://192.168.100.16:8081/api/v1';
    }
    return 'http://localhost:8081/api/v1';
  }

  static String _normalize(String value) {
    return value.endsWith('/') ? value.substring(0, value.length - 1) : value;
  }
}
