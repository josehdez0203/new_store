import 'dart:convert';
import 'dart:typed_data';

import 'package:credit_store_app/core/network/api_client.dart';
import 'package:credit_store_app/core/storage/token_storage.dart';
import 'package:credit_store_app/core/theme/app_theme.dart';
import 'package:credit_store_app/features/auth/providers/auth_provider.dart';
import 'package:credit_store_app/features/products/pages/products_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:image_picker_platform_interface/image_picker_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeImagePicker extends ImagePickerPlatform
    with MockPlatformInterfaceMixin {
  _FakeImagePicker(this.files);

  final List<XFile> files;

  @override
  Future<List<XFile>> getMultiImageWithOptions({
    MultiImagePickerOptions options = const MultiImagePickerOptions(),
  }) async {
    return files;
  }
}

Map<String, dynamic> _productJson() {
  return {
    'id': 'product-1',
    'name': 'Producto creado',
    'description': 'Descripción',
    'barcode': '123',
    'price': 10,
    'cost': 4,
    'margin': 6,
    'type': 'product',
    'images': [
      for (var index = 0; index < 3; index++)
        {
          'id': 'image-$index',
          'url': '/downloads/products/product-1/image-$index.png',
          'original_name': 'foto-$index.png',
          'mime_type': 'image/png',
          'size_bytes': 68,
          'sort_order': index,
          'created_at': '2026-10-27T14:00:00Z',
        },
    ],
    'images_count': 3,
    'created_at': '2026-10-27T14:00:00Z',
    'updated_at': '2026-10-27T14:00:00Z',
  };
}

const _adminJson = {
  'id': 'user-1',
  'email': 'admin@example.com',
  'full_name': 'Admin',
  'is_active': true,
  'roles': ['admin'],
  'permissions': [
    'dashboard.read',
    'products.read',
    'products.create',
    'products.update',
    'products.delete',
    'products.manage_images',
  ],
};

void main() {
  testWidgets('crear producto con fotos no rompe la semántica', (tester) async {
    tester.view.physicalSize = const Size(1200, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final storage = TokenStorage(preferences);
    await storage.saveTokens(accessToken: 'access', refreshToken: 'refresh');

    final originalPicker = ImagePickerPlatform.instance;
    final bytes = base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
    );
    ImagePickerPlatform.instance = _FakeImagePicker([
      for (var index = 0; index < 3; index++)
        XFile.fromData(
          Uint8List.fromList(bytes),
          name: 'foto-$index.png',
          mimeType: 'image/png',
        ),
    ]);
    addTearDown(() => ImagePickerPlatform.instance = originalPicker);

    var created = false;
    final httpClient = MockClient((request) async {
      if (request.url.path.endsWith('/auth/me')) {
        return http.Response(
          jsonEncode({'data': _adminJson}),
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      if (request.method == 'GET' && request.url.path.endsWith('/products')) {
        return http.Response(
          jsonEncode({
            'data': created ? [_productJson()] : [],
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
      if (request.method == 'POST' && request.url.path.endsWith('/products')) {
        created = true;
        return http.Response(
          jsonEncode({'data': _productJson()}),
          201,
          headers: {'content-type': 'application/json'},
        );
      }
      return http.Response('{}', 404);
    });

    final api = ApiClient(
      baseUrl: 'http://localhost:8081/api/v1',
      storage: storage,
      client: httpClient,
    );
    final auth = AuthProvider(api: api, storage: storage);
    await auth.restore();

    final handle = tester.ensureSemantics();
    addTearDown(api.dispose);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthProvider>.value(value: auth),
          Provider<ApiClient>.value(value: api),
        ],
        child: MaterialApp(theme: AppTheme.light, home: const ProductsPage()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Nuevo producto'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField).first, 'Producto creado');
    final select = find.text('Seleccionar fotos');
    await tester.tap(select);
    await tester.pumpAndSettle();

    final create = find.descendant(
      of: find.byType(Dialog),
      matching: find.text('Crear producto'),
    );
    await tester.tap(create);
    await tester.pumpAndSettle();

    handle.dispose();
  });
}
