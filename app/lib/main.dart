import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'core/config/app_config.dart';
import 'core/network/api_client.dart';
import 'core/storage/token_storage.dart';
import 'features/auth/providers/auth_provider.dart';
import 'features/settings/providers/theme_provider.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final preferences = await SharedPreferences.getInstance();
  final themeProvider = ThemeProvider(preferences);
  final tokenStorage = TokenStorage(preferences);

  final apiClient = ApiClient(
    baseUrl: AppConfig.apiBaseUrl,
    storage: tokenStorage,
  );
  final authProvider = AuthProvider(api: apiClient, storage: tokenStorage);
  apiClient.onSessionExpired = authProvider.handleSessionExpired;

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<ThemeProvider>.value(value: themeProvider),
        ChangeNotifierProvider<AuthProvider>.value(value: authProvider),
        Provider<ApiClient>.value(value: apiClient),
      ],
      child: const CreditStoreApp(),
    ),
  );

  unawaited(authProvider.restore());
}
