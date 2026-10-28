import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/config/app_config.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/section_header.dart';
import '../../auth/models/auth_user.dart';
import '../../auth/providers/auth_provider.dart';
import '../../settings/pages/settings_page.dart';
import '../../settings/providers/theme_provider.dart';
import '../widgets/app_drawer.dart';
import '../widgets/stat_card.dart';

/// Pantalla principal para cualquier usuario autenticado.
class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  Future<ApiResult>? _statsFuture;

  @override
  void initState() {
    super.initState();
    final user = context.read<AuthProvider>().user;
    if (user != null && user.hasPermission('dashboard.read')) {
      _statsFuture = context.read<ApiClient>().get('/dashboard/stats');
    }
  }

  void _reloadStats() {
    final user = context.read<AuthProvider>().user;
    if (user == null || !user.hasPermission('dashboard.read')) {
      setState(() => _statsFuture = null);
      return;
    }
    setState(() {
      _statsFuture = context.read<ApiClient>().get('/dashboard/stats');
    });
  }

  Future<void> _refresh() async {
    await context.read<AuthProvider>().refreshUser();
    if (!mounted) {
      return;
    }
    _reloadStats();
    final future = _statsFuture;
    if (future != null) {
      try {
        await future;
      } catch (_) {
        // El FutureBuilder muestra el error.
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final theme = context.watch<ThemeProvider>();
    final user = auth.user;

    if (user == null) {
      return const SizedBox.shrink();
    }

    final scheme = Theme.of(context).colorScheme;
    final canSeeDashboard = user.hasPermission('dashboard.read');

    return Scaffold(
      drawer: const AppDrawer(),
      appBar: AppBar(
        title: const Text('Inicio'),
        actions: [
          IconButton(
            tooltip: 'Actualizar',
            onPressed: _refresh,
            icon: const Icon(Icons.refresh_rounded),
          ),
          IconButton(
            tooltip: theme.isDark
                ? 'Cambiar a tema claro'
                : 'Cambiar a tema oscuro',
            onPressed: () => context.read<ThemeProvider>().toggle(),
            icon: Icon(
              theme.isDark ? Icons.light_mode_rounded : Icons.dark_mode_rounded,
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(20),
          children: [
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1120),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _WelcomeCard(user: user),
                    if (canSeeDashboard) ...[
                      const SizedBox(height: 30),
                      SectionHeader(
                        title: 'Resumen',
                        subtitle: 'Estado general del sistema',
                        trailing: TextButton.icon(
                          onPressed: _reloadStats,
                          icon: const Icon(Icons.refresh_rounded, size: 16),
                          label: const Text('Actualizar'),
                        ),
                      ),
                      const SizedBox(height: 12),
                      _StatsSection(
                        future: _statsFuture,
                        onRetry: _reloadStats,
                      ),
                    ],
                    const SizedBox(height: 30),
                    const SectionHeader(
                      title: 'Apariencia',
                      subtitle: 'Preferencias visuales de tu cuenta',
                    ),
                    const SizedBox(height: 12),
                    const _AppearanceCard(),
                    const SizedBox(height: 34),
                    Center(
                      child: Text(
                        '${AppConfig.appName} v${AppConfig.appVersion}'
                        ' · ${AppConfig.appSubtitle}',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
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

class _WelcomeCard extends StatelessWidget {
  const _WelcomeCard({required this.user});

  final AuthUser user;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    final avatar = Container(
      width: 72,
      height: 72,
      decoration: BoxDecoration(
        color: scheme.surface.withValues(alpha: 0.8),
        shape: BoxShape.circle,
        border: Border.all(color: scheme.surface, width: 1.5),
      ),
      alignment: Alignment.center,
      child: Text(
        user.initials,
        style: textTheme.headlineSmall?.copyWith(
          color: scheme.primary,
          fontWeight: FontWeight.w800,
        ),
      ),
    );

    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${greetingFor(DateTime.now())},',
          style: textTheme.titleSmall?.copyWith(
            color: scheme.onSurfaceVariant,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          user.firstName,
          style: textTheme.headlineMedium?.copyWith(
            fontWeight: FontWeight.w800,
            letterSpacing: -1,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Este es tu panel de ${AppConfig.appName}. '
          'Usa el menú lateral para acceder a los módulos de tu rol.',
          style: textTheme.bodySmall?.copyWith(
            color: scheme.onSurfaceVariant,
            height: 1.5,
          ),
        ),
        const SizedBox(height: 14),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final role in user.roles)
              _WelcomeChip(icon: Icons.badge_outlined, label: roleLabel(role)),
            _WelcomeChip(
              icon: Icons.key_rounded,
              label: '${user.permissions.length} permisos',
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
          final compact = constraints.maxWidth < 620;
          if (compact) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [avatar, const SizedBox(height: 16), content],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              avatar,
              const SizedBox(width: 20),
              Expanded(child: content),
              Icon(
                Icons.auto_awesome_rounded,
                size: 54,
                color: scheme.primary.withValues(alpha: 0.22),
              ),
              const SizedBox(width: 8),
            ],
          );
        },
      ),
    );
  }
}

class _WelcomeChip extends StatelessWidget {
  const _WelcomeChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: scheme.surface.withValues(alpha: 0.62),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: scheme.surface.withValues(alpha: 0.85)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: scheme.onSurfaceVariant),
          const SizedBox(width: 5),
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: scheme.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatsSection extends StatelessWidget {
  const _StatsSection({required this.future, required this.onRetry});

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
              padding: const EdgeInsets.all(22),
              child: Row(
                children: [
                  const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2.2),
                  ),
                  const SizedBox(width: 14),
                  Text(
                    'Cargando métricas...',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
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
          final message = error is ApiException
              ? error.displayMessage
              : 'No se pudieron cargar las métricas.';
          return Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Row(
                children: [
                  Icon(Icons.cloud_off_rounded, color: scheme.error),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Sin datos disponibles',
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          message,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: scheme.onSurfaceVariant),
                        ),
                      ],
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

        final data = snapshot.data?.asMap ?? const <String, dynamic>{};
        final items = [
          _StatItem(
            label: 'Usuarios activos',
            value: _formatNumber(data['users_active']),
            caption: '${_formatNumber(data['users_total'])} registrados',
            icon: Icons.people_alt_rounded,
            accent: scheme.primary,
          ),
          _StatItem(
            label: 'Roles',
            value: _formatNumber(data['roles_total']),
            caption: 'Perfiles de acceso',
            icon: Icons.admin_panel_settings_rounded,
            accent: scheme.secondary,
          ),
          _StatItem(
            label: 'Permisos',
            value: _formatNumber(data['permissions_total']),
            caption: 'En el catálogo',
            icon: Icons.key_rounded,
            accent: scheme.tertiary,
          ),
          _StatItem(
            label: 'Sesiones',
            value: _formatNumber(data['active_sessions']),
            caption: 'Activas ahora',
            icon: Icons.devices_rounded,
            accent: scheme.primary,
          ),
        ];

        return LayoutBuilder(
          builder: (context, constraints) {
            final columns = constraints.maxWidth >= 960 ? 4 : 2;
            const spacing = 12.0;
            return GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              padding: EdgeInsets.zero,
              itemCount: items.length,
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: columns,
                crossAxisSpacing: spacing,
                mainAxisSpacing: spacing,
                mainAxisExtent: 158,
              ),
              itemBuilder: (context, index) {
                final item = items[index];
                return StatCard(
                  label: item.label,
                  value: item.value,
                  caption: item.caption,
                  icon: item.icon,
                  accent: item.accent,
                );
              },
            );
          },
        );
      },
    );
  }

  static String _formatNumber(dynamic value) {
    final number = value is num
        ? value.toInt()
        : int.tryParse('${value ?? 0}') ?? 0;
    return number.toString().replaceAllMapped(
      RegExp(r'\B(?=(\d{3})+(?!\d))'),
      (match) => '.',
    );
  }
}

class _StatItem {
  const _StatItem({
    required this.label,
    required this.value,
    required this.caption,
    required this.icon,
    required this.accent,
  });

  final String label;
  final String value;
  final String caption;
  final IconData icon;
  final Color accent;
}

class _AppearanceCard extends StatelessWidget {
  const _AppearanceCard();

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<ThemeProvider>();
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (_) => const SettingsPage())),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: scheme.secondaryContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(Icons.palette_outlined, color: scheme.secondary),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Tema actual',
                      style: textTheme.labelSmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(theme.themeLabel, style: textTheme.titleSmall),
                  ],
                ),
              ),
              Switch.adaptive(
                value: theme.isDark,
                onChanged: (value) => context
                    .read<ThemeProvider>()
                    .setThemeMode(value ? ThemeMode.dark : ThemeMode.light),
              ),
              Icon(Icons.chevron_right_rounded, color: scheme.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}
