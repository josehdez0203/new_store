import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/section_header.dart';
import '../../auth/models/auth_user.dart';
import '../../auth/providers/auth_provider.dart';

/// Perfil del usuario autenticado y sus sesiones activas.
class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  Future<ApiResult>? _sessionsFuture;

  @override
  void initState() {
    super.initState();
    _sessionsFuture = context.read<ApiClient>().get('/auth/sessions');
  }

  Future<void> _reload() async {
    setState(() {
      _sessionsFuture = context.read<ApiClient>().get('/auth/sessions');
    });
    await context.read<AuthProvider>().refreshUser();
    final pending = _sessionsFuture;
    if (pending != null) {
      try {
        await pending;
      } catch (_) {
        // El FutureBuilder muestra el error.
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthProvider>().user;
    if (user == null) {
      return const SizedBox.shrink();
    }

    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Mi perfil'),
        actions: [
          IconButton(
            tooltip: 'Actualizar',
            onPressed: _reload,
            icon: const Icon(Icons.refresh_rounded),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _reload,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(20),
          children: [
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 920),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _ProfileHeader(user: user),
                    const SizedBox(height: 26),
                    const SectionHeader(
                      title: 'Información de la cuenta',
                      subtitle: 'Datos asociados a tu usuario',
                    ),
                    const SizedBox(height: 12),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 18,
                          vertical: 6,
                        ),
                        child: Column(
                          children: [
                            _InfoRow(
                              icon: Icons.alternate_email_rounded,
                              label: 'Correo electrónico',
                              value: user.email,
                            ),
                            const Divider(height: 1),
                            _InfoRow(
                              icon: Icons.login_rounded,
                              label: 'Último acceso',
                              value: formatDateTime(user.lastLoginAt),
                            ),
                            const Divider(height: 1),
                            _InfoRow(
                              icon: Icons.calendar_today_outlined,
                              label: 'Miembro desde',
                              value: formatDate(user.createdAt),
                            ),
                            const Divider(height: 1),
                            _InfoRow(
                              icon: Icons.verified_user_outlined,
                              label: 'Estado de la cuenta',
                              value: user.isActive ? 'Activa' : 'Inactiva',
                              valueColor: user.isActive
                                  ? scheme.tertiary
                                  : scheme.error,
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 26),
                    const SectionHeader(
                      title: 'Roles y permisos',
                      subtitle: 'Acceso efectivo en este momento',
                    ),
                    const SizedBox(height: 12),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(18),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Roles',
                              style: Theme.of(context).textTheme.labelMedium
                                  ?.copyWith(
                                    color: scheme.onSurfaceVariant,
                                    fontWeight: FontWeight.w700,
                                  ),
                            ),
                            const SizedBox(height: 8),
                            if (user.roles.isEmpty)
                              Text(
                                'Sin roles asignados.',
                                style: Theme.of(context).textTheme.bodySmall
                                    ?.copyWith(color: scheme.onSurfaceVariant),
                              )
                            else
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  for (final role in user.roles)
                                    Chip(
                                      avatar: Icon(
                                        Icons.badge_outlined,
                                        size: 15,
                                        color: scheme.primary,
                                      ),
                                      label: Text(roleLabel(role)),
                                    ),
                                ],
                              ),
                            const SizedBox(height: 18),
                            Text(
                              'Permisos (${user.permissions.length})',
                              style: Theme.of(context).textTheme.labelMedium
                                  ?.copyWith(
                                    color: scheme.onSurfaceVariant,
                                    fontWeight: FontWeight.w700,
                                  ),
                            ),
                            const SizedBox(height: 8),
                            if (user.permissions.isEmpty)
                              Text(
                                'Sin permisos asignados.',
                                style: Theme.of(context).textTheme.bodySmall
                                    ?.copyWith(color: scheme.onSurfaceVariant),
                              )
                            else
                              Wrap(
                                spacing: 6,
                                runSpacing: 6,
                                children: [
                                  for (final permission in user.permissions)
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 4,
                                      ),
                                      decoration: BoxDecoration(
                                        color: scheme.surfaceContainerHigh,
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(
                                          color: scheme.outlineVariant,
                                        ),
                                      ),
                                      child: Text(
                                        permission,
                                        style: Theme.of(context)
                                            .textTheme
                                            .labelSmall
                                            ?.copyWith(
                                              fontFamily: 'monospace',
                                              color: scheme.onSurfaceVariant,
                                              fontSize: 10.5,
                                            ),
                                      ),
                                    ),
                                ],
                              ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 26),
                    SectionHeader(
                      title: 'Sesiones activas',
                      subtitle: 'Dispositivos con acceso a tu cuenta',
                      trailing: TextButton.icon(
                        onPressed: _reload,
                        icon: const Icon(Icons.refresh_rounded, size: 16),
                        label: const Text('Actualizar'),
                      ),
                    ),
                    const SizedBox(height: 12),
                    _SessionsSection(future: _sessionsFuture, onRetry: _reload),
                    const SizedBox(height: 34),
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

class _ProfileHeader extends StatelessWidget {
  const _ProfileHeader({required this.user});

  final AuthUser user;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    final avatar = Container(
      width: 78,
      height: 78,
      decoration: BoxDecoration(
        color: scheme.surface.withValues(alpha: 0.8),
        shape: BoxShape.circle,
        border: Border.all(color: scheme.surface, width: 1.5),
      ),
      alignment: Alignment.center,
      child: Text(
        user.initials,
        style: textTheme.headlineMedium?.copyWith(
          color: scheme.primary,
          fontWeight: FontWeight.w800,
        ),
      ),
    );

    final info = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          user.displayName,
          style: textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 2),
        Text(
          user.email,
          style: textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final role in user.roles)
              _HeaderPill(label: roleLabel(role), icon: Icons.badge_outlined),
            _HeaderPill(
              label: user.isActive ? 'Activa' : 'Inactiva',
              icon: user.isActive
                  ? Icons.check_circle_rounded
                  : Icons.pause_circle_outline_rounded,
              color: user.isActive ? scheme.tertiary : scheme.error,
            ),
          ],
        ),
      ],
    );

    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        gradient: AppTheme.heroGradient(context),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: scheme.primary.withValues(alpha: 0.18)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth < 560) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [avatar, const SizedBox(height: 16), info],
            );
          }
          return Row(
            children: [
              avatar,
              const SizedBox(width: 20),
              Expanded(child: info),
            ],
          );
        },
      ),
    );
  }
}

