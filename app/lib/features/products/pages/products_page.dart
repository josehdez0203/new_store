import 'dart:async';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/utils/formatters.dart';
import '../../auth/providers/auth_provider.dart';
import '../models/product.dart';
import '../widgets/product_form_dialog.dart';
import '../widgets/product_photos_dialog.dart';

/// CRUD del catálogo de productos y servicios.
class ProductsPage extends StatefulWidget {
  const ProductsPage({super.key});

  @override
  State<ProductsPage> createState() => _ProductsPageState();
}

class _ProductsPageState extends State<ProductsPage> {
  static const int _pageSize = 10;

  final _searchController = TextEditingController();
  Timer? _searchTimer;

  List<Product> _products = const [];
  bool _loading = true;
  String? _error;
  String? _typeFilter;
  int _page = 1;
  int _total = 0;

  int get _totalPages =>
      _total == 0 ? 0 : ((_total + _pageSize - 1) ~/ _pageSize);

  bool get _hasFilters =>
      _searchController.text.trim().isNotEmpty || _typeFilter != null;

  @override
  void initState() {
    super.initState();
    _loadProducts();
  }

  @override
  void dispose() {
    _searchTimer?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadProducts({bool showSpinner = true}) async {
    if (showSpinner) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }

    final api = context.read<ApiClient>();
    final query = <String, String>{'page': '$_page', 'page_size': '$_pageSize'};
    final search = _searchController.text.trim();
    if (search.isNotEmpty) {
      query['search'] = search;
    }
    if (_typeFilter != null) {
      query['type'] = _typeFilter!;
    }

    try {
      final result = await api.get('/products', query: query);
      if (!mounted) {
        return;
      }
      final items = result.asList.map(Product.fromJson).toList(growable: false);
      final total = (result.meta?['total'] as num?)?.toInt() ?? items.length;
      setState(() {
        _products = items;
        _total = total;
        _loading = false;
        _error = null;
      });
    } on ApiException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _loading = false;
        _error = error.displayMessage;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _loading = false;
        _error = 'No se pudieron cargar los productos.';
      });
    }
  }

  void _onSearchChanged(String value) {
    _searchTimer?.cancel();
    _searchTimer = Timer(const Duration(milliseconds: 350), () {
      if (!mounted) {
        return;
      }
      setState(() => _page = 1);
      _loadProducts();
    });
  }

  void _clearSearch() {
    _searchController.clear();
    setState(() => _page = 1);
    _loadProducts();
  }

  void _onTypeChanged(String? value) {
    setState(() {
      _typeFilter = (value == null || value.isEmpty) ? null : value;
      _page = 1;
    });
    _loadProducts();
  }

  void _changePage(int page) {
    if (page < 1 || (_totalPages > 0 && page > _totalPages)) {
      return;
    }
    setState(() => _page = page);
    _loadProducts();
  }

  Future<void> _showProductForm({Product? product}) async {
    final user = context.read<AuthProvider>().user;
    final allowed = product == null
        ? (user?.hasPermission('products.create') ?? false)
        : (user?.hasPermission('products.update') ?? false);
    if (!allowed) {
      return;
    }

    final result = await showDialog<ProductFormResult>(
      context: context,
      barrierDismissible: false,
      builder: (_) =>
          ProductFormDialog(product: product, collectImages: product == null),
    );
    if (result == null || !mounted) {
      return;
    }

    final api = context.read<ApiClient>();
    final messenger = ScaffoldMessenger.of(context);

    try {
      if (product == null) {
        final files = <http.MultipartFile>[];
        for (final image in result.images) {
          final bytes = await image.readAsBytes();
          files.add(
            http.MultipartFile.fromBytes('images', bytes, filename: image.name),
          );
        }
        if (!mounted) {
          return;
        }

        await api.postMultipart(
          '/products',
          fields: result.data.toFields(),
          files: files,
        );
        if (!mounted) {
          return;
        }
        setState(() => _page = 1);
      } else {
        await api.put('/products/${product.id}', body: result.data.toJson());
      }
      if (!mounted) {
        return;
      }
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            product == null
                ? 'Producto creado correctamente.'
                : 'Producto actualizado correctamente.',
          ),
        ),
      );
      await _loadProducts(showSpinner: false);
    } on ApiException catch (error) {
      if (!mounted) {
        return;
      }
      messenger.showSnackBar(SnackBar(content: Text(error.displayMessage)));
    } catch (_) {
      if (!mounted) {
        return;
      }
      messenger.showSnackBar(
        const SnackBar(content: Text('No se pudo guardar el producto.')),
      );
    }
  }

  Future<void> _showPhotos(Product product) async {
    final user = context.read<AuthProvider>().user;
    final canManage = user?.hasPermission('products.manage_images') ?? false;
    final changed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) =>
          ProductPhotosDialog(product: product, canManage: canManage),
    );
    if (changed == true && mounted) {
      await _loadProducts(showSpinner: false);
    }
  }

  Future<void> _deleteProduct(Product product) async {
    final user = context.read<AuthProvider>().user;
    if (!(user?.hasPermission('products.delete') ?? false)) {
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        final scheme = Theme.of(dialogContext).colorScheme;
        return AlertDialog(
          title: const Text('Eliminar del catálogo'),
          content: Text(
            '¿Eliminar "${product.name}"? Dejará de aparecer en el catálogo. '
            'Esta acción no se puede deshacer desde la aplicación.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: scheme.error,
                foregroundColor: scheme.onError,
              ),
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Eliminar'),
            ),
          ],
        );
      },
    );
    if (confirmed != true || !mounted) {
      return;
    }

    final api = context.read<ApiClient>();
    final messenger = ScaffoldMessenger.of(context);
    try {
      await api.delete('/products/${product.id}');
      if (!mounted) {
        return;
      }
      if (_products.length == 1 && _page > 1) {
        setState(() => _page -= 1);
      }
      messenger.showSnackBar(
        const SnackBar(content: Text('Producto eliminado del catálogo.')),
      );
      await _loadProducts(showSpinner: false);
    } on ApiException catch (error) {
      if (!mounted) {
        return;
      }
      messenger.showSnackBar(SnackBar(content: Text(error.displayMessage)));
    } catch (_) {
      if (!mounted) {
        return;
      }
      messenger.showSnackBar(
        const SnackBar(content: Text('No se pudo eliminar el producto.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthProvider>().user;
    final canCreate = user?.hasPermission('products.create') ?? false;
    final canUpdate = user?.hasPermission('products.update') ?? false;
    final canDelete = user?.hasPermission('products.delete') ?? false;
    final canManageImages =
        user?.hasPermission('products.manage_images') ?? false;
    final canViewMargin = user?.hasPermission('products.view_margin') ?? false;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Productos'),
        actions: [
          IconButton(
            tooltip: 'Actualizar',
            onPressed: () => _loadProducts(showSpinner: false),
            icon: const Icon(Icons.refresh_rounded),
          ),
          const SizedBox(width: 8),
        ],
      ),
      floatingActionButton: canCreate
          ? FloatingActionButton.extended(
              onPressed: () => _showProductForm(),
              icon: const Icon(Icons.add_rounded),
              label: const Text('Nuevo producto'),
            )
          : null,
      body: RefreshIndicator(
        onRefresh: () => _loadProducts(showSpinner: false),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 110),
          children: [
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1280),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _FiltersBar(
                      searchController: _searchController,
                      typeFilter: _typeFilter,
                      total: _total,
                      onSearchChanged: _onSearchChanged,
                      onClearSearch: _clearSearch,
                      onTypeChanged: _onTypeChanged,
                    ),
                    const SizedBox(height: 16),
                    if (_loading && _products.isEmpty)
                      const _LoadingCard()
                    else if (_error != null)
                      _ErrorCard(
                        message: _error!,
                        onRetry: () => _loadProducts(),
                      )
                    else if (_products.isEmpty)
                      _EmptyCard(
                        hasFilters: _hasFilters,
                        canCreate: canCreate,
                        onCreate: () => _showProductForm(),
                      )
                    else ...[
                      if (_loading) const LinearProgressIndicator(),
                      if (_loading) const SizedBox(height: 8),
                      LayoutBuilder(
                        builder: (context, constraints) {
                          if (constraints.maxWidth >= 900) {
                            return _ProductsTable(
                              products: _products,
                              canUpdate: canUpdate,
                              canDelete: canDelete,
                              canManageImages: canManageImages,
                              canViewMargin: canViewMargin,
                              onEdit: (product) =>
                                  _showProductForm(product: product),
                              onDelete: _deleteProduct,
                              onPhotos: _showPhotos,
                            );
                          }
                          return _ProductsMobileList(
                            products: _products,
                            canUpdate: canUpdate,
                            canDelete: canDelete,
                            canManageImages: canManageImages,
                            canViewMargin: canViewMargin,
                            onEdit: (product) =>
                                _showProductForm(product: product),
                            onDelete: _deleteProduct,
                            onPhotos: _showPhotos,
                          );
                        },
                      ),
                      const SizedBox(height: 16),
                      _Pagination(
                        page: _page,
                        totalPages: _totalPages,
                        total: _total,
                        pageSize: _pageSize,
                        onPrevious: () => _changePage(_page - 1),
                        onNext: () => _changePage(_page + 1),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FiltersBar extends StatelessWidget {
  const _FiltersBar({
    required this.searchController,
    required this.typeFilter,
    required this.total,
    required this.onSearchChanged,
    required this.onClearSearch,
    required this.onTypeChanged,
  });

  final TextEditingController searchController;
  final String? typeFilter;
  final int total;
  final ValueChanged<String> onSearchChanged;
  final VoidCallback onClearSearch;
  final ValueChanged<String?> onTypeChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    final search = TextField(
      controller: searchController,
      onChanged: onSearchChanged,
      decoration: InputDecoration(
        hintText: 'Buscar por nombre, código o descripción...',
        prefixIcon: const Icon(Icons.search_rounded),
        suffixIcon: searchController.text.isEmpty
            ? null
            : IconButton(
                tooltip: 'Limpiar búsqueda',
                onPressed: onClearSearch,
                icon: const Icon(Icons.close_rounded),
              ),
      ),
    );

    final type = DropdownButtonFormField<String>(
      initialValue: typeFilter ?? '',
      isExpanded: true,
      decoration: const InputDecoration(
        labelText: 'Tipo',
        prefixIcon: Icon(Icons.category_outlined),
      ),
      items: const [
        DropdownMenuItem(value: '', child: Text('Todos')),
        DropdownMenuItem(value: ProductTypes.product, child: Text('Productos')),
        DropdownMenuItem(value: ProductTypes.service, child: Text('Servicios')),
      ],
      onChanged: onTypeChanged,
    );

    final counter = Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.inventory_2_outlined, size: 14, color: scheme.primary),
          const SizedBox(width: 5),
          Text(
            total == 1 ? '1 resultado' : '$total resultados',
            style: textTheme.labelSmall?.copyWith(
              color: scheme.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: LayoutBuilder(
          builder: (context, constraints) {
            if (constraints.maxWidth < 760) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  search,
                  const SizedBox(height: 12),
                  type,
                  const SizedBox(height: 12),
                  Align(alignment: Alignment.centerLeft, child: counter),
                ],
              );
            }
            return Row(
              children: [
                Expanded(flex: 3, child: search),
                const SizedBox(width: 12),
                SizedBox(width: 220, child: type),
                const SizedBox(width: 12),
                counter,
              ],
            );
          },
        ),
      ),
    );
  }
}

