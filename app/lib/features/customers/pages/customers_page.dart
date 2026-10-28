import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/api_exception.dart';
import '../../auth/providers/auth_provider.dart';
import '../models/customer.dart';
import '../widgets/customer_form_dialog.dart';

/// CRUD de clientes, con búsqueda, filtro por estado y paginación.
class CustomersPage extends StatefulWidget {
  const CustomersPage({super.key});

  @override
  State<CustomersPage> createState() => _CustomersPageState();
}

class _CustomersPageState extends State<CustomersPage> {
  static const int _pageSize = 10;

  final _searchController = TextEditingController();
  Timer? _searchTimer;

  List<Customer> _customers = const [];
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
    _loadCustomers();
  }

  @override
  void dispose() {
    _searchTimer?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadCustomers({bool showSpinner = true}) async {
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
      final result = await api.get('/customers', query: query);
      if (!mounted) {
        return;
      }
      final items = result.asList
          .map(Customer.fromJson)
          .toList(growable: false);
      final total = (result.meta?['total'] as num?)?.toInt() ?? items.length;
      setState(() {
        _customers = items;
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
        _error = 'No se pudieron cargar los clientes.';
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
      _loadCustomers();
    });
  }

  void _clearSearch() {
    _searchController.clear();
    setState(() => _page = 1);
    _loadCustomers();
  }

  void _onStatusChanged(String? value) {
    setState(() {
      _statusFilter = (value == null || value.isEmpty) ? null : value;
      _page = 1;
    });
    _loadCustomers();
  }

  void _changePage(int page) {
    if (page < 1 || (_totalPages > 0 && page > _totalPages)) {
      return;
    }
    setState(() => _page = page);
    _loadCustomers();
  }

  Future<void> _showForm({Customer? customer}) async {
    final authUser = context.read<AuthProvider>().user;
    final isCreating = customer == null;
    final allowed = isCreating
        ? (authUser?.hasPermission('customers.create') ?? false)
        : (authUser?.hasPermission('customers.update') ?? false);
    if (!allowed) {
      return;
    }

    final data = await showDialog<CustomerFormData>(
      context: context,
      barrierDismissible: false,
      builder: (_) => CustomerFormDialog(customer: customer),
    );
    if (data == null || !mounted) {
      return;
    }

    final api = context.read<ApiClient>();
    final messenger = ScaffoldMessenger.of(context);
    final existingCustomer = customer;
    try {
      if (existingCustomer == null) {
        await api.post('/customers', body: data.toJson());
        if (!mounted) {
          return;
        }
        setState(() => _page = 1);
      } else {
        await api.put('/customers/${existingCustomer.id}', body: data.toJson());
      }
      if (!mounted) {
        return;
      }
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            isCreating
                ? 'Cliente creado correctamente.'
                : 'Cliente actualizado correctamente.',
          ),
        ),
      );
      await _loadCustomers(showSpinner: false);
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
        const SnackBar(content: Text('No se pudo guardar el cliente.')),
      );
    }
  }

  Future<void> _delete(Customer customer) async {
    final authUser = context.read<AuthProvider>().user;
    if (!(authUser?.hasPermission('customers.delete') ?? false)) {
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        final scheme = Theme.of(dialogContext).colorScheme;
        return AlertDialog(
          title: const Text('Eliminar cliente'),
          content: Text(
            '¿Eliminar a ${customer.name}? Dejará de aparecer en el listado.',
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
      await api.delete('/customers/${customer.id}');
      if (!mounted) {
        return;
      }
      if (_customers.length == 1 && _page > 1) {
        setState(() => _page -= 1);
      }
      messenger.showSnackBar(
        const SnackBar(content: Text('Cliente eliminado correctamente.')),
      );
      await _loadCustomers(showSpinner: false);
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
        const SnackBar(content: Text('No se pudo eliminar el cliente.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final authUser = context.watch<AuthProvider>().user;
    final canCreate = authUser?.hasPermission('customers.create') ?? false;
    final canUpdate = authUser?.hasPermission('customers.update') ?? false;
    final canDelete = authUser?.hasPermission('customers.delete') ?? false;
    final showActions = canUpdate || canDelete;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Clientes'),
        actions: [
          IconButton(
            tooltip: 'Actualizar',
            onPressed: () => _loadCustomers(showSpinner: false),
            icon: const Icon(Icons.refresh_rounded),
          ),
          const SizedBox(width: 8),
        ],
      ),
      floatingActionButton: canCreate
          ? FloatingActionButton.extended(
              onPressed: () => _showForm(),
              icon: const Icon(Icons.person_add_alt_1_rounded),
              label: const Text('Nuevo cliente'),
            )
          : null,
      body: RefreshIndicator(
        onRefresh: () => _loadCustomers(showSpinner: false),
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
                      statusFilter: _statusFilter,
                      total: _total,
                      onSearchChanged: _onSearchChanged,
                      onClearSearch: _clearSearch,
                      onStatusChanged: _onStatusChanged,
                    ),
                    const SizedBox(height: 16),
                    if (_loading && _customers.isEmpty)
                      const _LoadingCard()
                    else if (_error != null)
                      _ErrorCard(
                        message: _error!,
                        onRetry: () => _loadCustomers(),
                      )
                    else if (_customers.isEmpty)
                      _EmptyCard(
                        hasFilters: _hasFilters,
                        canCreate: canCreate,
                        onCreate: () => _showForm(),
                      )
                    else ...[
                      if (_loading) const LinearProgressIndicator(),
                      if (_loading) const SizedBox(height: 8),
                      LayoutBuilder(
                        builder: (context, constraints) {
                          if (constraints.maxWidth >= 900) {
                            return _CustomersTable(
                              customers: _customers,
                              canUpdate: canUpdate,
                              canDelete: canDelete,
                              showActions: showActions,
                              onEdit: (customer) =>
                                  _showForm(customer: customer),
                              onDelete: _delete,
                            );
                          }
                          return _CustomersMobileList(
                            customers: _customers,
                            canUpdate: canUpdate,
                            canDelete: canDelete,
                            onEdit: (customer) => _showForm(customer: customer),
                            onDelete: _delete,
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
        hintText: 'Buscar por nombre, teléfono, correo o ciudad...',
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
        for (final value in CustomerStatuses.values)
          DropdownMenuItem(
            value: value,
            child: Text(CustomerStatuses.label(value)),
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
        total == 1 ? '1 cliente' : '$total clientes',
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

class _CustomersTable extends StatelessWidget {
  const _CustomersTable({
    required this.customers,
    required this.canUpdate,
    required this.canDelete,
    required this.showActions,
    required this.onEdit,
    required this.onDelete,
  });

  final List<Customer> customers;
  final bool canUpdate;
  final bool canDelete;
  final bool showActions;
  final ValueChanged<Customer> onEdit;
  final ValueChanged<Customer> onDelete;

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
          dataRowMinHeight: 66,
          dataRowMaxHeight: 90,
          columns: const [
            DataColumn(label: Text('Cliente')),
            DataColumn(label: Text('Contacto')),
            DataColumn(label: Text('Ubicación')),
            DataColumn(label: Text('Dirección')),
            DataColumn(label: Text('Estado')),
            DataColumn(label: Text('Acciones')),
          ],
          rows: [
            for (final customer in customers)
              DataRow(
                cells: [
                  DataCell(
                    SizedBox(
                      width: 240,
                      child: Row(
                        children: [
                          _CustomerAvatar(customer: customer),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              customer.name,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: textTheme.bodyMedium?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  DataCell(
                    SizedBox(
                      width: 190,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            customer.phone ?? '—',
                            style: textTheme.bodySmall,
                          ),
                          if (customer.email != null)
                            Text(
                              customer.email!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: textTheme.bodySmall?.copyWith(
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  DataCell(
                    Text(
                      customer.location,
                      style: textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  DataCell(
                    SizedBox(
                      width: 190,
                      child: Text(
                        customer.address ?? '—',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: textTheme.bodySmall,
                      ),
                    ),
                  ),
                  DataCell(_StatusBadge(status: customer.status)),
                  DataCell(
                    showActions
                        ? Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (canUpdate)
                                IconButton(
                                  tooltip: 'Editar',
                                  onPressed: () => onEdit(customer),
                                  icon: const Icon(
                                    Icons.edit_outlined,
                                    size: 19,
                                  ),
                                ),
                              if (canDelete)
                                IconButton(
                                  tooltip: 'Eliminar',
                                  onPressed: () => onDelete(customer),
                                  icon: Icon(
                                    Icons.delete_outline_rounded,
                                    size: 19,
                                    color: scheme.error,
                                  ),
                                ),
                            ],
                          )
                        : Text(
                            '—',
                            style: TextStyle(color: scheme.onSurfaceVariant),
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

class _CustomersMobileList extends StatelessWidget {
  const _CustomersMobileList({
    required this.customers,
    required this.canUpdate,
    required this.canDelete,
    required this.onEdit,
    required this.onDelete,
  });

  final List<Customer> customers;
  final bool canUpdate;
  final bool canDelete;
  final ValueChanged<Customer> onEdit;
  final ValueChanged<Customer> onDelete;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (var index = 0; index < customers.length; index++) ...[
          _CustomerCard(
            customer: customers[index],
            canUpdate: canUpdate,
            canDelete: canDelete,
            onEdit: () => onEdit(customers[index]),
            onDelete: () => onDelete(customers[index]),
          ),
          if (index < customers.length - 1) const SizedBox(height: 10),
        ],
      ],
    );
  }
}

class _CustomerCard extends StatelessWidget {
  const _CustomerCard({
    required this.customer,
    required this.canUpdate,
    required this.canDelete,
    required this.onEdit,
    required this.onDelete,
  });

  final Customer customer;
  final bool canUpdate;
  final bool canDelete;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final showMenu = canUpdate || canDelete;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _CustomerAvatar(customer: customer, size: 42),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        customer.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 3),
                      _StatusBadge(status: customer.status),
                    ],
                  ),
                ),
                if (showMenu)
                  PopupMenuButton<String>(
                    tooltip: 'Acciones',
                    onSelected: (value) {
                      if (value == 'edit') {
                        onEdit();
                      } else if (value == 'delete') {
                        onDelete();
                      }
                    },
                    itemBuilder: (context) => [
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
            const SizedBox(height: 12),
            const Divider(height: 1),
            const SizedBox(height: 10),
            _InfoRow(
              icon: Icons.phone_outlined,
              text: customer.phone ?? 'Sin teléfono',
            ),
            if (customer.email != null)
              _InfoRow(
                icon: Icons.alternate_email_rounded,
                text: customer.email!,
              ),
            _InfoRow(
              icon: Icons.location_city_outlined,
              text: customer.location,
            ),
            if (customer.address != null)
              _InfoRow(
                icon: Icons.location_on_outlined,
                text: customer.address!,
              ),
          ],
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 15, color: scheme.onSurfaceVariant),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              text,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }
}

class _CustomerAvatar extends StatelessWidget {
  const _CustomerAvatar({required this.customer, this.size = 38});

  final Customer customer;
  final double size;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final initial = customer.name.trim().isEmpty
        ? '?'
        : customer.name.trim()[0].toUpperCase();
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: scheme.primaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      alignment: Alignment.center,
      child: Text(
        initial,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
          color: scheme.primary,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (background, foreground, icon) = switch (status) {
      CustomerStatuses.prospect => (
        scheme.secondaryContainer,
        scheme.onSecondaryContainer,
        Icons.radar_rounded,
      ),
      CustomerStatuses.customer => (
        scheme.primaryContainer,
        scheme.onPrimaryContainer,
        Icons.check_circle_outline_rounded,
      ),
      CustomerStatuses.inPayment => (
        scheme.tertiaryContainer,
        scheme.onTertiaryContainer,
        Icons.schedule_rounded,
      ),
      CustomerStatuses.settled => (
        scheme.surfaceContainerHigh,
        scheme.onSurfaceVariant,
        Icons.task_alt_rounded,
      ),
      _ => (
        scheme.surfaceContainerHigh,
        scheme.onSurfaceVariant,
        Icons.help_outline_rounded,
      ),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: foreground),
          const SizedBox(width: 4),
          Text(
            CustomerStatuses.label(status),
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: foreground,
              fontWeight: FontWeight.w700,
              fontSize: 10,
            ),
          ),
        ],
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
            Text('Cargando clientes...'),
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
                    'No se pudieron cargar los clientes',
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
                hasFilters ? Icons.search_off_rounded : Icons.groups_outlined,
                size: 34,
                color: scheme.primary,
              ),
            ),
            const SizedBox(height: 18),
            Text(
              hasFilters ? 'No se encontraron clientes' : 'Aún no hay clientes',
              style: textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              hasFilters
                  ? 'Prueba con otro término o cambia el estado.'
                  : 'Crea el primer cliente para comenzar.',
              textAlign: TextAlign.center,
              style: textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            if (!hasFilters && canCreate) ...[
              const SizedBox(height: 18),
              FilledButton.icon(
                onPressed: onCreate,
                icon: const Icon(Icons.person_add_alt_1_rounded),
                label: const Text('Crear cliente'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
