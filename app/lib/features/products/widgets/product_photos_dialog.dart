import 'package:carousel_slider/carousel_slider.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/api_exception.dart';
import '../models/product.dart';

/// Visor de fotos con carrusel. Si [canManage], permite agregar, reemplazar y
/// eliminar imágenes (el API exige `products.manage_images`).
class ProductPhotosDialog extends StatefulWidget {
  const ProductPhotosDialog({
    super.key,
    required this.product,
    required this.canManage,
  });

  final Product product;
  final bool canManage;

  @override
  State<ProductPhotosDialog> createState() => _ProductPhotosDialogState();
}

class _ProductPhotosDialogState extends State<ProductPhotosDialog> {
  static const int _maxImages = 20;
  static const int _maxImageBytes = 5 * 1024 * 1024;

  final _picker = ImagePicker();
  late List<ProductImage> _images;
  int _currentIndex = 0;
  bool _busy = false;
  bool _changed = false;
  String? _error;

  ProductImage? get _currentImage {
    if (_images.isEmpty) {
      return null;
    }
    final index = _currentIndex.clamp(0, _images.length - 1).toInt();
    return _images[index];
  }

  @override
  void initState() {
    super.initState();
    _images = List<ProductImage>.from(widget.product.images);
  }

  Future<void> _addImages() async {
    if (_busy || _images.length >= _maxImages) {
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final picked = await _picker.pickMultiImage(
        maxWidth: 1600,
        imageQuality: 82,
      );
      if (picked.isEmpty || !mounted) {
        return;
      }

      final remaining = _maxImages - _images.length;
      final files = <http.MultipartFile>[];
      for (final file in picked.take(remaining)) {
        final bytes = await file.readAsBytes();
        if (bytes.length > _maxImageBytes) {
          _showMessage('Cada foto debe pesar como máximo 5 MB.');
          continue;
        }
        files.add(
          http.MultipartFile.fromBytes('images', bytes, filename: file.name),
        );
      }
      if (files.isEmpty || !mounted) {
        return;
      }

      final api = context.read<ApiClient>();
      final result = await api.postMultipart(
        '/products/${widget.product.id}/images',
        fields: const {},
        files: files,
      );
      _applyProduct(Product.fromJson(result.asMap));
    } on ApiException catch (error) {
      _showMessage(error.displayMessage);
    } catch (_) {
      _showMessage('No se pudieron subir las fotos.');
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _replaceCurrent() async {
    final current = _currentImage;
    if (_busy || current == null) {
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final picked = await _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1600,
        imageQuality: 82,
      );
      if (picked == null || !mounted) {
        return;
      }

      final bytes = await picked.readAsBytes();
      if (!mounted) {
        return;
      }
      if (bytes.length > _maxImageBytes) {
        _showMessage('Cada foto debe pesar como máximo 5 MB.');
        return;
      }

      final api = context.read<ApiClient>();
      final result = await api.putMultipart(
        '/products/${widget.product.id}/images/${current.id}',
        files: [
          http.MultipartFile.fromBytes('image', bytes, filename: picked.name),
        ],
      );
      _applyProduct(Product.fromJson(result.asMap));
    } on ApiException catch (error) {
      _showMessage(error.displayMessage);
    } catch (_) {
      _showMessage('No se pudo reemplazar la foto.');
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _deleteCurrent() async {
    final current = _currentImage;
    if (_busy || current == null || _images.length <= 3) {
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Eliminar foto'),
        content: const Text(
          '¿Eliminar esta foto? El producto debe conservar al menos 3.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(dialogContext).colorScheme.error,
              foregroundColor: Theme.of(dialogContext).colorScheme.onError,
            ),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) {
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final api = context.read<ApiClient>();
      await api.delete('/products/${widget.product.id}/images/${current.id}');
      if (!mounted) {
        return;
      }
      setState(() {
        _images = List<ProductImage>.from(_images)
          ..removeWhere((image) => image.id == current.id);
        if (_currentIndex >= _images.length) {
          _currentIndex = _images.isEmpty ? 0 : _images.length - 1;
        }
        _changed = true;
        _error = null;
      });
    } on ApiException catch (error) {
      _showMessage(error.displayMessage);
    } catch (_) {
      _showMessage('No se pudo eliminar la foto.');
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  void _applyProduct(Product product) {
    if (!mounted) {
      return;
    }
    setState(() {
      _images = List<ProductImage>.from(product.images);
      if (_currentIndex >= _images.length) {
        _currentIndex = _images.isEmpty ? 0 : _images.length - 1;
      }
      _changed = true;
      _error = null;
    });
  }

  void _showMessage(String message) {
    if (!mounted) {
      return;
    }
    setState(() => _error = message);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final current = _currentImage;

    return Dialog(
      insetPadding: const EdgeInsets.all(16),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 760,
          maxHeight: MediaQuery.sizeOf(context).height - 64,
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: scheme.primaryContainer,
                      borderRadius: BorderRadius.circular(11),
                    ),
                    child: Icon(
                      Icons.photo_library_outlined,
                      color: scheme.primary,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Fotos de ${widget.product.name}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        Text(
                          '${_images.length} fotos · mínimo 3',
                          style: textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Cerrar',
                    onPressed: () => Navigator.of(context).pop(_changed),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (_images.isEmpty)
                        Container(
                          height: 220,
                          decoration: BoxDecoration(
                            color: scheme.surfaceContainerLow,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: scheme.outlineVariant),
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.image_not_supported_outlined,
                                size: 38,
                                color: scheme.onSurfaceVariant,
                              ),
                              const SizedBox(height: 8),
                              const Text('Este producto no tiene fotos.'),
                              if (widget.canManage) ...[
                                const SizedBox(height: 12),
                                FilledButton.icon(
                                  onPressed: _busy ? null : _addImages,
                                  icon: const Icon(
                                    Icons.add_photo_alternate_outlined,
                                  ),
                                  label: const Text('Agregar fotos'),
                                ),
                              ],
                            ],
                          ),
                        )
                      else
                        ExcludeSemantics(
                          child: CarouselSlider.builder(
                            itemCount: _images.length,
                            options: CarouselOptions(
                              height: 340,
                              viewportFraction: 0.92,
                              enlargeCenterPage: true,
                              enableInfiniteScroll: _images.length > 1,
                              onPageChanged: (index, reason) {
                                if (mounted) {
                                  setState(() => _currentIndex = index);
                                }
                              },
                            ),
                            itemBuilder: (context, index, realIndex) {
                              final api = context.read<ApiClient>();
                              return ClipRRect(
                                borderRadius: BorderRadius.circular(14),
                                child: ColoredBox(
                                  color: scheme.surfaceContainerLow,
                                  child: Image.network(
                                    api.resolveUrl(_images[index].url),
                                    width: double.infinity,
                                    height: double.infinity,
                                    fit: BoxFit.cover,
                                    excludeFromSemantics: true,
                                    loadingBuilder: (context, child, progress) {
                                      if (progress == null) {
                                        return child;
                                      }
                                      return const Center(
                                        child: Icon(
                                          Icons.image_outlined,
                                          size: 34,
                                        ),
                                      );
                                    },
                                    errorBuilder: (context, error, stack) {
                                      return Center(
                                        child: Column(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(
                                              Icons.broken_image_outlined,
                                              size: 34,
                                              color: scheme.error,
                                            ),
                                            const SizedBox(height: 6),
                                            const Text(
                                              'No se pudo cargar la foto',
                                            ),
                                          ],
                                        ),
                                      );
                                    },
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      Offstage(
                        offstage: _error == null,
                        child: Padding(
                          padding: const EdgeInsets.only(top: 10),
                          child: Text(
                            _error ?? '',
                            style: textTheme.bodySmall?.copyWith(
                              color: scheme.error,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                      if (_images.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text(
                          '${_currentIndex + 1} / ${_images.length}',
                          textAlign: TextAlign.center,
                          style: textTheme.labelMedium?.copyWith(
                            color: scheme.onSurfaceVariant,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Offstage(
                          offstage: current?.originalName == null,
                          child: Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Text(
                              current?.originalName ?? '',
                              textAlign: TextAlign.center,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: textTheme.bodySmall?.copyWith(
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ),
                        if (widget.canManage) ...[
                          const SizedBox(height: 14),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              FilledButton.icon(
                                onPressed: _busy || _images.length >= _maxImages
                                    ? null
                                    : _addImages,
                                icon: const Icon(
                                  Icons.add_photo_alternate_outlined,
                                ),
                                label: const Text('Agregar fotos'),
                              ),
                              OutlinedButton.icon(
                                onPressed: _busy || current == null
                                    ? null
                                    : _replaceCurrent,
                                icon: const Icon(Icons.swap_horiz_rounded),
                                label: const Text('Reemplazar'),
                              ),
                              OutlinedButton.icon(
                                onPressed:
                                    _busy ||
                                        current == null ||
                                        _images.length <= 3
                                    ? null
                                    : _deleteCurrent,
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: scheme.error,
                                  side: BorderSide(
                                    color: _images.length <= 3
                                        ? scheme.outlineVariant
                                        : scheme.error.withValues(alpha: 0.5),
                                  ),
                                ),
                                icon: const Icon(Icons.delete_outline_rounded),
                                label: const Text('Eliminar'),
                              ),
                            ],
                          ),
                          Offstage(
                            offstage: _images.length > 3,
                            child: Padding(
                              padding: const EdgeInsets.only(top: 6),
                              child: Text(
                                'Para eliminar una foto primero agrega otra; el mínimo es 3.',
                                style: textTheme.bodySmall?.copyWith(
                                  color: scheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                          ),
                          TickerMode(
                            enabled: _busy,
                            child: Offstage(
                              offstage: !_busy,
                              child: const Padding(
                                padding: EdgeInsets.only(top: 10),
                                child: LinearProgressIndicator(),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: _busy
                      ? null
                      : () => Navigator.of(context).pop(_changed),
                  child: const Text('Cerrar'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