class _ProductsTable extends StatelessWidget {
  const _ProductsTable({
    required this.products,
    required this.canUpdate,
    required this.canDelete,
    required this.canManageImages,
    required this.canViewMargin,
    required this.onEdit,
    required this.onDelete,
    required this.onPhotos,
  });

  final List<Product> products;
  final bool canUpdate;
  final bool canDelete;
  final bool canManageImages;
  final bool canViewMargin;
  final ValueChanged<Product> onEdit;
  final ValueChanged<Product> onDelete;
  final ValueChanged<Product> onPhotos;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          showCheckboxColumn: false,
          headingRowColor: WidgetStatePropertyAll(scheme.surfaceContainerHigh),
          dataRowMinHeight: 62,
          dataRowMaxHeight: 74,
          columns: [
            const DataColumn(label: Text('Producto')),
            const DataColumn(label: Text('Código')),
            const DataColumn(label: Text('Tipo')),
            const DataColumn(label: Text('Precio'), numeric: true),
            const DataColumn(label: Text('Costo'), numeric: true),
            if (canViewMargin)
              const DataColumn(label: Text('Margen'), numeric: true),
            const DataColumn(label: Text('Acciones')),
          ],
          rows: [
            for (final product in products)
              DataRow(
                cells: [
                  DataCell(
                    SizedBox(
                      width: 270,
                      child: Row(
                        children: [
                          _ProductThumbnail(product: product, size: 40),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  product.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: textTheme.bodyMedium?.copyWith(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                if (product.description != null)
                                  Text(
                                    product.description!,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: textTheme.bodySmall?.copyWith(
                                      color: scheme.onSurfaceVariant,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  DataCell(
                    Text(
                      product.barcode ?? '—',
                      style: textTheme.bodySmall?.copyWith(
                        fontFamily: 'monospace',
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  DataCell(_TypeBadge(product: product)),
                  DataCell(Text(formatMoney(product.price))),
                  DataCell(Text(formatMoney(product.cost))),
                  if (canViewMargin)
                    DataCell(
                      Text(
                        formatMoney(product.margin),
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: product.margin >= 0
                              ? scheme.tertiary
                              : scheme.error,
                        ),
                      ),
                    ),
                  DataCell(
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          tooltip: canManageImages
                              ? 'Gestionar fotos'
                              : 'Ver fotos',
                          onPressed: () => onPhotos(product),
                          icon: const Icon(
                            Icons.photo_library_outlined,
                            size: 19,
                          ),
                        ),
                        if (canUpdate)
                          IconButton(
                            tooltip: 'Editar',
                            onPressed: () => onEdit(product),
                            icon: const Icon(Icons.edit_outlined, size: 19),
                          ),
                        if (canDelete)
                          IconButton(
                            tooltip: 'Eliminar',
                            onPressed: () => onDelete(product),
                            icon: Icon(
                              Icons.delete_outline_rounded,
                              size: 19,
                              color: scheme.error,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _ProductsMobileList extends StatelessWidget {
  const _ProductsMobileList({
    required this.products,
    required this.canUpdate,
    required this.canDelete,
    required this.canManageImages,
    required this.canViewMargin,
    required this.onEdit,
    required this.onDelete,
    required this.onPhotos,
  });

  final List<Product> products;
  final bool canUpdate;
  final bool canDelete;
  final bool canManageImages;
  final bool canViewMargin;
  final ValueChanged<Product> onEdit;
  final ValueChanged<Product> onDelete;
  final ValueChanged<Product> onPhotos;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (var index = 0; index < products.length; index++) ...[
          _ProductCard(
            product: products[index],
            canUpdate: canUpdate,
            canDelete: canDelete,
            canManageImages: canManageImages,
            canViewMargin: canViewMargin,
            onEdit: () => onEdit(products[index]),
            onDelete: () => onDelete(products[index]),
            onPhotos: () => onPhotos(products[index]),
          ),
          if (index < products.length - 1) const SizedBox(height: 10),
        ],
      ],
    );
  }
}

class _ProductCard extends StatelessWidget {
  const _ProductCard({
    required this.product,
    required this.canUpdate,
    required this.canDelete,
    required this.canManageImages,
    required this.canViewMargin,
    required this.onEdit,
    required this.onDelete,
    required this.onPhotos,
  });

  final Product product;
  final bool canUpdate;
  final bool canDelete;
  final bool canManageImages;
  final bool canViewMargin;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onPhotos;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: onPhotos,
                  child: _ProductThumbnail(product: product, size: 42),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        product.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        product.typeLabel,
                        style: textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                PopupMenuButton<String>(
                  tooltip: 'Acciones',
                  onSelected: (value) {
                    if (value == 'photos') {
                      onPhotos();
                    } else if (value == 'edit') {
                      onEdit();
                    } else if (value == 'delete') {
                      onDelete();
                    }
                  },
                  itemBuilder: (context) => [
                    PopupMenuItem(
                      value: 'photos',
                      child: ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.photo_library_outlined),
                        title: Text(
                          canManageImages ? 'Gestionar fotos' : 'Ver fotos',
                        ),
                      ),
                    ),
                    if (canUpdate)
                      const PopupMenuItem(
                        value: 'edit',
                        child: ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(Icons.edit_outlined),
                          title: Text('Editar'),
                        ),
                      ),
                    if (canDelete)
                      PopupMenuItem(
                        value: 'delete',
                        child: ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(
                            Icons.delete_outline_rounded,
                            color: scheme.error,
                          ),
                          title: Text(
                            'Eliminar',
                            style: TextStyle(color: scheme.error),
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
            if (product.description != null) ...[
              const SizedBox(height: 10),
              Text(
                product.description!,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                _TypeBadge(product: product),
                if (product.barcode != null)
                  _SmallChip(
                    icon: Icons.qr_code_2_rounded,
                    label: product.barcode!,
                  ),
              ],
            ),
            const SizedBox(height: 12),
            const Divider(height: 1),
            const SizedBox(height: 12),
            Wrap(
              spacing: 22,
              runSpacing: 10,
              children: [
                _Metric(label: 'Precio', value: formatMoney(product.price)),
                _Metric(label: 'Costo', value: formatMoney(product.cost)),
                if (canViewMargin)
                  _Metric(
                    label: 'Margen',
                    value: formatMoney(product.margin),
                    valueColor: product.margin >= 0
                        ? scheme.tertiary
                        : scheme.error,
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _TypeBadge extends StatelessWidget {
  const _TypeBadge({required this.product});

  final Product product;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isService = product.isService;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: isService ? scheme.secondaryContainer : scheme.primaryContainer,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isService
                ? Icons.design_services_rounded
                : Icons.inventory_2_rounded,
            size: 12,
            color: isService
                ? scheme.onSecondaryContainer
                : scheme.onPrimaryContainer,
          ),
          const SizedBox(width: 4),
          Text(
            product.typeLabel,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: isService
                  ? scheme.onSecondaryContainer
                  : scheme.onPrimaryContainer,
              fontWeight: FontWeight.w700,
              fontSize: 10,
            ),
          ),
        ],
      ),
    );
  }
}

class _SmallChip extends StatelessWidget {
  const _SmallChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: scheme.onSurfaceVariant),
          const SizedBox(width: 4),
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: scheme.onSurfaceVariant,
              fontSize: 10,
            ),
          ),
        ],
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value, this.valueColor});

  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: textTheme.labelSmall?.copyWith(color: scheme.onSurfaceVariant),
        ),
        const SizedBox(height: 1),
        Text(
          value,
          style: textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w700,
            color: valueColor,
          ),
        ),
      ],
    );
  }
}

