import 'package:flutter/material.dart';

import 'app_palette.dart';

/// Temas Material 3 de la aplicación.
///
/// Claro: Catppuccin Latte. Oscuro: Tokyo Night.
abstract final class AppTheme {
  static const double cardRadius = 18;
  static const double fieldRadius = 14;

  static ThemeData get light {
    const scheme = ColorScheme.light(
      primary: CatppuccinLatte.blue,
      onPrimary: Colors.white,
      primaryContainer: Color(0xFFD8E6FF),
      onPrimaryContainer: Color(0xFF0B2E6F),
      secondary: CatppuccinLatte.mauve,
      onSecondary: Colors.white,
      secondaryContainer: Color(0xFFEBDDFF),
      onSecondaryContainer: Color(0xFF3B1F63),
      tertiary: CatppuccinLatte.teal,
      onTertiary: Colors.white,
      tertiaryContainer: Color(0xFFC9F4EF),
      onTertiaryContainer: Color(0xFF093D3A),
      error: CatppuccinLatte.red,
      onError: Colors.white,
      errorContainer: Color(0xFFFFD9DF),
      onErrorContainer: Color(0xFF5A0A18),
      surface: CatppuccinLatte.base,
      onSurface: CatppuccinLatte.text,
      surfaceDim: CatppuccinLatte.crust,
      surfaceBright: Colors.white,
      surfaceContainerLowest: Colors.white,
      surfaceContainerLow: Color(0xFFF7F8FB),
      surfaceContainer: CatppuccinLatte.mantle,
      surfaceContainerHigh: CatppuccinLatte.crust,
      surfaceContainerHighest: CatppuccinLatte.surface0,
      onSurfaceVariant: CatppuccinLatte.subtext0,
      outline: CatppuccinLatte.overlay0,
      outlineVariant: CatppuccinLatte.surface0,
      shadow: Colors.black,
      scrim: Colors.black,
      inverseSurface: CatppuccinLatte.text,
      onInverseSurface: CatppuccinLatte.base,
      inversePrimary: Color(0xFF9CC0FF),
      surfaceTint: CatppuccinLatte.blue,
    );

    return _build(
      scheme: scheme,
      scaffold: CatppuccinLatte.base,
      card: Colors.white,
      drawer: CatppuccinLatte.mantle,
      inputFill: Colors.white,
    );
  }

  static ThemeData get dark {
    const scheme = ColorScheme.dark(
      primary: TokyoNight.blue,
      onPrimary: TokyoNight.bgDark,
      primaryContainer: Color(0xFF33467C),
      onPrimaryContainer: TokyoNight.fg,
      secondary: TokyoNight.magenta,
      onSecondary: TokyoNight.bgDark,
      secondaryContainer: Color(0xFF3D2C5C),
      onSecondaryContainer: Color(0xFFE9DFFF),
      tertiary: TokyoNight.cyan,
      onTertiary: TokyoNight.bgDark,
      tertiaryContainer: Color(0xFF1E4A5C),
      onTertiaryContainer: Color(0xFFD4F7FF),
      error: TokyoNight.red,
      onError: TokyoNight.bgDark,
      errorContainer: Color(0xFF5A2435),
      onErrorContainer: Color(0xFFFFD9E0),
      surface: TokyoNight.bg,
      onSurface: TokyoNight.fg,
      surfaceDim: TokyoNight.bgDark,
      surfaceBright: TokyoNight.bgHighlight,
      surfaceContainerLowest: TokyoNight.bgDark,
      surfaceContainerLow: Color(0xFF1E2030),
      surfaceContainer: Color(0xFF24283B),
      surfaceContainerHigh: TokyoNight.bgHighlight,
      surfaceContainerHighest: TokyoNight.fgGutter,
      onSurfaceVariant: TokyoNight.fgDark,
      outline: TokyoNight.comment,
      outlineVariant: TokyoNight.fgGutter,
      shadow: Colors.black,
      scrim: Colors.black,
      inverseSurface: TokyoNight.fg,
      onInverseSurface: TokyoNight.bg,
      inversePrimary: CatppuccinLatte.blue,
      surfaceTint: TokyoNight.blue,
    );

    return _build(
      scheme: scheme,
      scaffold: TokyoNight.bg,
      card: const Color(0xFF1E2030),
      drawer: TokyoNight.bgDark,
      inputFill: const Color(0xFF1E2030),
    );
  }

