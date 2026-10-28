import 'package:credit_store_app/features/settings/providers/theme_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('el tema por defecto es claro', () async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final provider = ThemeProvider(preferences);

    expect(provider.themeMode, ThemeMode.light);
    expect(provider.isDark, isFalse);
    expect(provider.themeLabel, ThemeProvider.lightLabel);
  });

  test('persiste el tema oscuro en shared_preferences', () async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final provider = ThemeProvider(preferences);

    await provider.setThemeMode(ThemeMode.dark);

    expect(provider.isDark, isTrue);
    expect(provider.themeLabel, ThemeProvider.darkLabel);
    expect(preferences.getString(ThemeProvider.preferenceKey), 'dark');

    final reloaded = ThemeProvider(preferences);
    expect(reloaded.themeMode, ThemeMode.dark);
  });

  test('toggle alterna entre claro y oscuro', () async {
    SharedPreferences.setMockInitialValues({
      ThemeProvider.preferenceKey: 'dark',
    });
    final preferences = await SharedPreferences.getInstance();
    final provider = ThemeProvider(preferences);

    expect(provider.isDark, isTrue);
    await provider.toggle();
    expect(provider.isDark, isFalse);
    expect(preferences.getString(ThemeProvider.preferenceKey), 'light');
  });
}
