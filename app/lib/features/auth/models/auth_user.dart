/// Usuario autenticado con sus roles y permisos efectivos.
class AuthUser {
  const AuthUser({
    required this.id,
    required this.email,
    required this.fullName,
    required this.isActive,
    required this.roles,
    required this.permissions,
    this.lastLoginAt,
    this.createdAt,
  });

  final String id;
  final String email;
  final String fullName;
  final bool isActive;
  final List<String> roles;
  final List<String> permissions;
  final DateTime? lastLoginAt;
  final DateTime? createdAt;

  factory AuthUser.fromJson(Map<String, dynamic> json) {
    return AuthUser(
      id: json['id'] as String? ?? '',
      email: json['email'] as String? ?? '',
      fullName: json['full_name'] as String? ?? '',
      isActive: json['is_active'] as bool? ?? false,
      roles: _stringList(json['roles']),
      permissions: _stringList(json['permissions']),
      lastLoginAt: _date(json['last_login_at']),
      createdAt: _date(json['created_at']),
    );
  }

  bool hasPermission(String permission) {
    return permissions.contains(permission) || permissions.contains('*');
  }

  bool hasAnyPermission(Iterable<String> values) {
    if (permissions.contains('*')) {
      return true;
    }
    for (final value in values) {
      if (permissions.contains(value)) {
        return true;
      }
    }
    return false;
  }

  bool hasRole(String role) => roles.contains(role);

  String get displayName => fullName.trim().isEmpty ? email : fullName.trim();

  String get firstName {
    final name = displayName.trim();
    if (name.isEmpty) {
      return 'Usuario';
    }
    return name.split(RegExp(r'\s+')).first;
  }

  String get initials {
    final source = displayName.trim();
    if (source.isEmpty) {
      return '?';
    }
    final parts = source
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .toList();
    if (parts.length >= 2) {
      return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
    }
    final single = parts.first;
    if (single.length >= 2) {
      return single.substring(0, 2).toUpperCase();
    }
    return single.toUpperCase();
  }

  static List<String> _stringList(dynamic value) {
    if (value is List) {
      return value.whereType<String>().toList(growable: false);
    }
    return const [];
  }

  static DateTime? _date(dynamic value) {
    if (value is String && value.isNotEmpty) {
      return DateTime.tryParse(value);
    }
    return null;
  }
}
