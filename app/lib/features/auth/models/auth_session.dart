import 'auth_user.dart';

/// Respuesta de login/refresh del API.
class AuthSession {
  const AuthSession({
    required this.accessToken,
    required this.refreshToken,
    required this.tokenType,
    required this.expiresIn,
    required this.refreshExpiresIn,
    required this.user,
  });

  final String accessToken;
  final String refreshToken;
  final String tokenType;
  final int expiresIn;
  final int refreshExpiresIn;
  final AuthUser user;

  factory AuthSession.fromJson(Map<String, dynamic> json) {
    final rawUser = json['user'];
    return AuthSession(
      accessToken: json['access_token'] as String? ?? '',
      refreshToken: json['refresh_token'] as String? ?? '',
      tokenType: json['token_type'] as String? ?? 'Bearer',
      expiresIn: (json['expires_in'] as num?)?.toInt() ?? 0,
      refreshExpiresIn: (json['refresh_expires_in'] as num?)?.toInt() ?? 0,
      user: rawUser is Map<String, dynamic>
          ? AuthUser.fromJson(rawUser)
          : AuthUser.fromJson(
              rawUser is Map ? Map<String, dynamic>.from(rawUser) : const {},
            ),
    );
  }
}
