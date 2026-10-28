import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/utils/formatters.dart';
import '../../auth/providers/auth_provider.dart';
import '../models/user.dart';
import '../widgets/user_form_dialog.dart';
import '../widgets/user_roles_dialog.dart';

/// Administración de usuarios y cambio de roles. Solo accesible con
/// `users.read`; las acciones respetan los permisos del API.
class UsersPage extends StatefulWidget {
  const UsersPage({super.key});

  @override
  State<UsersPage> createState() => _UsersPageState();
}

class _UsersPageState extends State<UsersPage> {
  static const int _pageSize = 10;

  final _searchController = TextEditingController();
  Timer? _searchTimer;

  List<ManagedUser> _users = const [];
  List<AppRole> _roles = const [];
  bool _loading = true;
  bool _loadingRoles = true;
  String? _error;
  String? _rolesError;
  String? _roleFilter;
  bool? _activeFilter;
  int _page = 1;
  int _total = 0;

  int get _totalPages =>
      _total == 0 ? 0 : ((_total + _pageSize - 1) ~/ _pageSize);

  bool get _hasFilters =>
      _searchController.text.trim().isNotEmpty ||
      _roleFilter != null ||
      _activeFilter != null;

  @override
  void initState() {
    super.initState();
    _loadRoles();
    _loadUsers();
  }

