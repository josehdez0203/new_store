import 'package:credit_store_app/core/theme/app_palette.dart';
import 'package:credit_store_app/core/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('el tema claro usa Catppuccin Latte', () {
    final theme = AppTheme.light;

    expect(theme.brightness, Brightness.light);
    expect(theme.scaffoldBackgroundColor, CatppuccinLatte.base);
    expect(theme.colorScheme.primary, CatppuccinLatte.blue);
    expect(theme.colorScheme.secondary, CatppuccinLatte.mauve);
    expect(theme.colorScheme.surface, CatppuccinLatte.base);
  });

  test('el tema oscuro usa Tokyo Night', () {
    final theme = AppTheme.dark;

    expect(theme.brightness, Brightness.dark);
    expect(theme.scaffoldBackgroundColor, TokyoNight.bg);
    expect(theme.colorScheme.primary, TokyoNight.blue);
    expect(theme.colorScheme.secondary, TokyoNight.magenta);
    expect(theme.colorScheme.surface, TokyoNight.bg);
  });

  test('ambos temas usan Material 3', () {
    expect(AppTheme.light.useMaterial3, isTrue);
    expect(AppTheme.dark.useMaterial3, isTrue);
  });
}