class _HeaderPill extends StatelessWidget {
  const _HeaderPill({required this.label, required this.icon, this.color});

  final String label;
  final IconData icon;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: scheme.surface.withValues(alpha: 0.62),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: scheme.surface.withValues(alpha: 0.85)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color ?? scheme.onSurfaceVariant),
          const SizedBox(width: 5),
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

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
    this.valueColor,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 13),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 18, color: scheme.onSurfaceVariant),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: textTheme.labelSmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  value,
                  style: textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: valueColor,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SessionsSection extends StatelessWidget {
  const _SessionsSection({required this.future, required this.onRetry});

  final Future<ApiResult>? future;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final pending = future;
    if (pending == null) {
      return const SizedBox.shrink();
    }

    final scheme = Theme.of(context).colorScheme;

    return FutureBuilder<ApiResult>(
      future: pending,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'Cargando sesiones...',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        if (snapshot.hasError) {
          final error = snapshot.error;
          return Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Row(
                children: [
                  Icon(Icons.cloud_off_rounded, color: scheme.error),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      error is ApiException
                          ? error.displayMessage
                          : 'No se pudieron cargar las sesiones.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: onRetry,
                    child: const Text('Reintentar'),
                  ),
                ],
              ),
            ),
          );
        }

        final sessions = snapshot.data?.asList ?? const [];
        if (sessions.isEmpty) {
          return Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Text(
                'No hay otras sesiones activas.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
          );
        }

        return Column(
          children: [
            for (var index = 0; index < sessions.length; index++) ...[
              _SessionTile(session: sessions[index]),
              if (index < sessions.length - 1) const SizedBox(height: 10),
            ],
          ],
        );
      },
    );
  }
}

class _SessionTile extends StatelessWidget {
  const _SessionTile({required this.session});

  final Map<String, dynamic> session;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final current = session['current'] == true;
    final userAgent = session['user_agent'] as String?;
    final ip = session['ip_address'] as String?;
    final lastUsed = _date(session['last_used_at']);
    final expiresAt = _date(session['expires_at']);

    return Card(
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: current
                ? scheme.primaryContainer
                : scheme.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(11),
          ),
          child: Icon(
            _deviceIcon(userAgent),
            size: 20,
            color: current ? scheme.primary : scheme.onSurfaceVariant,
          ),
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(
                current ? 'Este dispositivo' : _deviceLabel(userAgent),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: textTheme.titleSmall,
              ),
            ),
            if (current)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: scheme.primaryContainer,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  'Actual',
                  style: textTheme.labelSmall?.copyWith(
                    color: scheme.primary,
                    fontWeight: FontWeight.w700,
                    fontSize: 10,
                  ),
                ),
              ),
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 3),
            Text(
              '${ip ?? 'IP no registrada'} · Último uso: ${timeAgo(lastUsed)}',
              style: textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 1),
            Text(
              'Expira: ${formatDateTime(expiresAt)}',
              style: textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _deviceLabel(String? userAgent) {
    if (userAgent == null || userAgent.trim().isEmpty) {
      return 'Dispositivo desconocido';
    }
    final lower = userAgent.toLowerCase();
    if (lower.contains('android')) {
      return 'Dispositivo Android';
    }
    if (lower.contains('iphone') || lower.contains('ipad')) {
      return 'Dispositivo iOS';
    }
    if (lower.contains('windows')) return 'Windows';
    if (lower.contains('mac os') || lower.contains('macintosh')) return 'macOS';
    if (lower.contains('linux')) return 'Linux';
    if (lower.contains('chrome')) return 'Chrome';
    return userAgent.length > 48 ? '${userAgent.substring(0, 48)}…' : userAgent;
  }

  static IconData _deviceIcon(String? userAgent) {
    if (userAgent == null) return Icons.devices_other_rounded;
    final lower = userAgent.toLowerCase();
    if (lower.contains('android') || lower.contains('iphone')) {
      return Icons.smartphone_rounded;
    }
    if (lower.contains('ipad') || lower.contains('tablet')) {
      return Icons.tablet_mac_rounded;
    }
    return Icons.computer_rounded;
  }

  static DateTime? _date(dynamic value) {
    if (value is String && value.isNotEmpty) {
      return DateTime.tryParse(value);
    }
    return null;
  }
}
