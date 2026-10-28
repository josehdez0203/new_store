import 'dart:convert';
import 'dart:typed_data';

import 'package:credit_store_app/core/network/api_client.dart';
import 'package:credit_store_app/core/storage/token_storage.dart';
import 'package:credit_store_app/features/products/models/product.dart';
import 'package:credit_store_app/features/products/widgets/product_photos_dialog.dart';
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

Map<String, dynamic> _productJson(int imageCount) {
  return {
    'id': 'product-1',
    'name': 'Producto de prueba',
    'description': 'Descripción',
    'barcode': '123',
    'price': 10,
    'cost': 4,
    'margin': 6,
    'type': 'product',
    'images': [
      for (var index = 0; index < imageCount; index++)
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
    'images_count': imageCount,
    'created_at': '2026-10-27T14:00:00Z',
    'updated_at': '2026-10-27T14:00:00Z',
  };
}

void main() {
  testWidgets('agregar una foto no rompe la semántica', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final originalPicker = ImagePickerPlatform.instance;
    final bytes = base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
    );
    ImagePickerPlatform.instance = _FakeImagePicker([
      XFile.fromData(
        Uint8List.fromList(bytes),
        name: 'nueva.png',
        mimeType: 'image/png',
      ),
    ]);
    addTearDown(() => ImagePickerPlatform.instance = originalPicker);

    final httpClient = MockClient((request) async {
      return http.Response(
        jsonEncode({'data': _productJson(4)}),
        200,
        headers: {'content-type': 'application/json'},
      );
    });
    final api = ApiClient(
      baseUrl: 'http://localhost:8081/api/v1',
      storage: TokenStorage(preferences),
      client: httpClient,
    );
    final product = Product.fromJson(_productJson(3));
    final handle = tester.ensureSemantics();

    await tester.pumpWidget(
      MultiProvider(
        providers: [Provider<ApiClient>.value(value: api)],
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => showDialog<void>(
                  context: context,
                  barrierDismissible: false,
                  builder: (_) =>
                      ProductPhotosDialog(product: product, canManage: true),
                ),
                child: const Text('Abrir fotos'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Abrir fotos'));
    await tester.pumpAndSettle();
    final add = find.text('Agregar fotos');
    await tester.ensureVisible(add);
    await tester.pumpAndSettle();
    await tester.tap(add);
    await tester.pumpAndSettle();

    handle.dispose();
    api.dispose();
  });
}
