import 'dart:convert';

import 'package:credit_store_app/core/network/api_client.dart';
import 'package:credit_store_app/core/storage/token_storage.dart';
import 'package:credit_store_app/core/theme/app_theme.dart';
import 'package:credit_store_app/features/auth/models/auth_user.dart';
import 'package:credit_store_app/features/auth/providers/auth_provider.dart';
import 'package:credit_store_app/features/sales/models/sale.dart';
import 'package:credit_store_app/features/sales/pages/sale_form_page.dart';
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

Sale _sale() {
  return Sale(
    id: 'sale-1',
    saleNumber: 'V-000001',
    clientId: 'client-1',
    clientName: 'Cliente Test',
    clientPhone: '5551112222',
    clientEmail: 'cliente@example.com',
    sellerId: 'seller-1',
    sellerName: 'Vendedor Demo',
    saleDate: DateTime(2026, 10, 27),
    status: SaleStatuses.sale,
    paymentType: PaymentTypes.cash,
    downPaymentPercent: 0,
    downPayment: 0,
    financedAmount: 0,
    monthlyInterestRate: 0,
    months: 0,
    totalInterest: 0,
    total: 5000,
    items: const [
      SaleItem(
        id: 'item-1',
        productId: 'product-1',
        productName: 'Microinversor',
        quantity: 1,
        unitPrice: 5000,
        subtotal: 5000,
      ),
    ],
    payments: const [
      SalePayment(
        id: 'payment-1',
        installmentNumber: 1,
        kind: 'contado',
        dueDate: null,
        amount: 5000,
      ),
    ],
  );
}

Map<String, dynamic> _saleJson() {
  return {
    'id': 'sale-1',
    'sale_number': 'V-000001',
    'client_id': 'client-1',
    'client_name': 'Cliente Test',
    'client_phone': '5551112222',
    'client_email': 'cliente@example.com',
    'seller_id': 'seller-1',
    'seller_name': 'Vendedor Demo',
    'sale_date': '2026-10-27',
    'status': 'venta',
    'payment_type': 'contado',
    'down_payment_percent': 0,
    'down_payment': 0,
    'financed_amount': 0,
    'monthly_interest_rate': 0,
    'months': 0,
    'total_interest': 0,
    'total': 5000,
    'items': [],
    'payments': [],
  };
}

void main() {
  testWidgets('edita una venta existente con PUT', (tester) async {
    tester.view.physicalSize = const Size(1200, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final storage = TokenStorage(preferences);
    Map<String, dynamic>? updated;

    final client = MockClient((request) async {
      if (request.method == 'GET' && request.url.path.endsWith('/customers')) {
        return http.Response(
          jsonEncode({
            'data': [
              {
                'id': 'client-1',
                'name': 'Cliente Test',
                'status': 'cliente',
                'created_at': '2026-10-01T10:00:00Z',
                'updated_at': '2026-10-01T10:00:00Z',
              },
            ],
            'meta': {'page': 1, 'page_size': 100, 'total': 1, 'total_pages': 1},
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      if (request.method == 'GET' && request.url.path.endsWith('/products')) {
        return http.Response(
          jsonEncode({
            'data': [
              {
                'id': 'product-1',
                'name': 'Microinversor',
                'description': null,
                'barcode': null,
                'price': 5000,
                'cost': 1000,
                'margin': 4000,
                'type': 'product',
                'images': [],
                'images_count': 0,
                'created_at': '2026-10-01T10:00:00Z',
                'updated_at': '2026-10-01T10:00:00Z',
              },
            ],
            'meta': {'page': 1, 'page_size': 100, 'total': 1, 'total_pages': 1},
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }
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
      if (request.method == 'GET' && request.url.path.endsWith('/users')) {
        return http.Response(
          jsonEncode({
            'data': [
              {
                'id': 'seller-1',
                'email': 'vendedor@gmail.com',
                'full_name': 'Vendedor Demo',
                'is_active': true,
                'roles': ['vendedor'],
                'created_at': '2026-10-01T10:00:00Z',
                'updated_at': '2026-10-01T10:00:00Z',
              },
            ],
            'meta': {'page': 1, 'page_size': 100, 'total': 1, 'total_pages': 1},
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      if (request.method == 'PUT' &&
          request.url.path.endsWith('/sales/sale-1')) {
        updated = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response(
          jsonEncode({'data': _saleJson()}),
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
        permissions: const ['sales.read', 'sales.create', 'sales.update'],
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
          home: SaleFormPage(sale: _sale()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Editar venta'), findsOneWidget);
    expect(find.text('Guardar cambios'), findsOneWidget);
    await tester.tap(find.text('Guardar cambios'));
    await tester.pumpAndSettle();

    expect(updated, isNotNull);
    expect(updated!['client_id'], 'client-1');
    expect(updated!['seller_id'], 'seller-1');
    expect(updated!['sale_date'], '2026-10-27');
    expect(updated!['status'], 'venta');
    expect(updated!['payment_type'], 'contado');
    final items = updated!['items'] as List;
    expect(items.single['product_id'], 'product-1');
    expect(items.single['quantity'], 1);
    expect(tester.takeException(), isNull);
  });
}
