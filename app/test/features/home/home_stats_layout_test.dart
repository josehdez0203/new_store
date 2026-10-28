import 'dart:convert';

import 'package:credit_store_app/core/network/api_client.dart';
import 'package:credit_store_app/core/storage/token_storage.dart';
import 'package:credit_store_app/core/theme/app_theme.dart';
import 'package:credit_store_app/features/auth/models/auth_user.dart';
import 'package:credit_store_app/features/auth/providers/auth_provider.dart';
import 'package:credit_store_app/features/home/pages/home_page.dart';
import 'package:credit_store_app/features/home/widgets/stat_card.dart';
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
  testWidgets('en móvil el resumen usa dos columnas', (tester) async {
    tester.view.physicalSize = const Size(412, 915);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final storage = TokenStorage(preferences);
    final client = MockClient((request) async {
      return http.Response(
        jsonEncode({
          'data': {
            'users_total': 3,
            'users_active': 3,
            'roles_total': 3,
            'permissions_total': 35,
            'active_sessions': 2,
            'users_by_role': <Map<String, dynamic>>[],
          },
        }),
        200,
        headers: {'content-type': 'application/json'},
      );
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
          'dashboard.read',
          'products.read',
          'customers.read',
          'sales.read',
          'credits.read',
          'reports.read',
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
        child: MaterialApp(theme: AppTheme.light, home: const HomePage()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(StatCard), findsNWidgets(4));
    final grid = tester.widget<GridView>(find.byType(GridView));
    final delegate =
        grid.gridDelegate as SliverGridDelegateWithFixedCrossAxisCount;
    expect(delegate.crossAxisCount, 2);
    expect(tester.takeException(), isNull);
  });
}
