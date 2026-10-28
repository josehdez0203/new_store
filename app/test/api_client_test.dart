import 'dart:convert';

import 'package:credit_store_app/core/network/api_client.dart';
import 'package:credit_store_app/core/network/api_exception.dart';
import 'package:credit_store_app/core/storage/token_storage.dart';
import 'package:credit_store_app/features/auth/providers/auth_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SharedPreferences preferences;
  late TokenStorage storage;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    preferences = await SharedPreferences.getInstance();
    storage = TokenStorage(preferences);
  });

  test('login guarda tokens y usuario autenticado', () async {
    final client = MockClient((request) async {
      expect(request.url.path, '/api/v1/auth/login');
      expect(request.method, 'POST');
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      expect(body['email'], 'admin@gmail.com');
      expect(body['password'], '123456');
      return _jsonResponse(200, {'data': _authPayload()});
    });

    final api = ApiClient(
      baseUrl: 'http://localhost:8081/api/v1',
      storage: storage,
      client: client,
    );
    final auth = AuthProvider(api: api, storage: storage);

    await auth.login(email: 'admin@gmail.com', password: '123456');

    expect(auth.status, AuthStatus.authenticated);
    expect(auth.user?.email, 'admin@gmail.com');
    expect(auth.user?.roles, ['admin']);
    expect(storage.accessToken, 'access-1');
    expect(storage.refreshToken, 'refresh-1');
  });

  test('login rechazado expone el mensaje del API', () async {
    final client = MockClient((request) async {
      return _jsonResponse(401, {
        'error': {
          'code': 'invalid_credentials',
          'message': 'Correo o contraseña incorrectos.',
        },
      });
    });

    final api = ApiClient(
      baseUrl: 'http://localhost:8081/api/v1',
      storage: storage,
      client: client,
    );
    final auth = AuthProvider(api: api, storage: storage);

    await expectLater(
      auth.login(email: 'admin@gmail.com', password: 'mala'),
      throwsA(
        isA<ApiException>()
            .having((error) => error.statusCode, 'statusCode', 401)
            .having((error) => error.code, 'code', 'invalid_credentials')
            .having(
              (error) => error.message,
              'message',
              'Correo o contraseña incorrectos.',
            ),
      ),
    );
    expect(auth.status, AuthStatus.checking);
    expect(storage.hasSession, isFalse);
  });

  test('renueva el access token automáticamente al recibir 401', () async {
    await storage.saveTokens(
      accessToken: 'access-vencido',
      refreshToken: 'refresh-viejo',
    );

    var meCalls = 0;
    final client = MockClient((request) async {
      if (request.url.path.endsWith('/auth/me')) {
        meCalls++;
        if (meCalls == 1) {
          expect(request.headers['Authorization'], 'Bearer access-vencido');
          return _jsonResponse(401, {
            'error': {
              'code': 'invalid_token',
              'message': 'El access token expiró.',
            },
          });
        }
        expect(request.headers['Authorization'], 'Bearer access-nuevo');
        return _jsonResponse(200, {'data': _userJson()});
      }

      if (request.url.path.endsWith('/auth/refresh')) {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body['refresh_token'], 'refresh-viejo');
        return _jsonResponse(200, {
          'data': {
            'access_token': 'access-nuevo',
            'refresh_token': 'refresh-nuevo',
            'token_type': 'Bearer',
            'expires_in': 900,
            'refresh_expires_in': 604800,
            'user': _userJson(),
          },
        });
      }

      fail('Ruta inesperada: ${request.url}');
    });

    final api = ApiClient(
      baseUrl: 'http://localhost:8081/api/v1',
      storage: storage,
      client: client,
    );

    final result = await api.get('/auth/me');

    expect(result.asMap['email'], 'admin@gmail.com');
    expect(meCalls, 2);
    expect(storage.accessToken, 'access-nuevo');
    expect(storage.refreshToken, 'refresh-nuevo');
  });

  test('si el refresh falla limpia la sesión y notifica', () async {
    await storage.saveTokens(
      accessToken: 'access-vencido',
      refreshToken: 'refresh-viejo',
    );

    var expiredNotified = false;
    final client = MockClient((request) async {
      if (request.url.path.endsWith('/auth/me')) {
        return _jsonResponse(401, {
          'error': {'code': 'invalid_token', 'message': 'Token inválido.'},
        });
      }
      if (request.url.path.endsWith('/auth/refresh')) {
        return _jsonResponse(401, {
          'error': {
            'code': 'invalid_refresh_token',
            'message': 'Refresh inválido.',
          },
        });
      }
      fail('Ruta inesperada: ${request.url}');
    });

    final api = ApiClient(
      baseUrl: 'http://localhost:8081/api/v1',
      storage: storage,
      client: client,
    );
    api.onSessionExpired = () => expiredNotified = true;

    await expectLater(api.get('/auth/me'), throwsA(isA<ApiException>()));

    expect(storage.hasSession, isFalse);
    expect(expiredNotified, isTrue);
  });

  test('perfil inválido expone detalles de validación', () async {
    await storage.saveTokens(accessToken: 'access', refreshToken: 'refresh');

    final client = MockClient((request) async {
      return _jsonResponse(422, {
        'error': {
          'code': 'validation_error',
          'message': 'Revisa los datos enviados.',
          'details': [
            {'field': 'email', 'message': 'Ingresa un correo válido.'},
          ],
        },
      });
    });

    final api = ApiClient(
      baseUrl: 'http://localhost:8081/api/v1',
      storage: storage,
      client: client,
    );

    try {
      await api.patch('/auth/me', body: {'email': 'no-es-correo'});
      fail('Se esperaba ApiException');
    } on ApiException catch (error) {
      expect(error.statusCode, 422);
      expect(error.details, hasLength(1));
      expect(error.details.first.field, 'email');
      expect(error.displayMessage, 'Ingresa un correo válido.');
    }
  });
}

http.Response _jsonResponse(int status, Map<String, dynamic> body) {
  return http.Response(
    jsonEncode(body),
    status,
    headers: {'content-type': 'application/json; charset=utf-8'},
  );
}

Map<String, dynamic> _authPayload() {
  return {
    'access_token': 'access-1',
    'refresh_token': 'refresh-1',
    'token_type': 'Bearer',
    'expires_in': 900,
    'refresh_expires_in': 604800,
    'user': _userJson(),
  };
}

Map<String, dynamic> _userJson() {
  return {
    'id': '10bfb55b-f409-4d9f-963e-698c59bc4f9a',
    'email': 'admin@gmail.com',
    'full_name': 'Administrador del Sistema',
    'is_active': true,
    'roles': ['admin'],
    'permissions': ['users.read', 'sales.read'],
    'last_login_at': '2026-10-26T16:00:00-06:00',
    'created_at': '2026-01-15T10:00:00Z',
    'updated_at': '2026-01-15T10:00:00Z',
  };
}
