import 'package:flutter/material.dart';

import '../../modules/pages/module_placeholder_page.dart';
import '../../customers/pages/customers_page.dart';
import '../../products/pages/products_page.dart';
import '../../sales/pages/credit_settings_page.dart';
import '../../sales/pages/sales_page.dart';
import '../../users/pages/users_page.dart';

/// Secciones del menú lateral.
enum MenuSection {
  operacion('Operación'),
  administracion('Administración');

  const MenuSection(this.label);

  final String label;
}

/// Una opción del menú protegida por un permiso.
class AppDestination {
  const AppDestination({
    required this.id,
    required this.label,
    required this.description,
    required this.icon,
    required this.section,
    this.permission,
    this.implemented = false,
  });

  final String id;
  final String label;
  final String description;
  final IconData icon;
  final MenuSection section;
  final String? permission;
  final bool implemented;

  bool isAllowed(Iterable<String> permissions) {
    if (permission == null) {
      return true;
    }
    final values = permissions.toSet();
    return values.contains('*') || values.contains(permission);
  }

  Widget buildPage() {
    if (id == 'products') {
      return const ProductsPage();
    }
    if (id == 'users') {
      return const UsersPage();
    }
    if (id == 'customers') {
      return const CustomersPage();
    }
    if (id == 'sales') {
      return const SalesPage();
    }
    if (id == 'credit_settings') {
      return const CreditSettingsPage();
    }
    return ModulePlaceholderPage(
      title: label,
      description: description,
      icon: icon,
      requiredPermission: permission,
    );
  }
}

/// Módulos del sistema ordenados por sección.
const List<AppDestination> appDestinations = [
  AppDestination(
    id: 'products',
    label: 'Productos',
    description: 'Administra el catálogo de productos y servicios.',
    icon: Icons.inventory_2_rounded,
    section: MenuSection.operacion,
    permission: 'products.read',
    implemented: true,
  ),
  AppDestination(
    id: 'sales',
    label: 'Ventas',
    description: 'Registra y consulta las ventas del negocio.',
    icon: Icons.point_of_sale_rounded,
    section: MenuSection.operacion,
    permission: 'sales.read',
    implemented: true,
  ),
  AppDestination(
    id: 'customers',
    label: 'Clientes',
    description: 'Administra la información de tus clientes.',
    icon: Icons.groups_rounded,
    section: MenuSection.operacion,
    permission: 'customers.read',
    implemented: true,
  ),
  AppDestination(
    id: 'credits',
    label: 'Créditos',
    description: 'Solicita, aprueba y da seguimiento a los créditos.',
    icon: Icons.account_balance_wallet_rounded,
    section: MenuSection.operacion,
    permission: 'credits.read',
  ),
  AppDestination(
    id: 'payments',
    label: 'Cobros',
    description: 'Registra pagos y consulta la cobranza.',
    icon: Icons.payments_rounded,
    section: MenuSection.operacion,
    permission: 'payments.read',
  ),
  AppDestination(
    id: 'reports',
    label: 'Reportes',
    description: 'Analiza el desempeño de ventas y créditos.',
    icon: Icons.insights_rounded,
    section: MenuSection.operacion,
    permission: 'reports.read',
  ),
  AppDestination(
    id: 'credit_settings',
    label: 'Configuración de crédito',
    description: 'Edita anticipos, plazos e interés de las ventas a crédito.',
    icon: Icons.tune_rounded,
    section: MenuSection.administracion,
    permission: 'credit_settings.update',
    implemented: true,
  ),
  AppDestination(
    id: 'users',
    label: 'Usuarios',
    description: 'Crea usuarios y asigna roles.',
    icon: Icons.manage_accounts_rounded,
    section: MenuSection.administracion,
    permission: 'users.read',
    implemented: true,
  ),
  AppDestination(
    id: 'roles',
    label: 'Roles',
    description: 'Define roles y sus permisos.',
    icon: Icons.admin_panel_settings_rounded,
    section: MenuSection.administracion,
    permission: 'roles.read',
  ),
  AppDestination(
    id: 'permissions',
    label: 'Permisos',
    description: 'Administra el catálogo de permisos.',
    icon: Icons.key_rounded,
    section: MenuSection.administracion,
    permission: 'permissions.read',
  ),
  AppDestination(
    id: 'settings',
    label: 'Configuración',
    description: 'Configura los parámetros generales del sistema.',
    icon: Icons.settings_rounded,
    section: MenuSection.administracion,
    permission: 'settings.read',
  ),
];

/// Devuelve los módulos visibles para el conjunto de permisos dado.
List<AppDestination> visibleDestinations(Iterable<String> permissions) {
  return appDestinations
      .where((destination) => destination.isAllowed(permissions))
      .toList(growable: false);
}

/// Agrupa los destinos visibles por sección.
Map<MenuSection, List<AppDestination>> destinationsBySection(
  Iterable<String> permissions,
) {
  final grouped = <MenuSection, List<AppDestination>>{};
  for (final destination in visibleDestinations(permissions)) {
    grouped.putIfAbsent(destination.section, () => []).add(destination);
  }
  return grouped;
}