class _Pagination extends StatelessWidget {
  const _Pagination({
    required this.page,
    required this.totalPages,
    required this.total,
    required this.pageSize,
    required this.onPrevious,
    required this.onNext,
  });

  final int page;
  final int totalPages;
  final int total;
  final int pageSize;
  final VoidCallback onPrevious;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final from = total == 0 ? 0 : ((page - 1) * pageSize) + 1;
    final calculatedTo = page * pageSize;
    final to = calculatedTo > total ? total : calculatedTo;

    return Row(
      children: [
        Expanded(
          child: Text(
            'Mostrando $from–$to de $total',
            style: textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ),
        IconButton(
          tooltip: 'Página anterior',
          onPressed: page > 1 ? onPrevious : null,
          icon: const Icon(Icons.chevron_left_rounded),
        ),
        Text(
          'Página $page de ${totalPages == 0 ? 1 : totalPages}',
          style: textTheme.bodySmall?.copyWith(
            color: scheme.onSurfaceVariant,
            fontWeight: FontWeight.w600,
          ),
        ),
        IconButton(
          tooltip: 'Página siguiente',
          onPressed: totalPages > 0 && page < totalPages ? onNext : null,
          icon: const Icon(Icons.chevron_right_rounded),
        ),
      ],
    );
  }
}

