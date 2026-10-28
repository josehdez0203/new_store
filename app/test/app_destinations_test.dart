import 'package:credit_store_app/features/home/navigation/app_destinations.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('el comodín ve todos los módulos', () {
    final destinations = visibleDestinations(['*']);
    expect(destinations.length, appDestinations.length);
  });

  test('el vendedor no ve módulos de administración', () {
    final destinations = visibleDestinations([
      'saludo',
      'dashboard.read',
      'customers.read',
      'sales.read',
      'credits.read',
      'reports.read',
    ]);
    final ids = destinations.map((destination) => destination.id).toList();

    expect(ids, containsAll(['sales', 'customers', 'credits', 'reports']));
    expect(ids, isNot(contains('users')));
    expect(ids, isNot(contains('roles')));
    expect(ids, isNot(contains('permissions')));
  });

  test('el cobrador solo ve cobros y consultas', () {
    final ids = visibleDestinations([
      'dashboard.read',
      'customers.read',
      'credits.read',
      'payments.read',
      'reports.read',
    ]).map((destination) => destination.id);

    expect(ids, contains('payments'));
    expect(ids, isNot(contains('sales')));
    expect(ids, isNot(contains('users')));
  });

  test('agrupa por sección y omite secciones vacías', () {
    final grouped = destinationsBySection(['sales.read', 'users.read']);

    expect(grouped[MenuSection.operacion]?.single.id, 'sales');
    expect(grouped[MenuSection.administracion]?.single.id, 'users');
    expect(destinationsBySection([]), isEmpty);
  });

  test('todas las opciones tienen permiso y sección', () {
    for (final destination in appDestinations) {
      expect(destination.permission, isNotNull);
      expect(destination.label, isNotEmpty);
    }
  });
}
