import 'package:credit_store_app/app.dart';
import 'package:credit_store_app/core/network/api_client.dart';
import 'package:credit_store_app/core/storage/token_storage.dart';
import 'package:credit_store_app/features/auth/models/auth_user.dart';
import 'package:credit_store_app/features/auth/providers/auth_provider.dart';
import 'package:credit_store_app/features/settings/providers/theme_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('muestra el login cuando no hay sesión guardada', (tester) async {
    _setDesktopSize(tester);
    final harness = await _pumpApp(tester, authenticatedUser: null);

    expect(find.text('Bienvenido de nuevo'), findsOneWidget);
    expect(find.text('Ingresar'), findsOneWidget);
    expect(find.text('admin@gmail.com  ·  123456'), findsOneWidget);
    expect(find.byType(TextFormField), findsNWidgets(2));
    expect(harness.theme.isDark, isFalse);

    await tester.tap(find.byTooltip('Cambiar a tema oscuro'));
    await tester.pumpAndSettle();

    expect(harness.theme.isDark, isTrue);
    expect(harness.theme.themeLabel, 'Tokyo Night');
    final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(app.themeMode, ThemeMode.dark);
    expect(harness.preferences.getString(ThemeProvider.preferenceKey), 'dark');
  });

  testWidgets('el vendedor solo ve módulos de operación en el drawer', (
    tester,
  ) async {
    _setDesktopSize(tester);
    final user = _user(
      id: 'vendedor-1',
      email: 'vendedor@gmail.com',
      fullName: 'Vendedor Demo',
      roles: const ['vendedor'],
      permissions: const [
        'dashboard.read',
        'customers.read',
        'sales.read',
        'credits.read',
        'reports.read',
      ],
    );

    await _pumpApp(tester, authenticatedUser: user);
    expect(find.text('Apariencia'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.menu));
    await tester.pumpAndSettle();

    final drawer = find.byType(Drawer);
    expect(drawer, findsOneWidget);
    expect(
      find.descendant(of: drawer, matching: find.text('Ventas')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: drawer, matching: find.text('Clientes')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: drawer, matching: find.text('Usuarios')),
      findsNothing,
    );
    expect(
      find.descendant(of: drawer, matching: find.text('Permisos')),
      findsNothing,
    );
    expect(
      find.descendant(of: drawer, matching: find.text('Mi perfil')),
      findsOneWidget,
    );
  });

  testWidgets('el administrador ve los módulos de administración', (
    tester,
  ) async {
    _setDesktopSize(tester);
    final user = _user(
      id: 'admin-1',
      email: 'admin@gmail.com',
      fullName: 'Administrador del Sistema',
      roles: const ['admin'],
      permissions: const ['users.read', 'roles.read', 'permissions.read'],
    );

    await _pumpApp(tester, authenticatedUser: user);
    await tester.tap(find.byIcon(Icons.menu));
    await tester.pumpAndSettle();

    final drawer = find.byType(Drawer);
    expect(
      find.descendant(of: drawer, matching: find.text('Usuarios')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: drawer, matching: find.text('Roles')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: drawer, matching: find.text('Permisos')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: drawer, matching: find.text('Ventas')),
      findsNothing,
    );
  });

  testWidgets('el login se adapta a una pantalla Android compacta', (
    tester,
  ) async {
    _setMobileSize(tester);
    await _pumpApp(tester, authenticatedUser: null);

    expect(find.text('Bienvenido de nuevo'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.ensureVisible(find.text('Usar demo'));
    await tester.pumpAndSettle();

    expect(find.text('Usar demo'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('el home y el drawer se adaptan a Android', (tester) async {
    _setMobileSize(tester);
    final user = _user(
      id: 'android-1',
      email: 'vendedor@gmail.com',
      fullName: 'Vendedor Android',
      roles: const ['vendedor'],
      permissions: const [
        'customers.read',
        'sales.read',
        'credits.read',
        'reports.read',
      ],
    );

    await _pumpApp(tester, authenticatedUser: user);
    expect(find.text('Apariencia'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.byIcon(Icons.menu));
    await tester.pumpAndSettle();

    expect(find.byType(Drawer), findsOneWidget);
    expect(
      find.descendant(of: find.byType(Drawer), matching: find.text('Ventas')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}

void _setDesktopSize(WidgetTester tester) {
  tester.view.physicalSize = const Size(1280, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void _setMobileSize(WidgetTester tester) {
  tester.view.physicalSize = const Size(412, 915);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

class _Harness {
  const _Harness({required this.theme, required this.preferences});

  final ThemeProvider theme;
  final SharedPreferences preferences;
}

Future<_Harness> _pumpApp(
  WidgetTester tester, {
  required AuthUser? authenticatedUser,
}) async {
  SharedPreferences.setMockInitialValues({});
  final preferences = await SharedPreferences.getInstance();
  final storage = TokenStorage(preferences);
  final api = ApiClient(
    baseUrl: 'http://localhost:8081/api/v1',
    storage: storage,
  );
  addTearDown(api.dispose);

  final theme = ThemeProvider(preferences);
  final auth = authenticatedUser == null
      ? AuthProvider(api: api, storage: storage)
      : _FakeAuthProvider(
          fakeUser: authenticatedUser,
          api: api,
          storage: storage,
        );

  if (authenticatedUser == null) {
    await auth.restore();
  }

  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<ThemeProvider>.value(value: theme),
        ChangeNotifierProvider<AuthProvider>.value(value: auth),
        Provider<ApiClient>.value(value: api),
      ],
      child: const CreditStoreApp(),
    ),
  );
  await tester.pumpAndSettle();

  return _Harness(theme: theme, preferences: preferences);
}

AuthUser _user({
  required String id,
  required String email,
  required String fullName,
  required List<String> roles,
  required List<String> permissions,
}) {
  return AuthUser(
    id: id,
    email: email,
    fullName: fullName,
    isActive: true,
    roles: roles,
    permissions: permissions,
    createdAt: DateTime(2026, 1, 15),
  );
}

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

  @override
  String? get sessionMessage => null;

  @override
  Future<void> restore() async {}

  @override
  Future<void> logout() async {}

  @override
  Future<bool> refreshUser() async => true;

  @override
  void handleSessionExpired() {}

  @override
  void clearSessionMessage() {}
}