class _LoadingCard extends StatelessWidget {
  const _LoadingCard();

  @override
  Widget build(BuildContext context) {
    return const Card(
      child: Padding(
        padding: EdgeInsets.all(28),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2.2),
            ),
            SizedBox(width: 14),
            Text('Cargando catálogo...'),
          ],
        ),
      ),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            Icon(Icons.cloud_off_rounded, color: scheme.error),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'No se pudo cargar el catálogo',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 3),
                  Text(
                    message,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            TextButton(onPressed: onRetry, child: const Text('Reintentar')),
          ],
        ),
      ),
    );
  }
}

class _EmptyCard extends StatelessWidget {
  const _EmptyCard({
    required this.hasFilters,
    required this.canCreate,
    required this.onCreate,
  });

  final bool hasFilters;
  final bool canCreate;
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
        child: Column(
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: scheme.primaryContainer,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Icon(
                hasFilters
                    ? Icons.search_off_rounded
                    : Icons.inventory_2_outlined,
                size: 34,
                color: scheme.primary,
              ),
            ),
            const SizedBox(height: 18),
            Text(
              hasFilters
                  ? 'No se encontraron productos'
                  : 'El catálogo está vacío',
              style: textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              hasFilters
                  ? 'Prueba con otro término de búsqueda o cambia el filtro de tipo.'
                  : 'Crea el primer producto o servicio para empezar a vender.',
              textAlign: TextAlign.center,
              style: textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            if (!hasFilters && canCreate) ...[
              const SizedBox(height: 18),
              FilledButton.icon(
                onPressed: onCreate,
                icon: const Icon(Icons.add_rounded),
                label: const Text('Crear producto'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ProductThumbnail extends StatelessWidget {
  const _ProductThumbnail({required this.product, this.size = 42});

  final Product product;
  final double size;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fallback = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: product.isService
            ? scheme.secondaryContainer
            : scheme.primaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(
        product.isService
            ? Icons.design_services_rounded
            : Icons.inventory_2_rounded,
        size: size * 0.5,
        color: product.isService ? scheme.secondary : scheme.primary,
      ),
    );

    if (product.images.isEmpty) {
      return fallback;
    }

    final api = context.read<ApiClient>();
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Image.network(
        api.resolveUrl(product.images.first.url),
        width: size,
        height: size,
        fit: BoxFit.cover,
        excludeFromSemantics: true,
        errorBuilder: (context, error, stack) => fallback,
      ),
    );
  }
}
