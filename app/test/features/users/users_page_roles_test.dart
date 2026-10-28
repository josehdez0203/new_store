import 'dart:convert';

import 'package:credit_store_app/core/network/api_client.dart';
import 'package:credit_store_app/core/storage/token_storage.dart';
import 'package:credit_store_app/core/theme/app_theme.dart';
import 'package:credit_store_app/features/auth/models/auth_user.dart';
import 'package:credit_store_app/features/auth/providers/auth_provider.dart';
import 'package:credit_store_app/features/settings/providers/theme_provider.dart';
import 'package:credit_store_app/features/users/pages/users_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeAuthProvider extends AuthProvider {
  _FakeAuthProvider({
    required this.fakeUser,
    required super.api,
    required super.storage,
  });

  final AuthUser fakeUser;

  @override
  AuthStatus get status => AuthStatus.authenticated;

  @override
  AuthUser? get user => fakeUser;
}

Map<String, dynamic> _userJson(List<String> roles) {
  return {
    'id': 'user-1',
    'email': 'usuario@example.com',
    'full_name': 'Usuario de Prueba',
    'is_active': true,
    'roles': roles,
    'last_login_at': '2026-10-27T16:00:00Z',
    'created_at': '2026-10-01T10:00:00Z',
    'updated_at': '2026-10-27T16:00:00Z',
  };
}

List<Map<String, dynamic>> _rolesJson() {
  return [
    {
      'id': 'role-admin',
      'name': 'admin',
      'description': 'Administra el sistema',
      'is_system': true,
      'user_count': 1,
      'permission_count': 36,
    },
    {
      'id': 'role-vendedor',
      'name': 'vendedor',
      'description': 'Ventas y clientes',
      'is_system': false,
      'user_count': 1,
      'permission_count': 11,
    },
    {
      'id': 'role-cobrador',
      'name': 'cobrador',
      'description': 'Cobros y créditos',
      'is_system': false,
      'user_count': 0,
      'permission_count': 6,
    },
  ];
}

void main() {
  testWidgets('el admin puede cambiar el rol de un usuario', (tester) async {
    tester.view.physicalSize = const Size(1200, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final storage = TokenStorage(preferences);
    var currentRoles = <String>['vendedor'];
    List<String>? lastRoleIds;

    final client = MockClient((request) async {
      if (request.method == 'GET' && request.url.path.endsWith('/roles')) {
        return http.Response(
          jsonEncode({'data': _rolesJson()}),
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      if (request.method == 'GET' && request.url.path.endsWith('/users')) {
        return http.Response(
          jsonEncode({
            'data': [_userJson(currentRoles)],
            'meta': {
              'page': 1,
              'page_size': 10,
              'total': 1,
              'total_pages': 1,
            },
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      if (request.method == 'PUT' &&
          request.url.path.endsWith('/users/user-1/roles')) {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        lastRoleIds = (body['role_ids'] as List).cast<String>();
        currentRoles = ['cobrador'];
        return http.Response(
          jsonEncode({'data': _userJson(currentRoles)}),
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      return http.Response('{}', 404);
    });

    final api = ApiClient(
      baseUrl: 'http://localhost:8081/api/v1',
      storage: storage,
      client: client,
    );
    addTearDown(api.dispose);
    final theme = ThemeProvider(preferences);
    final auth = _FakeAuthProvider(
      fakeUser: AuthUser(
        id: 'admin-1',
        email: 'admin@gmail.com',
        fullName: 'Admin',
        isActive: true,
        roles: const ['admin'],
        permissions: const [
          'users.read',
          'users.create',
          'users.update',
          'users.delete',
          'users.assign_roles',
          'roles.read',
        ],
      ),
      api: api,
      storage: storage,
    );

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<ThemeProvider>.value(value: theme),
          ChangeNotifierProvider<AuthProvider>.value(value: auth),
          Provider<ApiClient>.value(value: api),
        ],
        child: MaterialApp(theme: AppTheme.light, home: const UsersPage()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Usuario de Prueba'), findsOneWidget);
    await tester.tap(find.byTooltip('Cambiar roles'));
    await tester.pumpAndSettle();

    expect(find.text('Cambiar roles'), findsWidgets);
    await tester.tap(find.text('Cobrador'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Guardar roles'));
    await tester.pumpAndSettle();

    expect(lastRoleIds, isNotNull);
    expect(lastRoleIds, contains('role-cobrador'));
    expect(tester.takeException(), isNull);
  });
}
