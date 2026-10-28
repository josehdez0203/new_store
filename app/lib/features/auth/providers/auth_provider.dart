import 'package:flutter/foundation.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/storage/token_storage.dart';
import '../models/auth_session.dart';
import '../models/auth_user.dart';

enum AuthStatus { checking, authenticated, unauthenticated }

/// Estado global de autenticación.
class AuthProvider extends ChangeNotifier {
  AuthProvider({required this.api, required this.storage});

  final ApiClient api;
  final TokenStorage storage;

  AuthStatus _status = AuthStatus.checking;
  AuthUser? _user;
  String? _sessionMessage;

  AuthStatus get status => _status;
  AuthUser? get user => _user;
  bool get isAuthenticated => _status == AuthStatus.authenticated;
  String? get sessionMessage => _sessionMessage;

  /// Intenta restaurar la sesión guardada al iniciar la aplicación.
  Future<void> restore() async {
    if (!storage.hasSession) {
      _status = AuthStatus.unauthenticated;
      notifyListeners();
      return;
    }

    try {
      final result = await api.get('/auth/me');
      _user = AuthUser.fromJson(result.asMap);
      _status = AuthStatus.authenticated;
      _sessionMessage = null;
    } on ApiException catch (error) {
      if (error.statusCode == 401) {
        await storage.clear();
      } else {
        _sessionMessage = error.message;
      }
      _user = null;
      _status = AuthStatus.unauthenticated;
    } catch (_) {
      _user = null;
      _status = AuthStatus.unauthenticated;
      _sessionMessage =
          'No se pudo restaurar la sesión. Inicia sesión de nuevo.';
    }

    notifyListeners();
  }

  /// Inicia sesión. Lanza [ApiException] si el API rechaza las credenciales.
  Future<void> login({required String email, required String password}) async {
    final result = await api.post(
      '/auth/login',
      body: {'email': email.trim(), 'password': password},
      auth: false,
    );

    final session = AuthSession.fromJson(result.asMap);
    await storage.saveTokens(
      accessToken: session.accessToken,
      refreshToken: session.refreshToken,
    );

    _user = session.user;
    _status = AuthStatus.authenticated;
    _sessionMessage = null;
    notifyListeners();
  }

  /// Cierra la sesión en el API (si es posible) y limpia el estado local.
  Future<void> logout() async {
    try {
      await api.post('/auth/logout');
    } catch (_) {
      // Aunque falle la red, la sesión local debe cerrarse.
    }
    await storage.clear();
    _user = null;
    _status = AuthStatus.unauthenticated;
    _sessionMessage = null;
    notifyListeners();
  }

  /// Vuelve a consultar el perfil para refrescar roles y permisos.
  Future<bool> refreshUser() async {
    try {
      final result = await api.get('/auth/me');
      _user = AuthUser.fromJson(result.asMap);
      _status = AuthStatus.authenticated;
      notifyListeners();
      return true;
    } on ApiException catch (error) {
      if (error.statusCode != 401) {
        _sessionMessage = error.message;
        notifyListeners();
      }
      return false;
    } catch (_) {
      _sessionMessage = 'No se pudo actualizar el perfil.';
      notifyListeners();
      return false;
    }
  }

  /// Callback invocado por [ApiClient] cuando el refresh token ya no sirve.
  void handleSessionExpired() {
    _user = null;
    _status = AuthStatus.unauthenticated;
    _sessionMessage = 'Tu sesión expiró. Inicia sesión de nuevo.';
    notifyListeners();
  }

  void clearSessionMessage() {
    if (_sessionMessage == null) {
      return;
    }
    _sessionMessage = null;
    notifyListeners();
  }
}
