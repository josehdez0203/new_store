import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/utils/formatters.dart';
import '../../auth/providers/auth_provider.dart';
import '../models/sale.dart';
import 'credit_settings_page.dart';
import 'sale_detail_page.dart';
import 'sale_form_page.dart';

class SalesPage extends StatefulWidget {
  const SalesPage({super.key});

  @override
  State<SalesPage> createState() => _SalesPageState();
}

class _SalesPageState extends State<SalesPage> {
  static const int _pageSize = 10;

  final _searchController = TextEditingController();
  Timer? _searchTimer;

  List<Sale> _sales = const [];
  bool _loading = true;
  String? _error;
  String? _statusFilter;
  int _page = 1;
  int _total = 0;

  int get _totalPages =>
      _total == 0 ? 0 : ((_total + _pageSize - 1) ~/ _pageSize);

  bool get _hasFilters =>
      _searchController.text.trim().isNotEmpty || _statusFilter != null;

  @override
  void initState() {
    super.initState();
    _loadSales();
  }

  @override
  void dispose() {
    _searchTimer?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadSales({bool showSpinner = true}) async {
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
    if (_statusFilter != null) {
      query['status'] = _statusFilter!;
    }

    try {
      final result = await api.get('/sales', query: query);
      if (!mounted) {
        return;
      }
      final items = result.asList.map(Sale.fromJson).toList(growable: false);
      final total = (result.meta?['total'] as num?)?.toInt() ?? items.length;
      setState(() {
        _sales = items;
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
        _error = 'No se pudieron cargar las ventas.';
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
      _loadSales();
    });
  }

  void _clearSearch() {
    _searchController.clear();
    setState(() => _page = 1);
    _loadSales();
  }

  void _onStatusChanged(String? value) {
    setState(() {
      _statusFilter = (value == null || value.isEmpty) ? null : value;
      _page = 1;
    });
    _loadSales();
  }

  void _changePage(int page) {
    if (page < 1 || (_totalPages > 0 && page > _totalPages)) {
      return;
    }
    setState(() => _page = page);
    _loadSales();
  }

  Future<void> _openNewSale() async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => const SaleFormPage()));
    if (!mounted) {
      return;
    }
    await _loadSales(showSpinner: false);
  }

  Future<void> _openSale(Sale sale) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => SaleDetailPage(saleId: sale.id)),
    );
    if (!mounted) {
      return;
    }
    await _loadSales(showSpinner: false);
  }

  Future<void> _openCreditSettings() async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => const CreditSettingsPage()));
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>().user;
    final canCreate = auth?.hasPermission('sales.create') ?? false;
    final canSettings = auth?.hasPermission('credit_settings.update') ?? false;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Ventas'),
        actions: [
          if (canSettings)
            IconButton(
              tooltip: 'Configuración de crédito',
              onPressed: _openCreditSettings,
              icon: const Icon(Icons.tune_rounded),
            ),
          IconButton(
            tooltip: 'Actualizar',
            onPressed: () => _loadSales(showSpinner: false),
            icon: const Icon(Icons.refresh_rounded),
          ),
          const SizedBox(width: 8),
        ],
      ),
      floatingActionButton: canCreate
          ? FloatingActionButton.extended(
              onPressed: _openNewSale,
              icon: const Icon(Icons.add_rounded),
              label: const Text('Nueva venta'),
            )
          : null,
      body: RefreshIndicator(
        onRefresh: () => _loadSales(showSpinner: false),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 110),
          children: [
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1320),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _FiltersBar(
                      searchController: _searchController,
                      statusFilter: _statusFilter,
                      total: _total,
                      onSearchChanged: _onSearchChanged,
                      onClearSearch: _clearSearch,
                      onStatusChanged: _onStatusChanged,
                    ),
                    const SizedBox(height: 16),
                    if (_loading && _sales.isEmpty)
                      const _LoadingCard()
                    else if (_error != null)
                      _ErrorCard(message: _error!, onRetry: () => _loadSales())
                    else if (_sales.isEmpty)
                      _EmptyCard(
                        hasFilters: _hasFilters,
                        canCreate: canCreate,
                        onCreate: _openNewSale,
                      )
                    else ...[
                      if (_loading) const LinearProgressIndicator(),
                      if (_loading) const SizedBox(height: 8),
                      LayoutBuilder(
                        builder: (context, constraints) {
                          if (constraints.maxWidth >= 1000) {
                            return _SalesTable(
                              sales: _sales,
                              onOpen: _openSale,
                            );
                          }
                          return _SalesMobileList(
                            sales: _sales,
                            onOpen: _openSale,
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
    required this.statusFilter,
    required this.total,
    required this.onSearchChanged,
    required this.onClearSearch,
    required this.onStatusChanged,
  });

  final TextEditingController searchController;
  final String? statusFilter;
  final int total;
  final ValueChanged<String> onSearchChanged;
  final VoidCallback onClearSearch;
  final ValueChanged<String?> onStatusChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final search = TextField(
      controller: searchController,
      onChanged: onSearchChanged,
      decoration: InputDecoration(
        hintText: 'Buscar por número, cliente o vendedor...',
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
    final status = DropdownButtonFormField<String>(
      initialValue: statusFilter ?? '',
      isExpanded: true,
      decoration: const InputDecoration(
        labelText: 'Estado',
        prefixIcon: Icon(Icons.flag_outlined),
      ),
      items: [
        const DropdownMenuItem(value: '', child: Text('Todos')),
        for (final value in SaleStatuses.values)
          DropdownMenuItem(
            value: value,
            child: Text(SaleStatuses.label(value)),
          ),
      ],
      onChanged: onStatusChanged,
    );
    final counter = Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Text(
        total == 1 ? '1 venta' : '$total ventas',
        style: textTheme.labelSmall?.copyWith(
          color: scheme.onSurfaceVariant,
          fontWeight: FontWeight.w600,
        ),
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
                  status,
                  const SizedBox(height: 12),
                  Align(alignment: Alignment.centerLeft, child: counter),
                ],
              );
            }
            return Row(
              children: [
                Expanded(flex: 3, child: search),
                const SizedBox(width: 12),
                SizedBox(width: 210, child: status),
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

class _SalesTable extends StatelessWidget {
  const _SalesTable({required this.sales, required this.onOpen});

  final List<Sale> sales;
  final ValueChanged<Sale> onOpen;

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
          dataRowMinHeight: 60,
          dataRowMaxHeight: 78,
          columns: const [
            DataColumn(label: Text('No. venta')),
            DataColumn(label: Text('Cliente')),
            DataColumn(label: Text('Vendedor')),
            DataColumn(label: Text('Fecha')),
            DataColumn(label: Text('Pago')),
            DataColumn(label: Text('Estado')),
            DataColumn(label: Text('Total')),
            DataColumn(label: Text('')),
          ],
          rows: [
            for (final sale in sales)
              DataRow(
                onSelectChanged: (_) => onOpen(sale),
                cells: [
                  DataCell(
                    Text(
                      sale.saleNumber,
                      style: textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  DataCell(
                    SizedBox(
                      width: 220,
                      child: Text(
                        sale.clientName,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                  DataCell(
                    SizedBox(
                      width: 160,
                      child: Text(
                        sale.sellerName,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: textTheme.bodySmall,
                      ),
                    ),
                  ),
                  DataCell(Text(formatDate(sale.saleDate))),
                  DataCell(Text(PaymentTypes.label(sale.paymentType))),
                  DataCell(_SaleStatusBadge(status: sale.status)),
                  DataCell(
                    Text(
                      formatMoney(sale.total),
                      style: textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  DataCell(
                    IconButton(
                      tooltip: 'Ver detalle',
                      onPressed: () => onOpen(sale),
                      icon: const Icon(Icons.chevron_right_rounded),
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

class _SalesMobileList extends StatelessWidget {
  const _SalesMobileList({required this.sales, required this.onOpen});

  final List<Sale> sales;
  final ValueChanged<Sale> onOpen;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (var index = 0; index < sales.length; index++) ...[
          _SaleCard(sale: sales[index], onOpen: () => onOpen(sales[index])),
          if (index < sales.length - 1) const SizedBox(height: 10),
        ],
      ],
    );
  }
}

class _SaleCard extends StatelessWidget {
  const _SaleCard({required this.sale, required this.onOpen});

  final Sale sale;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          sale.saleNumber,
                          style: textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          sale.clientName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  _SaleStatusBadge(status: sale.status),
                ],
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 12,
                runSpacing: 5,
                children: [
                  _Meta(
                    icon: Icons.calendar_today_outlined,
                    text: formatDate(sale.saleDate),
                  ),
                  _Meta(
                    icon: Icons.payments_outlined,
                    text: PaymentTypes.label(sale.paymentType),
                  ),
                  _Meta(icon: Icons.badge_outlined, text: sale.sellerName),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    formatMoney(sale.total),
                    style: textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w900,
                      color: scheme.primary,
                    ),
                  ),
                  Text(
                    'Ver detalle',
                    style: textTheme.labelMedium?.copyWith(
                      color: scheme.primary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Meta extends StatelessWidget {
  const _Meta({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: scheme.onSurfaceVariant),
        const SizedBox(width: 4),
        Text(
          text,
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
        ),
      ],
    );
  }
}

class _SaleStatusBadge extends StatelessWidget {
  const _SaleStatusBadge({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (background, foreground) = switch (status) {
      SaleStatuses.quote => (
        scheme.secondaryContainer,
        scheme.onSecondaryContainer,
      ),
      SaleStatuses.sale => (
        scheme.tertiaryContainer,
        scheme.onTertiaryContainer,
      ),
      SaleStatuses.canceled => (scheme.errorContainer, scheme.onErrorContainer),
      _ => (scheme.surfaceContainerHigh, scheme.onSurfaceVariant),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        SaleStatuses.label(status),
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: foreground,
          fontWeight: FontWeight.w700,
          fontSize: 10,
        ),
      ),
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
    return Wrap(
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 8,
      children: [
        Text(
          'Mostrando $from–$to de $total',
          style: textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
        ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
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
            Text('Cargando ventas...'),
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
                    'No se pudieron cargar las ventas',
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
                    : Icons.receipt_long_outlined,
                size: 34,
                color: scheme.primary,
              ),
            ),
            const SizedBox(height: 18),
            Text(
              hasFilters ? 'No se encontraron ventas' : 'Aún no hay ventas',
              style: textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              hasFilters
                  ? 'Prueba con otro término o cambia el estado.'
                  : 'Registra una cotización o una venta con su plan de pagos.',
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
                label: const Text('Crear venta'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
