import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_palette.dart';
import '../providers/theme_provider.dart';
import '../widgets/theme_option_card.dart';

/// Página de preferencias visuales del usuario.
class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<ThemeProvider>();
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Apariencia')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 920),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Elige cómo se ve CrediStore',
                    style: textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Tu preferencia se guarda en este dispositivo y se aplica al instante. '
                    'El tema claro usa Catppuccin Latte y el oscuro Tokyo Night.',
                    style: textTheme.bodyMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 24),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final wide = constraints.maxWidth >= 700;
                      final lightCard = ThemeOptionCard(
                        title: ThemeProvider.lightLabel,
                        subtitle: 'Claro · suave y luminoso',
                        selected: !theme.isDark,
                        icon: Icons.light_mode_rounded,
                        previewBackground: CatppuccinLatte.base,
                        previewSurface: Colors.white,
                        previewPrimary: CatppuccinLatte.blue,
                        previewSecondary: CatppuccinLatte.mauve,
                        previewText: CatppuccinLatte.text,
                        onTap: () => theme.setThemeMode(ThemeMode.light),
                      );
                      final darkCard = ThemeOptionCard(
                        title: ThemeProvider.darkLabel,
                        subtitle: 'Oscuro · azul profundo',
                        selected: theme.isDark,
                        icon: Icons.dark_mode_rounded,
                        previewBackground: TokyoNight.bg,
                        previewSurface: const Color(0xFF1E2030),
                        previewPrimary: TokyoNight.blue,
                        previewSecondary: TokyoNight.magenta,
                        previewText: TokyoNight.fg,
                        onTap: () => theme.setThemeMode(ThemeMode.dark),
                      );

                      if (!wide) {
                        return Column(
                          children: [
                            lightCard,
                            const SizedBox(height: 16),
                            darkCard,
                          ],
                        );
                      }
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(child: lightCard),
                          const SizedBox(width: 16),
                          Expanded(child: darkCard),
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 24),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(18),
                      child: Row(
                        children: [
                          Container(
                            width: 42,
                            height: 42,
                            decoration: BoxDecoration(
                              color: scheme.primaryContainer,
                              borderRadius: BorderRadius.circular(11),
                            ),
                            child: Icon(
                              theme.isDark
                                  ? Icons.dark_mode_rounded
                                  : Icons.light_mode_rounded,
                              color: scheme.primary,
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Preferencia guardada',
                                  style: textTheme.titleSmall,
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'Tema actual: ${theme.themeLabel}. '
                                  'Se mantiene al cerrar sesión y volver a abrir la app.',
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
                  const SizedBox(height: 12),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(18),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                Icons.color_lens_outlined,
                                size: 18,
                                color: scheme.secondary,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'Paletas utilizadas',
                                style: textTheme.titleSmall,
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Text(
                            'Catppuccin Latte ofrece tonos pastel y bajo contraste para '
                            'sesiones largas. Tokyo Night aporta un fondo azul profundo '
                            'con acentos neón, ideal para ambientes oscuros.',
                            style: textTheme.bodySmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 14),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: const [
                              _PaletteChip(
                                label: 'Catppuccin Latte',
                                colors: [
                                  CatppuccinLatte.base,
                                  CatppuccinLatte.blue,
                                  CatppuccinLatte.mauve,
                                  CatppuccinLatte.teal,
                                ],
                              ),
                              _PaletteChip(
                                label: 'Tokyo Night',
                                colors: [
                                  TokyoNight.bg,
                                  TokyoNight.blue,
                                  TokyoNight.magenta,
                                  TokyoNight.cyan,
                                ],
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PaletteChip extends StatelessWidget {
  const _PaletteChip({required this.label, required this.colors});

  final String label;
  final List<Color> colors;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final color in colors) ...[
            Container(
              width: 13,
              height: 13,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
                border: Border.all(color: scheme.outlineVariant),
              ),
            ),
            const SizedBox(width: 3),
          ],
          const SizedBox(width: 5),
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: scheme.onSurface,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
