import 'dart:convert';

import 'package:credit_store_app/core/network/api_client.dart';
import 'package:credit_store_app/core/storage/token_storage.dart';
import 'package:credit_store_app/core/theme/app_theme.dart';
import 'package:credit_store_app/features/auth/models/auth_user.dart';
import 'package:credit_store_app/features/auth/providers/auth_provider.dart';
import 'package:credit_store_app/features/sales/pages/credit_settings_page.dart';
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

void main() {
  testWidgets('el admin actualiza anticipos, plazos e interés', (tester) async {
    tester.view.physicalSize = const Size(1100, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final storage = TokenStorage(preferences);
    Map<String, dynamic>? updatedBody;

    final client = MockClient((request) async {
      if (request.method == 'GET' &&
          request.url.path.endsWith('/credit-settings')) {
        return http.Response(
          jsonEncode({
            'data': {
              'down_payment_options': [10, 20, 30],
              'credit_months': [3, 6, 12],
              'monthly_interest_rate': 2,
              'updated_at': '2026-10-27T10:00:00Z',
            },
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      if (request.method == 'PUT' &&
          request.url.path.endsWith('/credit-settings')) {
        updatedBody = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response(
          jsonEncode({
            'data': {
              'down_payment_options': [10, 20, 30],
              'credit_months': [3, 6, 12],
              'monthly_interest_rate': 2.5,
              'updated_at': '2026-10-27T11:00:00Z',
            },
          }),
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
        permissions: const ['credit_settings.update'],
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
        child: MaterialApp(
          theme: AppTheme.light,
          home: const CreditSettingsPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Parámetros de financiamiento'), findsOneWidget);
    await tester.enterText(find.byType(TextFormField).at(2), '2.5');
    await tester.tap(find.text('Guardar configuración'));
    await tester.pumpAndSettle();

    expect(updatedBody, isNotNull);
    expect(updatedBody!['monthly_interest_rate'], 2.5);
    expect(updatedBody!['down_payment_options'], [10, 20, 30]);
    expect(updatedBody!['credit_months'], [3, 6, 12]);
    expect(tester.takeException(), isNull);
  });
}
