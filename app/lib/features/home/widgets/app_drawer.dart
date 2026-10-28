import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/config/app_config.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/app_logo.dart';
import '../../auth/models/auth_user.dart';
import '../../auth/providers/auth_provider.dart';
import '../../profile/pages/profile_page.dart';
import '../../settings/pages/settings_page.dart';
import '../../settings/providers/theme_provider.dart';
import '../navigation/app_destinations.dart';

/// Menú lateral del home. Las opciones se filtran por los permisos del usuario.
class AppDrawer extends StatelessWidget {
  const AppDrawer({super.key, this.currentDestinationId = 'home'});

  final String currentDestinationId;

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final user = auth.user;
    final theme = context.watch<ThemeProvider>();
    final scheme = Theme.of(context).colorScheme;

    if (user == null) {
      return const Drawer(child: SizedBox.shrink());
    }

    final grouped = destinationsBySection(user.permissions);

    return Drawer(
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 14, 18, 4),
              child: Row(
                children: [
                  const AppLogo(size: 30, showGlow: false),
                  const SizedBox(width: 10),
                  Text(
                    AppConfig.appName,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.3,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    'v${AppConfig.appVersion}',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            _DrawerHeader(user: user),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(10, 10, 10, 8),
                children: [
                  _NavTile(
                    icon: Icons.space_dashboard_rounded,
                    label: 'Inicio',
                    selected: currentDestinationId == 'home',
                    onTap: () => Navigator.of(context).pop(),
                  ),
                  for (final section in MenuSection.values)
                    if ((grouped[section] ?? const []).isNotEmpty) ...[
                      _SectionLabel(label: section.label),
                      for (final destination in grouped[section]!)
                        _NavTile(
                          icon: destination.icon,
                          label: destination.label,
                          selected: currentDestinationId == destination.id,
                          onTap: () => _openDestination(context, destination),
                        ),
                    ],
                  const _SectionLabel(label: 'Cuenta'),
                  _NavTile(
                    icon: Icons.person_outline_rounded,
                    label: 'Mi perfil',
                    onTap: () => _openPage(context, const ProfilePage()),
                  ),
                  const _SectionLabel(label: 'Preferencias'),
                  _NavTile(
                    icon: Icons.palette_outlined,
                    label: 'Apariencia',
                    trailing: theme.themeLabel,
                    onTap: () => _openPage(context, const SettingsPage()),
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            ),
            const Divider(height: 1),
            SwitchListTile.adaptive(
              value: theme.isDark,
              onChanged: (value) => context.read<ThemeProvider>().setThemeMode(
                value ? ThemeMode.dark : ThemeMode.light,
              ),
              secondary: Icon(
                theme.isDark
                    ? Icons.dark_mode_rounded
                    : Icons.light_mode_rounded,
                size: 20,
              ),
              title: const Text('Tema oscuro'),
              subtitle: Text(theme.themeLabel),
              contentPadding: const EdgeInsets.symmetric(horizontal: 18),
            ),
            ListTile(
              leading: Icon(
                Icons.logout_rounded,
                size: 20,
                color: scheme.error,
              ),
              title: Text(
                'Cerrar sesión',
                style: TextStyle(
                  color: scheme.error,
                  fontWeight: FontWeight.w600,
                ),
              ),
              onTap: () => _confirmLogout(context),
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: 10, top: 2),
              child: Text(
                '${AppConfig.appName} · ${AppConfig.appVersion}',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _openDestination(BuildContext context, AppDestination destination) {
    _openPage(context, destination.buildPage());
  }

  void _openPage(BuildContext context, Widget page) {
    final navigator = Navigator.of(context);
    navigator.pop();
    navigator.push(MaterialPageRoute(builder: (_) => page));
  }

  Future<void> _confirmLogout(BuildContext context) async {
    final auth = context.read<AuthProvider>();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        final scheme = Theme.of(dialogContext).colorScheme;
        return AlertDialog(
          title: const Text('Cerrar sesión'),
          content: const Text(
            '¿Seguro que quieres salir de CrediStore? Deberás ingresar tus credenciales de nuevo.',
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
              child: const Text('Cerrar sesión'),
            ),
          ],
        );
      },
    );

    if (confirmed == true) {
      await auth.logout();
    }
  }
}

class _DrawerHeader extends StatelessWidget {
  const _DrawerHeader({required this.user});

  final AuthUser user;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: AppTheme.heroGradient(context),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: scheme.primary.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: scheme.surface.withValues(alpha: 0.75),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: scheme.surface.withValues(alpha: 0.9),
                  ),
                ),
                alignment: Alignment.center,
                child: Text(
                  user.initials,
                  style: textTheme.titleMedium?.copyWith(
                    color: scheme.primary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
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
                        color: scheme.onSurface,
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
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final role in user.roles)
                _HeaderChip(label: roleLabel(role)),
              if (user.roles.isEmpty) const _HeaderChip(label: 'Sin rol'),
              if (user.isActive)
                _HeaderChip(
                  label: 'Activo',
                  icon: Icons.check_circle_rounded,
                  color: scheme.tertiary,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _HeaderChip extends StatelessWidget {
  const _HeaderChip({required this.label, this.icon, this.color});

  final String label;
  final IconData? icon;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: scheme.surface.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: scheme.surface.withValues(alpha: 0.8)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: color ?? scheme.onSurfaceVariant),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: color ?? scheme.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 16, 12, 5),
      child: Text(
        label.toUpperCase(),
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: scheme.onSurfaceVariant,
          letterSpacing: 1.1,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _NavTile extends StatelessWidget {
  const _NavTile({
    required this.icon,
    required this.label,
    required this.onTap,
    this.selected = false,
    this.trailing,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool selected;
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return ListTile(
      dense: true,
      leading: Icon(
        icon,
        size: 20,
        color: selected ? scheme.primary : scheme.onSurfaceVariant,
      ),
      title: Text(
        label,
        style: textTheme.bodyMedium?.copyWith(
          fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
          color: selected ? scheme.primary : scheme.onSurface,
        ),
      ),
      trailing: trailing != null
          ? Text(
              trailing!,
              style: textTheme.labelSmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            )
          : (selected
                ? Icon(
                    Icons.chevron_right_rounded,
                    size: 18,
                    color: scheme.primary,
                  )
                : null),
      selected: selected,
      onTap: onTap,
    );
  }
}
