import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Preferencia de tema del usuario.
///
/// Solo se admiten dos valores: claro (Catppuccin Latte) y oscuro
/// (Tokyo Night). El valor por defecto es claro.
class ThemeProvider extends ChangeNotifier {
  ThemeProvider(this._preferences) {
    _themeMode = _preferences.getString(preferenceKey) == 'dark'
        ? ThemeMode.dark
        : ThemeMode.light;
  }

  static const String preferenceKey = 'preferences.theme_mode';
  static const String lightLabel = 'Catppuccin Latte';
  static const String darkLabel = 'Tokyo Night';

  final SharedPreferences _preferences;

  ThemeMode _themeMode = ThemeMode.light;

  ThemeMode get themeMode => _themeMode;
  bool get isDark => _themeMode == ThemeMode.dark;
  String get themeLabel => isDark ? darkLabel : lightLabel;

  Future<void> setThemeMode(ThemeMode mode) async {
    final normalized = mode == ThemeMode.dark
        ? ThemeMode.dark
        : ThemeMode.light;
    if (_themeMode == normalized) {
      return;
    }
    _themeMode = normalized;
    notifyListeners();
    await _preferences.setString(
      preferenceKey,
      normalized == ThemeMode.dark ? 'dark' : 'light',
    );
  }

  Future<void> toggle() {
    return setThemeMode(isDark ? ThemeMode.light : ThemeMode.dark);
  }
}
