import 'package:credit_store_app/features/auth/models/auth_user.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parsea roles, permisos y fechas del API', () {
    final user = AuthUser.fromJson({
      'id': 'f4d77e1c-75c2-4e5e-8a6f-d52e2a2b5e11',
      'email': 'admin@gmail.com',
      'full_name': 'Administrador del Sistema',
      'is_active': true,
      'roles': ['admin'],
      'permissions': ['users.read', 'users.create', 'sales.read'],
      'last_login_at': '2026-10-26T16:00:00-06:00',
      'created_at': '2026-01-15T10:00:00Z',
    });

    expect(user.email, 'admin@gmail.com');
    expect(user.roles, ['admin']);
    expect(user.permissions, contains('users.read'));
    expect(user.hasPermission('users.create'), isTrue);
    expect(user.hasPermission('users.delete'), isFalse);
    expect(user.hasRole('admin'), isTrue);
    expect(user.lastLoginAt, isNotNull);
    expect(user.createdAt, isNotNull);
    expect(user.initials, 'AS');
  });

  test('el permiso comodín concede todo', () {
    final user = AuthUser.fromJson({
      'id': '1',
      'email': 'a@b.com',
      'full_name': 'Root',
      'is_active': true,
      'roles': <String>[],
      'permissions': ['*'],
    });

    expect(user.hasPermission('cualquier.cosa'), isTrue);
    expect(user.hasAnyPermission(['users.read', 'sales.read']), isTrue);
  });

  test('usa el correo cuando no hay nombre y calcula iniciales', () {
    final user = AuthUser.fromJson({
      'id': '1',
      'email': 'persona@correo.com',
      'full_name': '',
      'is_active': true,
      'roles': <String>[],
      'permissions': <String>[],
    });

    expect(user.displayName, 'persona@correo.com');
    expect(user.firstName, 'persona@correo.com');
    expect(user.initials, 'PE');
  });
}
