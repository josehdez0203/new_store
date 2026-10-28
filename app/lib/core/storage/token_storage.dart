import 'package:shared_preferences/shared_preferences.dart';

/// Persistencia local de los tokens de sesión.
///
/// Para una aplicación en producción se recomienda usar
/// `flutter_secure_storage` (Keychain / Keystore); aquí se usa
/// `shared_preferences` para que el ejemplo funcione en web, Linux y Android
/// sin dependencias nativas adicionales.
class TokenStorage {
  TokenStorage(this._preferences);

  static const String accessTokenKey = 'auth.access_token';
  static const String refreshTokenKey = 'auth.refresh_token';

  final SharedPreferences _preferences;

  String? get accessToken => _preferences.getString(accessTokenKey);
  String? get refreshToken => _preferences.getString(refreshTokenKey);

  bool get hasSession =>
      (accessToken?.isNotEmpty ?? false) || (refreshToken?.isNotEmpty ?? false);

  Future<void> saveTokens({
    required String accessToken,
    required String refreshToken,
  }) async {
    await _preferences.setString(accessTokenKey, accessToken);
    await _preferences.setString(refreshTokenKey, refreshToken);
  }

  Future<void> clear() async {
    await _preferences.remove(accessTokenKey);
    await _preferences.remove(refreshTokenKey);
  }
}
