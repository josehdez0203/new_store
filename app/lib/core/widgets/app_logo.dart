import 'package:flutter/material.dart';

/// Marca gráfica de CrediStore.
class AppLogo extends StatelessWidget {
  const AppLogo({super.key, this.size = 52, this.showGlow = true});

  final double size;
  final bool showGlow;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [scheme.primary, scheme.tertiary],
        ),
        borderRadius: BorderRadius.circular(size * 0.3),
        boxShadow: showGlow
            ? [
                BoxShadow(
                  color: scheme.primary.withValues(alpha: 0.32),
                  blurRadius: size * 0.75,
                  offset: Offset(0, size * 0.18),
                ),
              ]
            : null,
      ),
      child: Icon(
        Icons.credit_score_rounded,
        color: scheme.onPrimary,
        size: size * 0.52,
      ),
    );
  }
}
