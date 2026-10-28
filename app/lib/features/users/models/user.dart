/// Usuario administrado desde el módulo de Usuarios.
class ManagedUser {
  const ManagedUser({
    required this.id,
    required this.email,
    required this.fullName,
    required this.isActive,
    required this.roles,
    this.lastLoginAt,
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String email;
  final String fullName;
  final bool isActive;
  final List<String> roles;
  final DateTime? lastLoginAt;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  String get displayName => fullName.trim().isEmpty ? email : fullName.trim();

  String get initials {
    final parts = displayName
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .toList();
    if (parts.isEmpty) {
      return '?';
    }
    if (parts.length >= 2) {
      return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
    }
    final single = parts.first;
    return single.length >= 2
        ? single.substring(0, 2).toUpperCase()
        : single.toUpperCase();
  }

  bool hasRole(String role) => roles.contains(role);

  factory ManagedUser.fromJson(Map<String, dynamic> json) {
    return ManagedUser(
      id: json['id'] as String? ?? '',
      email: json['email'] as String? ?? '',
      fullName: json['full_name'] as String? ?? '',
      isActive: json['is_active'] as bool? ?? false,
      roles: _stringList(json['roles']),
      lastLoginAt: _date(json['last_login_at']),
      createdAt: _date(json['created_at']),
      updatedAt: _date(json['updated_at']),
    );
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

/// Rol disponible para asignar.
class AppRole {
  const AppRole({
    required this.id,
    required this.name,
    required this.isSystem,
    this.description,
    this.userCount = 0,
    this.permissionCount = 0,
  });

  final String id;
  final String name;
  final String? description;
  final bool isSystem;
  final int userCount;
  final int permissionCount;

  factory AppRole.fromJson(Map<String, dynamic> json) {
    return AppRole(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      description: json['description'] as String?,
      isSystem: json['is_system'] as bool? ?? false,
      userCount: (json['user_count'] as num?)?.toInt() ?? 0,
      permissionCount: (json['permission_count'] as num?)?.toInt() ?? 0,
    );
  }
}

/// Datos del formulario de alta/edición de usuario.
class UserFormData {
  const UserFormData({
    required this.email,
    required this.fullName,
    required this.isActive,
    this.password,
    this.roleIds = const [],
  });

  final String email;
  final String fullName;
  final bool isActive;
  final String? password;
  final List<String> roleIds;

  Map<String, dynamic> toCreateJson() {
    return {
      'email': email,
      'full_name': fullName,
      'password': password,
      'is_active': isActive,
      'role_ids': roleIds,
    };
  }

  Map<String, dynamic> toUpdateJson() {
    return {
      'email': email,
      'full_name': fullName,
      'is_active': isActive,
      if (password != null) 'password': password,
    };
  }
}