  /// Gradiente usado en las tarjetas de bienvenida y el login.
  static LinearGradient heroGradient(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [scheme.primaryContainer, scheme.secondaryContainer],
    );
  }

  static ThemeData _build({
    required ColorScheme scheme,
    required Color scaffold,
    required Color card,
    required Color drawer,
    required Color inputFill,
  }) {
    final base = ThemeData(
      useMaterial3: true,
      brightness: scheme.brightness,
      colorScheme: scheme,
    );
    final textTheme = _textTheme(base.textTheme, scheme.onSurface);

    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(fieldRadius),
      borderSide: BorderSide(color: scheme.outlineVariant),
    );

    return base.copyWith(
      scaffoldBackgroundColor: scaffold,
      canvasColor: scaffold,
      textTheme: textTheme,
      primaryTextTheme: textTheme,
      iconTheme: IconThemeData(color: scheme.onSurfaceVariant),
      appBarTheme: AppBarTheme(
        backgroundColor: scaffold,
        foregroundColor: scheme.onSurface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: textTheme.titleLarge?.copyWith(
          fontWeight: FontWeight.w700,
          color: scheme.onSurface,
        ),
        iconTheme: IconThemeData(color: scheme.onSurface),
      ),
      drawerTheme: DrawerThemeData(
        backgroundColor: drawer,
        surfaceTintColor: Colors.transparent,
        width: 308,
      ),
      cardTheme: CardThemeData(
        color: card,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(cardRadius),
          side: BorderSide(
            color: scheme.outlineVariant.withValues(alpha: 0.75),
          ),
        ),
      ),
      dividerTheme: DividerThemeData(
        color: scheme.outlineVariant.withValues(alpha: 0.7),
        thickness: 1,
        space: 1,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: inputFill,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 16,
        ),
        border: border,
        enabledBorder: border,
        disabledBorder: border,
        focusedBorder: border.copyWith(
          borderSide: BorderSide(color: scheme.primary, width: 1.6),
        ),
        errorBorder: border.copyWith(
          borderSide: BorderSide(color: scheme.error),
        ),
        focusedErrorBorder: border.copyWith(
          borderSide: BorderSide(color: scheme.error, width: 1.6),
        ),
        hintStyle: textTheme.bodyMedium?.copyWith(
          color: scheme.onSurfaceVariant,
        ),
        labelStyle: textTheme.bodyMedium?.copyWith(
          color: scheme.onSurfaceVariant,
        ),
        floatingLabelStyle: textTheme.bodySmall?.copyWith(
          color: scheme.primary,
        ),
        prefixIconColor: scheme.onSurfaceVariant,
        suffixIconColor: scheme.onSurfaceVariant,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(0, 50),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(fieldRadius),
          ),
          textStyle: textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(0, 44),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(fieldRadius),
          ),
          side: BorderSide(color: scheme.outlineVariant),
          textStyle: textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: scheme.primary,
          textStyle: textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(foregroundColor: scheme.onSurfaceVariant),
      ),
      listTileTheme: ListTileThemeData(
        iconColor: scheme.onSurfaceVariant,
        textColor: scheme.onSurface,
        selectedColor: scheme.primary,
        selectedTileColor: scheme.primaryContainer.withValues(alpha: 0.55),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: scheme.surfaceContainerHigh,
        selectedColor: scheme.primaryContainer,
        labelStyle: textTheme.labelMedium?.copyWith(color: scheme.onSurface),
        side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.7)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: scheme.inverseSurface,
        contentTextStyle: textTheme.bodyMedium?.copyWith(
          color: scheme.onInverseSurface,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: card,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        titleTextStyle: textTheme.headlineSmall?.copyWith(
          fontWeight: FontWeight.w700,
          color: scheme.onSurface,
        ),
        contentTextStyle: textTheme.bodyMedium?.copyWith(
          color: scheme.onSurfaceVariant,
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          return states.contains(WidgetState.selected)
              ? scheme.onPrimary
              : scheme.outline;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          return states.contains(WidgetState.selected)
              ? scheme.primary
              : scheme.surfaceContainerHighest;
        }),
        trackOutlineColor: WidgetStateProperty.all(scheme.outlineVariant),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(color: scheme.primary),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: scheme.primary,
        selectionColor: scheme.primaryContainer,
        selectionHandleColor: scheme.primary,
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: scheme.inverseSurface,
          borderRadius: BorderRadius.circular(8),
        ),
        textStyle: textTheme.bodySmall?.copyWith(
          color: scheme.onInverseSurface,
        ),
      ),
    );
  }

  static TextTheme _textTheme(TextTheme base, Color color) {
    return base
        .copyWith(
          displaySmall: base.displaySmall?.copyWith(
            fontWeight: FontWeight.w800,
            letterSpacing: -1.2,
            height: 1.08,
          ),
          headlineMedium: base.headlineMedium?.copyWith(
            fontWeight: FontWeight.w800,
            letterSpacing: -0.8,
            height: 1.12,
          ),
          headlineSmall: base.headlineSmall?.copyWith(
            fontWeight: FontWeight.w700,
            letterSpacing: -0.4,
          ),
          titleLarge: base.titleLarge?.copyWith(
            fontWeight: FontWeight.w700,
            letterSpacing: -0.3,
          ),
          titleMedium: base.titleMedium?.copyWith(fontWeight: FontWeight.w600),
          titleSmall: base.titleSmall?.copyWith(fontWeight: FontWeight.w600),
          bodyLarge: base.bodyLarge?.copyWith(height: 1.5),
          bodyMedium: base.bodyMedium?.copyWith(height: 1.5),
          bodySmall: base.bodySmall?.copyWith(height: 1.45),
          labelLarge: base.labelLarge?.copyWith(
            fontWeight: FontWeight.w700,
            letterSpacing: 0.1,
          ),
        )
        .apply(bodyColor: color, displayColor: color);
  }
}
