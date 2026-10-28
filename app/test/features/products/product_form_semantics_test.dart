import 'dart:convert';
import 'dart:typed_data';

import 'package:credit_store_app/features/products/widgets/product_form_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker_platform_interface/image_picker_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

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

void main() {
  testWidgets('seleccionar fotos no rompe la semántica', (tester) async {
    final original = ImagePickerPlatform.instance;
    final bytes = base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
    );
    ImagePickerPlatform.instance = _FakeImagePicker([
      XFile.fromData(
        Uint8List.fromList(bytes),
        name: 'p1.png',
        mimeType: 'image/png',
      ),
      XFile.fromData(
        Uint8List.fromList(bytes),
        name: 'p2.png',
        mimeType: 'image/png',
      ),
      XFile.fromData(
        Uint8List.fromList(bytes),
        name: 'p3.png',
        mimeType: 'image/png',
      ),
    ]);

    final handle = tester.ensureSemantics();
    addTearDown(() {
      ImagePickerPlatform.instance = original;
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) => const ProductFormDialog(collectImages: true),
              ),
              child: const Text('Abrir'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Abrir'));
    await tester.pumpAndSettle();
    final select = find.text('Seleccionar fotos');
    await tester.ensureVisible(select);
    await tester.pumpAndSettle();
    await tester.tap(select);
    await tester.pumpAndSettle();

    handle.dispose();
  });
}
