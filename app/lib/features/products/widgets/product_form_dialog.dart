import 'package:carousel_slider/carousel_slider.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/utils/formatters.dart';
import '../models/product.dart';

/// Resultado del formulario: datos y fotos seleccionadas (solo al crear).
class ProductFormResult {
  const ProductFormResult({required this.data, this.images = const []});

  final ProductFormData data;
  final List<XFile> images;
}

class _SelectedProductImage {
  const _SelectedProductImage(this.file, this.bytes);

  final XFile file;
  final Uint8List bytes;
}

/// Formulario para crear o editar un producto o servicio.
class ProductFormDialog extends StatefulWidget {
  const ProductFormDialog({
    super.key,
    this.product,
    this.collectImages = false,
    this.showMargin = true,
  });

  final Product? product;

  /// Al crear, exige seleccionar al menos 3 fotos.
  final bool collectImages;

  /// El vendedor no debe ver el margen de ganancia.
  final bool showMargin;

  @override
  State<ProductFormDialog> createState() => _ProductFormDialogState();
}

class _ProductFormDialogState extends State<ProductFormDialog> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _nameController;
  late final TextEditingController _descriptionController;
  late final TextEditingController _barcodeController;
  late final TextEditingController _priceController;
  late final TextEditingController _costController;

  late String _type;

  final _imagePicker = ImagePicker();
  final List<_SelectedProductImage> _selectedImages = [];
  String? _imagesError;
  bool _pickingImages = false;
  int _currentImageIndex = 0;

  static final _amountFormatter = TextInputFormatter.withFunction((
    oldValue,
    newValue,
  ) {
    if (newValue.text.isEmpty) {
      return newValue;
    }
    final valid = RegExp(r'^\d{0,10}([.,]\d{0,2})?$');
    return valid.hasMatch(newValue.text) ? newValue : oldValue;
  });

  @override
  void initState() {
    super.initState();
    final product = widget.product;
    _type = product?.type ?? ProductTypes.product;
    _nameController = TextEditingController(text: product?.name ?? '');
    _descriptionController = TextEditingController(
      text: product?.description ?? '',
    );
    _barcodeController = TextEditingController(text: product?.barcode ?? '');
    _priceController = TextEditingController(
      text: product?.price.toStringAsFixed(2) ?? '0.00',
    );
    _costController = TextEditingController(
      text: product?.cost.toStringAsFixed(2) ?? '0.00',
    );

    _priceController.addListener(_onAmountChanged);
    _costController.addListener(_onAmountChanged);
  }

  @override
  void dispose() {
    _priceController.removeListener(_onAmountChanged);
    _costController.removeListener(_onAmountChanged);
    _nameController.dispose();
    _descriptionController.dispose();
    _barcodeController.dispose();
    _priceController.dispose();
    _costController.dispose();
    super.dispose();
  }

  double get _price => _parseAmount(_priceController.text);
  double get _cost => _parseAmount(_costController.text);
  double get _margin => _price - _cost;

  void _onAmountChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  void _onTypeChanged(String? value) {
    setState(() => _type = value ?? ProductTypes.product);
  }

  Future<void> _pickImages() async {
    if (_pickingImages) {
      return;
    }
    setState(() => _pickingImages = true);

    try {
      final files = await _imagePicker.pickMultiImage(
        maxWidth: 1600,
        imageQuality: 82,
      );
      if (files.isEmpty || !mounted) {
        return;
      }

      final remaining = 20 - _selectedImages.length;
      final selected = <_SelectedProductImage>[];
      String? error;
      for (final file in files) {
        if (selected.length >= remaining) {
          error = 'Puedes agregar hasta 20 fotos por producto.';
          break;
        }
        final bytes = await file.readAsBytes();
        if (bytes.length > 5 * 1024 * 1024) {
          error = 'Cada foto debe pesar como máximo 5 MB.';
          continue;
        }
        selected.add(_SelectedProductImage(file, bytes));
      }

      if (!mounted) {
        return;
      }
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted) {
        return;
      }
      setState(() {
        _selectedImages.addAll(selected);
        _imagesError = error;
      });
    } catch (_) {
      if (mounted) {
        setState(() => _imagesError = 'No se pudieron cargar las fotos.');
      }
    } finally {
      if (mounted) {
        setState(() => _pickingImages = false);
      }
    }
  }

  void _removeSelectedImage(int index) {
    setState(() {
      _selectedImages.removeAt(index);
      if (_currentImageIndex >= _selectedImages.length) {
        _currentImageIndex = _selectedImages.isEmpty
            ? 0
            : _selectedImages.length - 1;
      }
      _imagesError = null;
    });
  }

  void _submit() {
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }
    if (widget.collectImages && _selectedImages.length < 3) {
      setState(() => _imagesError = 'Selecciona al menos 3 fotos.');
      return;
    }

    Navigator.of(context).pop(
      ProductFormResult(
        data: ProductFormData(
          name: _nameController.text.trim(),
          description: _nullable(_descriptionController.text),
          barcode: _nullable(_barcodeController.text),
          price: _round2(_price),
          cost: _round2(_cost),
          type: _type,
        ),
        images: _selectedImages
            .map((selected) => selected.file)
            .toList(growable: false),
      ),
    );
  }

  Widget _buildImagesSection(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final count = _selectedImages.length;
    final missing = count < 3 ? 3 - count : 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text(
              'Fotos del producto',
              style: textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: count >= 3
                    ? scheme.tertiaryContainer
                    : scheme.errorContainer,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                count >= 3 ? '$count fotos' : 'Mínimo 3 · faltan $missing',
                style: textTheme.labelSmall?.copyWith(
                  color: count >= 3
                      ? scheme.onTertiaryContainer
                      : scheme.onErrorContainer,
                  fontWeight: FontWeight.w700,
                  fontSize: 10,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 170,
          child: Stack(
            fit: StackFit.expand,
            children: [
              Offstage(
                offstage: _selectedImages.isEmpty,
                child: ExcludeSemantics(
                  child: CarouselSlider.builder(
                    itemCount: count == 0 ? 1 : count,
                    options: CarouselOptions(
                      height: 170,
                      viewportFraction: 0.9,
                      enlargeCenterPage: true,
                      enableInfiniteScroll: count > 1,
                      padEnds: false,
                      onPageChanged: (index, reason) {
                        if (mounted) {
                          setState(() => _currentImageIndex = index);
                        }
                      },
                    ),
                    itemBuilder: (context, index, realIndex) {
                      if (_selectedImages.isEmpty) {
                        return const SizedBox.shrink();
                      }
                      return ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            Image.memory(
                              _selectedImages[index].bytes,
                              fit: BoxFit.cover,
                              excludeFromSemantics: true,
                            ),
                            Positioned(
                              top: 4,
                              right: 4,
                              child: Material(
                                color: Colors.black54,
                                shape: const CircleBorder(),
                                child: IconButton(
                                  tooltip: 'Quitar foto',
                                  onPressed: () => _removeSelectedImage(index),
                                  icon: const Icon(
                                    Icons.close_rounded,
                                    color: Colors.white,
                                    size: 18,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ),
              Offstage(
                offstage: _selectedImages.isNotEmpty,
                child: Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: scheme.outlineVariant),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.add_photo_alternate_outlined,
                        size: 34,
                        color: scheme.primary,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Agrega al menos 3 fotos',
                        style: textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        'JPG, PNG o WebP · máximo 5 MB por foto',
                        style: textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 10,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            OutlinedButton.icon(
              onPressed: _pickingImages || count >= 20 ? null : _pickImages,
              icon: _pickingImages
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.add_photo_alternate_outlined, size: 18),
              label: Text(
                count == 0 ? 'Seleccionar fotos' : 'Agregar más fotos',
              ),
            ),
            Offstage(
              offstage: count == 0,
              child: TextButton.icon(
                onPressed: () => _removeSelectedImage(_currentImageIndex),
                icon: const Icon(Icons.close_rounded, size: 18),
                label: const Text('Quitar foto actual'),
              ),
            ),
            Text(
              'Mínimo 3 fotos; puedes agregar más.',
              style: textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        Offstage(
          offstage: _imagesError == null,
          child: Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              _imagesError ?? '',
              style: textTheme.bodySmall?.copyWith(
                color: scheme.error,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final isEditing = widget.product != null;
    final marginPositive = _margin >= 0;
    final media = MediaQuery.sizeOf(context);
    final width = media.width < 680 ? media.width - 64 : 600.0;

    return Dialog(
      insetPadding: const EdgeInsets.all(16),
      child: SizedBox(
        width: width,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: media.height - 64),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 18, 12, 0),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        isEditing ? 'Editar producto' : 'Nuevo producto',
                        style: textTheme.headlineSmall,
                      ),
                    ),
                    IconButton(
                      tooltip: 'Cerrar',
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
              ),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        TextFormField(
                          controller: _nameController,
                          autofocus: true,
                          textInputAction: TextInputAction.next,
                          textCapitalization: TextCapitalization.sentences,
                          decoration: const InputDecoration(
                            labelText: 'Nombre',
                            hintText: 'Ej. Café americano',
                            prefixIcon: Icon(Icons.inventory_2_outlined),
                          ),
                          validator: _validateName,
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _descriptionController,
                          minLines: 2,
                          maxLines: 3,
                          textCapitalization: TextCapitalization.sentences,
                          decoration: const InputDecoration(
                            labelText: 'Descripción',
                            hintText:
                                'Detalle opcional del producto o servicio',
                            alignLabelWithHint: true,
                          ),
                          validator: _validateDescription,
                        ),
                        const SizedBox(height: 12),
                        DropdownButtonFormField<String>(
                          initialValue: _type,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            labelText: 'Tipo',
                            prefixIcon: Icon(Icons.category_outlined),
                          ),
                          items: const [
                            DropdownMenuItem(
                              value: ProductTypes.product,
                              child: Text('Producto'),
                            ),
                            DropdownMenuItem(
                              value: ProductTypes.service,
                              child: Text('Servicio'),
                            ),
                          ],
                          onChanged: _onTypeChanged,
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _barcodeController,
                          textInputAction: TextInputAction.next,
                          decoration: const InputDecoration(
                            labelText: 'Código de barras',
                            hintText: 'Opcional',
                            prefixIcon: Icon(Icons.qr_code_2_rounded),
                          ),
                          validator: _validateBarcode,
                        ),
                        const SizedBox(height: 12),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: TextFormField(
                                controller: _priceController,
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                      decimal: true,
                                    ),
                                inputFormatters: [_amountFormatter],
                                textInputAction: TextInputAction.next,
                                decoration: const InputDecoration(
                                  labelText: 'Precio',
                                  prefixText: '\$ ',
                                ),
                                validator: (value) =>
                                    _validateAmount(value, 'precio'),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: TextFormField(
                                controller: _costController,
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                      decimal: true,
                                    ),
                                inputFormatters: [_amountFormatter],
                                textInputAction: TextInputAction.next,
                                decoration: const InputDecoration(
                                  labelText: 'Costo',
                                  prefixText: '\$ ',
                                ),
                                validator: (value) =>
                                    _validateAmount(value, 'costo'),
                              ),
                            ),
                          ],
                        ),
                        if (widget.showMargin) ...[
                          const SizedBox(height: 12),
                          Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: marginPositive
                                  ? scheme.tertiaryContainer
                                  : scheme.errorContainer,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color:
                                    (marginPositive
                                            ? scheme.tertiary
                                            : scheme.error)
                                        .withValues(alpha: 0.35),
                              ),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.trending_up_rounded,
                                  color: marginPositive
                                      ? scheme.onTertiaryContainer
                                      : scheme.onErrorContainer,
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Margen calculado',
                                        style: textTheme.labelMedium?.copyWith(
                                          color: marginPositive
                                              ? scheme.onTertiaryContainer
                                              : scheme.onErrorContainer,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                      Text(
                                        'Precio − costo',
                                        style: textTheme.bodySmall?.copyWith(
                                          color: marginPositive
                                              ? scheme.onTertiaryContainer
                                              : scheme.onErrorContainer,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Text(
                                  formatMoney(_margin),
                                  style: textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w800,
                                    color: marginPositive
                                        ? scheme.onTertiaryContainer
                                        : scheme.onErrorContainer,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                        if (widget.collectImages) ...[
                          const SizedBox(height: 18),
                          _buildImagesSection(context),
                        ] else if (widget.product != null) ...[
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Icon(
                                Icons.photo_library_outlined,
                                size: 18,
                                color: scheme.onSurfaceVariant,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Las fotos se administran desde el botón Fotos del producto.',
                                  style: textTheme.bodySmall?.copyWith(
                                    color: scheme.onSurfaceVariant,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Cancelar'),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed: _submit,
                      child: Text(
                        isEditing ? 'Guardar cambios' : 'Crear producto',
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static double _parseAmount(String value) {
    return double.tryParse(value.replaceAll(',', '.')) ?? 0;
  }

  static double _round2(double value) {
    return (value * 100).roundToDouble() / 100;
  }

  static String? _nullable(String value) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  static String? _validateName(String? value) {
    final name = value?.trim() ?? '';
    if (name.length < 2) {
      return 'El nombre debe tener al menos 2 caracteres.';
    }
    if (name.length > 150) {
      return 'El nombre no puede superar 150 caracteres.';
    }
    return null;
  }

  static String? _validateDescription(String? value) {
    if ((value ?? '').length > 2000) {
      return 'La descripción no puede superar 2000 caracteres.';
    }
    return null;
  }

  static String? _validateBarcode(String? value) {
    if ((value ?? '').length > 64) {
      return 'El código de barras no puede superar 64 caracteres.';
    }
    return null;
  }

  static String? _validateAmount(String? value, String label) {
    final text = value?.trim() ?? '';
    if (text.isEmpty) {
      return 'Ingresa el $label.';
    }
    final amount = _parseAmount(text);
    if (amount < 0) {
      return 'El $label no puede ser negativo.';
    }
    return null;
  }
}