  @override
  void dispose() {
    _searchTimer?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadRoles() async {
    final api = context.read<ApiClient>();
    try {
      final result = await api.get('/roles');
      if (!mounted) {
        return;
      }
      setState(() {
        _roles = result.asList.map(AppRole.fromJson).toList(growable: false);
        _loadingRoles = false;
        _rolesError = null;
      });
    } on ApiException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _loadingRoles = false;
        _rolesError = error.displayMessage;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _loadingRoles = false;
        _rolesError = 'No se pudieron cargar los roles.';
      });
    }
  }

  Future<void> _loadUsers({bool showSpinner = true}) async {
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
    if (_roleFilter != null) {
      query['role'] = _roleFilter!;
    }
    if (_activeFilter != null) {
      query['is_active'] = '$_activeFilter';
    }

    try {
      final result = await api.get('/users', query: query);
      if (!mounted) {
        return;
      }
      final items = result.asList
          .map(ManagedUser.fromJson)
          .toList(growable: false);
      final total = (result.meta?['total'] as num?)?.toInt() ?? items.length;
      setState(() {
        _users = items;
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
        _error = 'No se pudieron cargar los usuarios.';
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
      _loadUsers();
    });
  }

  void _clearSearch() {
    _searchController.clear();
    setState(() => _page = 1);
    _loadUsers();
  }

  void _onRoleChanged(String? value) {
    setState(() {
      _roleFilter = (value == null || value.isEmpty) ? null : value;
      _page = 1;
    });
    _loadUsers();
  }

  void _onActiveChanged(String? value) {
    setState(() {
      _activeFilter = switch (value) {
        'true' => true,
        'false' => false,
        _ => null,
      };
      _page = 1;
    });
    _loadUsers();
  }

  void _changePage(int page) {
    if (page < 1 || (_totalPages > 0 && page > _totalPages)) {
      return;
    }
    setState(() => _page = page);
    _loadUsers();
  }

  Future<void> _showUserForm({ManagedUser? user}) async {
    final authUser = context.read<AuthProvider>().user;
    final isCreating = user == null;
    final allowed = isCreating
        ? (authUser?.hasPermission('users.create') ?? false)
        : (authUser?.hasPermission('users.update') ?? false);
    if (!allowed) {
      return;
    }
    if (isCreating && _roles.isEmpty) {
      _showMessage(
        _rolesError ?? 'Los roles aún no están disponibles. Intenta de nuevo.',
      );
      return;
    }

    final result = await showDialog<UserFormData>(
      context: context,
      barrierDismissible: false,
      builder: (_) => UserFormDialog(user: user, roles: _roles),
    );
    if (result == null || !mounted) {
      return;
    }

    final api = context.read<ApiClient>();
    final messenger = ScaffoldMessenger.of(context);
    final existingUser = user;
    try {
      if (existingUser == null) {
        await api.post('/users', body: result.toCreateJson());
        if (!mounted) {
          return;
        }
        setState(() => _page = 1);
      } else {
        await api.patch(
          '/users/${existingUser.id}',
          body: result.toUpdateJson(),
        );
      }
      if (!mounted) {
        return;
      }
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            isCreating
                ? 'Usuario creado correctamente.'
                : 'Usuario actualizado correctamente.',
          ),
        ),
      );
      await _loadUsers(showSpinner: false);
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
        const SnackBar(content: Text('No se pudo guardar el usuario.')),
      );
    }
  }

  Future<void> _showRoles(ManagedUser user) async {
    final authUser = context.read<AuthProvider>().user;
    if (!(authUser?.hasPermission('users.assign_roles') ?? false)) {
      return;
    }
    if (_roles.isEmpty) {
      _showMessage(
        _rolesError ?? 'Los roles aún no están disponibles. Intenta de nuevo.',
      );
      return;
    }

    final roleIds = await showDialog<List<String>>(
      context: context,
      barrierDismissible: false,
      builder: (_) => UserRolesDialog(user: user, roles: _roles),
    );
    if (roleIds == null || !mounted) {
      return;
    }

    final api = context.read<ApiClient>();
    final messenger = ScaffoldMessenger.of(context);
    try {
      await api.put('/users/${user.id}/roles', body: {'role_ids': roleIds});
      if (!mounted) {
        return;
      }
      messenger.showSnackBar(
        const SnackBar(content: Text('Roles actualizados correctamente.')),
      );
      await _loadUsers(showSpinner: false);
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
        const SnackBar(content: Text('No se pudieron actualizar los roles.')),
      );
    }
  }

  Future<void> _deleteUser(ManagedUser user) async {
    final authUser = context.read<AuthProvider>().user;
    if (!(authUser?.hasPermission('users.delete') ?? false) ||
        authUser?.id == user.id) {
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        final scheme = Theme.of(dialogContext).colorScheme;
        return AlertDialog(
          title: const Text('Eliminar usuario'),
          content: Text(
            '¿Eliminar a ${user.displayName} (${user.email})? '
            'El usuario dejará de poder iniciar sesión.',
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
      await api.delete('/users/${user.id}');
      if (!mounted) {
        return;
      }
      if (_users.length == 1 && _page > 1) {
        setState(() => _page -= 1);
      }
      messenger.showSnackBar(
        const SnackBar(content: Text('Usuario eliminado correctamente.')),
      );
      await _loadUsers(showSpinner: false);
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
        const SnackBar(content: Text('No se pudo eliminar el usuario.')),
      );
    }
  }

  void _showMessage(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final authUser = context.watch<AuthProvider>().user;
    final canCreate = authUser?.hasPermission('users.create') ?? false;
    final canUpdate = authUser?.hasPermission('users.update') ?? false;
    final canDelete = authUser?.hasPermission('users.delete') ?? false;
    final canAssignRoles =
        authUser?.hasPermission('users.assign_roles') ?? false;
    final showActions = canUpdate || canDelete || canAssignRoles;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Usuarios'),
        actions: [
          IconButton(
            tooltip: 'Actualizar',
            onPressed: () => _loadUsers(showSpinner: false),
            icon: const Icon(Icons.refresh_rounded),
          ),
          const SizedBox(width: 8),
        ],
      ),
      floatingActionButton: canCreate
          ? FloatingActionButton.extended(
              onPressed: () => _showUserForm(),
              icon: const Icon(Icons.person_add_alt_1_rounded),
              label: const Text('Nuevo usuario'),
            )
          : null,
      body: RefreshIndicator(
        onRefresh: () async {
          await _loadRoles();
          await _loadUsers(showSpinner: false);
        },
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
                      roles: _roles,
                      rolesLoading: _loadingRoles,
                      roleFilter: _roleFilter,
                      activeFilter: _activeFilter,
                      total: _total,
                      onSearchChanged: _onSearchChanged,
                      onClearSearch: _clearSearch,
                      onRoleChanged: _onRoleChanged,
                      onActiveChanged: _onActiveChanged,
                    ),
                    if (_rolesError != null) ...[
                      const SizedBox(height: 10),
                      _RolesWarning(message: _rolesError!, onRetry: _loadRoles),
                    ],
                    const SizedBox(height: 16),
                    if (_loading && _users.isEmpty)
                      const _LoadingCard()
                    else if (_error != null)
                      _ErrorCard(message: _error!, onRetry: () => _loadUsers())
                    else if (_users.isEmpty)
                      _EmptyCard(
                        hasFilters: _hasFilters,
                        canCreate: canCreate,
                        onCreate: () => _showUserForm(),
                      )
                    else ...[
                      if (_loading) const LinearProgressIndicator(),
                      if (_loading) const SizedBox(height: 8),
                      LayoutBuilder(
                        builder: (context, constraints) {
                          final table = constraints.maxWidth >= 900;
                          if (table) {
                            return _UsersTable(
                              users: _users,
                              currentUserId: authUser?.id,
                              canUpdate: canUpdate,
                              canDelete: canDelete,
                              canAssignRoles: canAssignRoles,
                              showActions: showActions,
                              onEdit: (user) => _showUserForm(user: user),
                              onRoles: _showRoles,
                              onDelete: _deleteUser,
                            );
                          }
                          return _UsersMobileList(
                            users: _users,
                            currentUserId: authUser?.id,
                            canUpdate: canUpdate,
                            canDelete: canDelete,
                            canAssignRoles: canAssignRoles,
                            onEdit: (user) => _showUserForm(user: user),
                            onRoles: _showRoles,
                            onDelete: _deleteUser,
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
    required this.roles,
    required this.rolesLoading,
    required this.roleFilter,
    required this.activeFilter,
    required this.total,
    required this.onSearchChanged,
    required this.onClearSearch,
    required this.onRoleChanged,
    required this.onActiveChanged,
  });

  final TextEditingController searchController;
  final List<AppRole> roles;
  final bool rolesLoading;
  final String? roleFilter;
  final bool? activeFilter;
  final int total;
  final ValueChanged<String> onSearchChanged;
  final VoidCallback onClearSearch;
  final ValueChanged<String?> onRoleChanged;
  final ValueChanged<String?> onActiveChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    final search = TextField(
      controller: searchController,
      onChanged: onSearchChanged,
      decoration: InputDecoration(
        hintText: 'Buscar por nombre o correo...',
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

    final role = DropdownButtonFormField<String>(
      initialValue: roleFilter ?? '',
      isExpanded: true,
      decoration: const InputDecoration(
        labelText: 'Rol',
        prefixIcon: Icon(Icons.badge_outlined),
      ),
      items: [
        const DropdownMenuItem(value: '', child: Text('Todos')),
        for (final item in roles)
          DropdownMenuItem(value: item.name, child: Text(roleLabel(item.name))),
      ],
      onChanged: rolesLoading ? null : onRoleChanged,
    );

    final active = DropdownButtonFormField<String>(
      initialValue: activeFilter == null ? '' : '$activeFilter',
      isExpanded: true,
      decoration: const InputDecoration(
        labelText: 'Estado',
        prefixIcon: Icon(Icons.toggle_on_outlined),
      ),
      items: const [
        DropdownMenuItem(value: '', child: Text('Todos')),
        DropdownMenuItem(value: 'true', child: Text('Activos')),
        DropdownMenuItem(value: 'false', child: Text('Inactivos')),
      ],
      onChanged: onActiveChanged,
    );

    final counter = Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Text(
        total == 1 ? '1 usuario' : '$total usuarios',
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
            if (constraints.maxWidth < 820) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  search,
                  const SizedBox(height: 12),
                  role,
                  const SizedBox(height: 12),
                  active,
                  const SizedBox(height: 12),
                  Align(alignment: Alignment.centerLeft, child: counter),
                ],
              );
            }
            return Row(
              children: [
                Expanded(flex: 3, child: search),
                const SizedBox(width: 12),
                SizedBox(width: 200, child: role),
                const SizedBox(width: 12),
                SizedBox(width: 170, child: active),
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

class _UsersTable extends StatelessWidget {
  const _UsersTable({
    required this.users,
    required this.currentUserId,
    required this.canUpdate,
    required this.canDelete,
    required this.canAssignRoles,
    required this.showActions,
    required this.onEdit,
    required this.onRoles,
    required this.onDelete,
  });

  final List<ManagedUser> users;
  final String? currentUserId;
  final bool canUpdate;
  final bool canDelete;
  final bool canAssignRoles;
  final bool showActions;
  final ValueChanged<ManagedUser> onEdit;
  final ValueChanged<ManagedUser> onRoles;
  final ValueChanged<ManagedUser> onDelete;

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
          dataRowMinHeight: 64,
          dataRowMaxHeight: 84,
          columns: const [
            DataColumn(label: Text('Usuario')),
            DataColumn(label: Text('Roles')),
            DataColumn(label: Text('Estado')),
            DataColumn(label: Text('Último acceso')),
            DataColumn(label: Text('Acciones')),
          ],
          rows: [
            for (final user in users)
              DataRow(
                cells: [
                  DataCell(
                    SizedBox(
                      width: 270,
                      child: Row(
                        children: [
                          _UserAvatar(user: user, size: 38),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  user.displayName,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: textTheme.bodyMedium?.copyWith(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                Text(
                                  user.email,
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
                  DataCell(_RoleChips(roles: user.roles)),
                  DataCell(_StatusChip(active: user.isActive)),
                  DataCell(
                    Text(
                      formatDateTime(user.lastLoginAt),
                      style: textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  DataCell(
                    showActions
                        ? Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (canAssignRoles)
                                IconButton(
                                  tooltip: 'Cambiar roles',
                                  onPressed: () => onRoles(user),
                                  icon: const Icon(
                                    Icons.admin_panel_settings_outlined,
                                    size: 19,
                                  ),
                                ),
                              if (canUpdate)
                                IconButton(
                                  tooltip: 'Editar',
                                  onPressed: () => onEdit(user),
                                  icon: const Icon(
                                    Icons.edit_outlined,
                                    size: 19,
                                  ),
                                ),
                              if (canDelete && user.id != currentUserId)
                                IconButton(
                                  tooltip: 'Eliminar',
                                  onPressed: () => onDelete(user),
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

class _UsersMobileList extends StatelessWidget {
  const _UsersMobileList({
    required this.users,
    required this.currentUserId,
    required this.canUpdate,
    required this.canDelete,
    required this.canAssignRoles,
    required this.onEdit,
    required this.onRoles,
    required this.onDelete,
  });

  final List<ManagedUser> users;
  final String? currentUserId;
  final bool canUpdate;
  final bool canDelete;
  final bool canAssignRoles;
  final ValueChanged<ManagedUser> onEdit;
  final ValueChanged<ManagedUser> onRoles;
  final ValueChanged<ManagedUser> onDelete;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (var index = 0; index < users.length; index++) ...[
          _UserCard(
            user: users[index],
            currentUserId: currentUserId,
            canUpdate: canUpdate,
            canDelete: canDelete,
            canAssignRoles: canAssignRoles,
            onEdit: () => onEdit(users[index]),
            onRoles: () => onRoles(users[index]),
            onDelete: () => onDelete(users[index]),
          ),
          if (index < users.length - 1) const SizedBox(height: 10),
        ],
      ],
    );
  }
}

class _UserCard extends StatelessWidget {
  const _UserCard({
    required this.user,
    required this.currentUserId,
    required this.canUpdate,
    required this.canDelete,
    required this.canAssignRoles,
    required this.onEdit,
    required this.onRoles,
    required this.onDelete,
  });

  final ManagedUser user;
  final String? currentUserId;
  final bool canUpdate;
  final bool canDelete;
  final bool canAssignRoles;
  final VoidCallback onEdit;
  final VoidCallback onRoles;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final showMenu = canUpdate || canDelete || canAssignRoles;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _UserAvatar(user: user, size: 44),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        user.displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        user.email,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                if (showMenu)
                  PopupMenuButton<String>(
                    tooltip: 'Acciones',
                    onSelected: (value) {
                      if (value == 'roles') {
                        onRoles();
                      } else if (value == 'edit') {
                        onEdit();
                      } else if (value == 'delete') {
                        onDelete();
                      }
                    },
                    itemBuilder: (context) => [
                      if (canAssignRoles)
                        const PopupMenuItem(
                          value: 'roles',
                          child: ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: Icon(Icons.admin_panel_settings_outlined),
                            title: Text('Cambiar roles'),
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
                      if (canDelete && user.id != currentUserId)
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
            Wrap(
              spacing: 8,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                _StatusChip(active: user.isActive),
                _RoleChips(roles: user.roles),
              ],
            ),
            const SizedBox(height: 12),
            const Divider(height: 1),
            const SizedBox(height: 10),
            Row(
              children: [
                Icon(
                  Icons.access_time_rounded,
                  size: 15,
                  color: scheme.onSurfaceVariant,
                ),
                const SizedBox(width: 5),
                Expanded(
                  child: Text(
                    'Último acceso: ${formatDateTime(user.lastLoginAt)}',
                    style: textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
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

class _UserAvatar extends StatelessWidget {
  const _UserAvatar({required this.user, required this.size});

  final ManagedUser user;
  final double size;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: user.isActive
            ? scheme.primaryContainer
            : scheme.surfaceContainerHigh,
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: Text(
        user.initials,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
          color: user.isActive ? scheme.primary : scheme.onSurfaceVariant,
          fontWeight: FontWeight.w800,
          fontSize: size * 0.32,
        ),
      ),
    );
  }
}

class _RoleChips extends StatelessWidget {
  const _RoleChips({required this.roles});

  final List<String> roles;

  @override
  Widget build(BuildContext context) {
    if (roles.isEmpty) {
      return Text(
        '—',
        style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
      );
    }
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Wrap(
      spacing: 4,
      runSpacing: 4,
      children: [
        for (final role in roles)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
            decoration: BoxDecoration(
              color: scheme.secondaryContainer,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              roleLabel(role),
              style: textTheme.labelSmall?.copyWith(
                color: scheme.onSecondaryContainer,
                fontWeight: FontWeight.w700,
                fontSize: 10,
              ),
            ),
          ),
      ],
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.active});

  final bool active;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: active ? scheme.tertiaryContainer : scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        active ? 'Activo' : 'Inactivo',
        style: textTheme.labelSmall?.copyWith(
          color: active ? scheme.onTertiaryContainer : scheme.onSurfaceVariant,
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
      runSpacing: 4,
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
            Text('Cargando usuarios...'),
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
                    'No se pudieron cargar los usuarios',
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

class _RolesWarning extends StatelessWidget {
  const _RolesWarning({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      color: scheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: scheme.onErrorContainer),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Roles no disponibles: $message',
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: scheme.onErrorContainer),
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
                hasFilters ? Icons.search_off_rounded : Icons.people_outline,
                size: 34,
                color: scheme.primary,
              ),
            ),
            const SizedBox(height: 18),
            Text(
              hasFilters ? 'No se encontraron usuarios' : 'Aún no hay usuarios',
              style: textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              hasFilters
                  ? 'Prueba con otro término o cambia los filtros.'
                  : 'Crea el primer usuario y asígnale un rol.',
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
                label: const Text('Crear usuario'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
