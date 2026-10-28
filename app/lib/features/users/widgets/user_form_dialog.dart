import 'package:flutter/material.dart';

import '../../../core/utils/formatters.dart';
import '../models/user.dart';

/// Formulario de alta o edición de un usuario.
class UserFormDialog extends StatefulWidget {
  const UserFormDialog({super.key, this.user, required this.roles});

  final ManagedUser? user;
  final List<AppRole> roles;

  bool get isCreating => user == null;

  @override
  State<UserFormDialog> createState() => _UserFormDialogState();
}

class _UserFormDialogState extends State<UserFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _emailController;
  late final TextEditingController _passwordController;
  late bool _isActive;
  late final Set<String> _selectedRoleIds;
  String? _rolesError;

  @override
  void initState() {
    super.initState();
    final user = widget.user;
    _nameController = TextEditingController(text: user?.fullName ?? '');
    _emailController = TextEditingController(text: user?.email ?? '');
    _passwordController = TextEditingController();
    _isActive = user?.isActive ?? true;
    _selectedRoleIds = {
      for (final role in widget.roles)
        if (user?.hasRole(role.name) ?? false) role.id,
    };
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _submit() {
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }
    if (widget.isCreating && _selectedRoleIds.isEmpty) {
      setState(() => _rolesError = 'Selecciona al menos un rol.');
      return;
    }

    final password = _passwordController.text.trim();
    Navigator.of(context).pop(
      UserFormData(
        email: _emailController.text.trim(),
        fullName: _nameController.text.trim(),
        isActive: _isActive,
        password: password.isEmpty ? null : password,
        roleIds: _selectedRoleIds.toList(growable: false),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final media = MediaQuery.sizeOf(context);
    final width = media.width < 680 ? media.width - 64 : 520.0;
    final isCreating = widget.isCreating;

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
                        isCreating ? 'Nuevo usuario' : 'Editar usuario',
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
                          textCapitalization: TextCapitalization.words,
                          decoration: const InputDecoration(
                            labelText: 'Nombre completo',
                            prefixIcon: Icon(Icons.person_outline_rounded),
                          ),
                          validator: _validateName,
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _emailController,
                          keyboardType: TextInputType.emailAddress,
                          textInputAction: TextInputAction.next,
                          decoration: const InputDecoration(
                            labelText: 'Correo electrónico',
                            prefixIcon: Icon(Icons.alternate_email_rounded),
                          ),
                          validator: _validateEmail,
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _passwordController,
                          obscureText: true,
                          textInputAction: TextInputAction.done,
                          onFieldSubmitted: (_) => _submit(),
                          decoration: InputDecoration(
                            labelText: isCreating
                                ? 'Contraseña'
                                : 'Nueva contraseña (opcional)',
                            helperText: isCreating
                                ? 'Mínimo 6 caracteres'
                                : 'Déjala vacía para conservar la actual',
                            prefixIcon: const Icon(Icons.lock_outline_rounded),
                          ),
                          validator: (value) =>
                              _validatePassword(value, required: isCreating),
                        ),
                        const SizedBox(height: 8),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          value: _isActive,
                          onChanged: (value) =>
                              setState(() => _isActive = value),
                          title: const Text('Usuario activo'),
                          subtitle: const Text(
                            'Si se desactiva, no podrá iniciar sesión.',
                          ),
                          secondary: Icon(
                            _isActive
                                ? Icons.check_circle_outline_rounded
                                : Icons.block_rounded,
                            color: _isActive ? scheme.tertiary : scheme.error,
                          ),
                        ),
                        if (isCreating) ...[
                          const SizedBox(height: 12),
                          Text(
                            'Roles',
                            style: textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Define qué módulos podrá usar este usuario.',
                            style: textTheme.bodySmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 8),
                          if (widget.roles.isEmpty)
                            Text(
                              'No hay roles disponibles. Crea un rol primero.',
                              style: textTheme.bodySmall?.copyWith(
                                color: scheme.error,
                              ),
                            )
                          else
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
                                    _rolesError = null;
                                  });
                                },
                                title: Text(roleLabel(role.name)),
                                subtitle: Text(
                                  role.description?.trim().isNotEmpty ?? false
                                      ? role.description!
                                      : '${role.permissionCount} permisos',
                                ),
                                controlAffinity:
                                    ListTileControlAffinity.leading,
                              ),
                          if (_rolesError != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text(
                                _rolesError!,
                                style: textTheme.bodySmall?.copyWith(
                                  color: scheme.error,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                        ] else ...[
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Icon(
                                Icons.admin_panel_settings_outlined,
                                size: 18,
                                color: scheme.onSurfaceVariant,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Los roles se cambian desde la acción Roles.',
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
                      child: Text(isCreating ? 'Crear usuario' : 'Guardar'),
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

  static String? _validateName(String? value) {
    final name = value?.trim() ?? '';
    if (name.length < 2) {
      return 'El nombre debe tener al menos 2 caracteres.';
    }
    if (name.length > 120) {
      return 'El nombre no puede superar 120 caracteres.';
    }
    return null;
  }

  static String? _validateEmail(String? value) {
    final email = value?.trim() ?? '';
    if (email.isEmpty) {
      return 'Ingresa el correo electrónico.';
    }
    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)) {
      return 'Ingresa un correo electrónico válido.';
    }
    if (email.length > 254) {
      return 'El correo no puede superar 254 caracteres.';
    }
    return null;
  }

  static String? _validatePassword(String? value, {required bool required}) {
    final password = value ?? '';
    if (password.isEmpty && !required) {
      return null;
    }
    if (password.length < 6) {
      return 'La contraseña debe tener al menos 6 caracteres.';
    }
    if (password.length > 72) {
      return 'La contraseña no puede superar 72 caracteres.';
    }
    return null;
  }
}
