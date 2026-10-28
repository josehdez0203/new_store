import 'dart:convert';

import 'package:credit_store_app/core/network/api_client.dart';
import 'package:credit_store_app/core/storage/token_storage.dart';
import 'package:credit_store_app/core/theme/app_theme.dart';
import 'package:credit_store_app/features/auth/models/auth_user.dart';
import 'package:credit_store_app/features/auth/providers/auth_provider.dart';
import 'package:credit_store_app/features/customers/pages/customers_page.dart';
import 'package:credit_store_app/features/settings/providers/theme_provider.dart';
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

Map<String, dynamic> _customerJson({required String name}) {
  return {
    'id': 'customer-1',
    'name': name,
    'address': 'Calle 1 #123',
    'city': 'Ciudad de México',
    'postal_code': '01000',
    'phone': '5551234567',
    'email': 'cliente@example.com',
    'status': 'prospecto',
    'created_at': '2026-10-01T10:00:00Z',
    'updated_at': '2026-10-27T16:00:00Z',
  };
}

void main() {
  testWidgets('el admin crea un cliente desde la pantalla', (tester) async {
    tester.view.physicalSize = const Size(1200, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final storage = TokenStorage(preferences);
    var created = false;
    Map<String, dynamic>? postedBody;

    final client = MockClient((request) async {
      if (request.method == 'GET' && request.url.path.endsWith('/customers')) {
        return http.Response(
          jsonEncode({
            'data': created ? [_customerJson(name: 'Cliente Creado')] : [],
            'meta': {
              'page': 1,
              'page_size': 10,
              'total': created ? 1 : 0,
              'total_pages': created ? 1 : 0,
            },
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      if (request.method == 'POST' && request.url.path.endsWith('/customers')) {
        created = true;
        postedBody = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response(
          jsonEncode({'data': _customerJson(name: 'Cliente Creado')}),
          201,
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
          'customers.read',
          'customers.create',
          'customers.update',
          'customers.delete',
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
        child: MaterialApp(theme: AppTheme.light, home: const CustomersPage()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Nuevo cliente'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byType(TextFormField).first,
      'Cliente Creado',
    );
    final create = find.descendant(
      of: find.byType(Dialog),
      matching: find.text('Crear cliente'),
    );
    await tester.tap(create);
    await tester.pumpAndSettle();

    expect(postedBody, isNotNull);
    expect(postedBody!['name'], 'Cliente Creado');
    expect(postedBody!['status'], 'prospecto');
    expect(find.text('Cliente Creado'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
