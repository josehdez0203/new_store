import 'package:flutter/material.dart';

import '../../../core/utils/formatters.dart';
import '../models/user.dart';

/// Diálogo para cambiar los roles de un usuario.
class UserRolesDialog extends StatefulWidget {
  const UserRolesDialog({super.key, required this.user, required this.roles});

  final ManagedUser user;
  final List<AppRole> roles;

  @override
  State<UserRolesDialog> createState() => _UserRolesDialogState();
}

class _UserRolesDialogState extends State<UserRolesDialog> {
  late final Set<String> _selectedRoleIds;
  String? _error;

  @override
  void initState() {
    super.initState();
    _selectedRoleIds = {
      for (final role in widget.roles)
        if (widget.user.hasRole(role.name)) role.id,
    };
  }

  void _submit() {
    if (_selectedRoleIds.isEmpty) {
      setState(() => _error = 'Selecciona al menos un rol.');
      return;
    }
    Navigator.of(context).pop(_selectedRoleIds.toList(growable: false));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final media = MediaQuery.sizeOf(context);
    final width = media.width < 680 ? media.width - 64 : 500.0;

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
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Cambiar roles', style: textTheme.headlineSmall),
                          const SizedBox(height: 3),
                          Text(
                            widget.user.displayName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: textTheme.bodySmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ],
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
                  padding: const EdgeInsets.fromLTRB(24, 14, 24, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Un usuario puede tener más de un rol. '
                        'Los permisos se suman.',
                        style: textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 8),
                      for (final role in widget.roles)
                        CheckboxListTile(
                          contentPadding: EdgeInsets.zero,
                          value: _selectedRoleIds.contains(role.id),
                          onChanged: (checked) {
                            setState(() {
                              if (checked ?? false) {
                                _selectedRoleIds.add(role.id);
                              } else {
                                _selectedRoleIds.remove(role.id);
                              }
                              _error = null;
                            });
                          },
                          title: Text(roleLabel(role.name)),
                          subtitle: Text(
                            role.description?.trim().isNotEmpty ?? false
                                ? role.description!
                                : '${role.permissionCount} permisos · '
                                      '${role.userCount} usuarios',
                          ),
                          controlAffinity: ListTileControlAffinity.leading,
                        ),
                      if (_error != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          _error!,
                          style: textTheme.bodySmall?.copyWith(
                            color: scheme.error,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ],
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
                      child: const Text('Guardar roles'),
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
}
