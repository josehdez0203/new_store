/// Estados del ciclo de vida de un cliente.
abstract final class CustomerStatuses {
  static const String prospect = 'prospecto';
  static const String customer = 'cliente';
  static const String inPayment = 'en_pago';
  static const String settled = 'liquidado';

  static const List<String> values = [prospect, customer, inPayment, settled];

  static String label(String status) {
    return switch (status) {
      prospect => 'Prospecto',
      customer => 'Cliente',
      inPayment => 'En pago',
      settled => 'Liquidado',
      _ => status,
    };
  }
}

/// Cliente del negocio.
class Customer {
  const Customer({
    required this.id,
    required this.name,
    required this.status,
    this.address,
    this.city,
    this.postalCode,
    this.phone,
    this.email,
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String name;
  final String? address;
  final String? city;
  final String? postalCode;
  final String? phone;
  final String? email;
  final String status;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  String get statusLabel => CustomerStatuses.label(status);

  String get location {
    final parts = [
      if (city != null && city!.trim().isNotEmpty) city!,
      if (postalCode != null && postalCode!.trim().isNotEmpty) 'CP $postalCode',
    ];
    return parts.isEmpty ? '—' : parts.join(' · ');
  }

  factory Customer.fromJson(Map<String, dynamic> json) {
    return Customer(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      address: _nullableString(json['address']),
      city: _nullableString(json['city']),
      postalCode: _nullableString(json['postal_code']),
      phone: _nullableString(json['phone']),
      email: _nullableString(json['email']),
      status: json['status'] as String? ?? CustomerStatuses.prospect,
      createdAt: _date(json['created_at']),
      updatedAt: _date(json['updated_at']),
    );
  }

  static String? _nullableString(dynamic value) {
    if (value is String && value.trim().isNotEmpty) {
      return value;
    }
    return null;
  }

  static DateTime? _date(dynamic value) {
    if (value is String && value.isNotEmpty) {
      return DateTime.tryParse(value);
    }
    return null;
  }
}

/// Datos editables del cliente.
class CustomerFormData {
  const CustomerFormData({
    required this.name,
    required this.status,
    this.address,
    this.city,
    this.postalCode,
    this.phone,
    this.email,
  });

  final String name;
  final String? address;
  final String? city;
  final String? postalCode;
  final String? phone;
  final String? email;
  final String status;

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'address': address,
      'city': city,
      'postal_code': postalCode,
      'phone': phone,
      'email': email,
      'status': status,
    };
  }
}
