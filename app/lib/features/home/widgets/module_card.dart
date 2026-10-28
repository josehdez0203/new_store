import 'package:flutter/material.dart';

import '../navigation/app_destinations.dart';

/// Acceso rápido a un módulo desde el home.
class ModuleCard extends StatelessWidget {
  const ModuleCard({super.key, required this.destination});

  final AppDestination destination;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (_) => destination.buildPage())),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: scheme.primaryContainer.withValues(alpha: 0.7),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      destination.icon,
                      size: 21,
                      color: scheme.primary,
                    ),
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: destination.implemented
                          ? scheme.tertiaryContainer
                          : scheme.surfaceContainerHigh,
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                        color: destination.implemented
                            ? scheme.tertiary.withValues(alpha: 0.35)
                            : scheme.outlineVariant,
                      ),
                    ),
                    child: Text(
                      destination.implemented ? 'Disponible' : 'Próximamente',
                      style: textTheme.labelSmall?.copyWith(
                        color: destination.implemented
                            ? scheme.onTertiaryContainer
                            : scheme.onSurfaceVariant,
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text(destination.label, style: textTheme.titleMedium),
              const SizedBox(height: 5),
              Text(
                destination.description,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Text(
                    'Abrir módulo',
                    style: textTheme.labelSmall?.copyWith(
                      color: scheme.primary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    Icons.arrow_forward_rounded,
                    size: 14,
                    color: scheme.primary,
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
