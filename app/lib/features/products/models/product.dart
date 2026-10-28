/// Tipos de producto admitidos por el API.
abstract final class ProductTypes {
  static const String product = 'product';
  static const String service = 'service';
}

/// Fotografía de un producto o servicio.
class ProductImage {
  const ProductImage({
    required this.id,
    required this.url,
    this.originalName,
    this.mimeType,
    this.sizeBytes = 0,
    this.sortOrder = 0,
    this.createdAt,
  });

  final String id;

  /// Ruta relativa servida por el API, por ejemplo `/downloads/products/...`.
  final String url;
  final String? originalName;
  final String? mimeType;
  final int sizeBytes;
  final int sortOrder;
  final DateTime? createdAt;

  factory ProductImage.fromJson(Map<String, dynamic> json) {
    return ProductImage(
      id: json['id'] as String? ?? '',
      url: json['url'] as String? ?? '',
      originalName: _nullableString(json['original_name']),
      mimeType: _nullableString(json['mime_type']),
      sizeBytes: (json['size_bytes'] as num?)?.toInt() ?? 0,
      sortOrder: (json['sort_order'] as num?)?.toInt() ?? 0,
      createdAt: _date(json['created_at']),
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

/// Producto o servicio del catálogo.
class Product {
  const Product({
    required this.id,
    required this.name,
    required this.price,
    required this.cost,
    required this.margin,
    required this.type,
    this.description,
    this.barcode,
    this.images = const [],
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String name;
  final String? description;
  final String? barcode;
  final double price;
  final double cost;
  final double margin;
  final String type;
  final List<ProductImage> images;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  bool get isService => type == ProductTypes.service;

  String get typeLabel => isService ? 'Servicio' : 'Producto';

  factory Product.fromJson(Map<String, dynamic> json) {
    final rawImages = json['images'];
    final images = rawImages is List
        ? rawImages
              .whereType<Map<String, dynamic>>()
              .map(ProductImage.fromJson)
              .toList(growable: false)
        : const <ProductImage>[];

    return Product(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      description: _nullableString(json['description']),
      barcode: _nullableString(json['barcode']),
      price: _double(json['price']),
      cost: _double(json['cost']),
      margin: _double(json['margin']),
      type: json['type'] as String? ?? ProductTypes.product,
      images: images,
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

  static double _double(dynamic value) {
    if (value is num) {
      return value.toDouble();
    }
    if (value is String) {
      return double.tryParse(value) ?? 0;
    }
    return 0;
  }

  static DateTime? _date(dynamic value) {
    if (value is String && value.isNotEmpty) {
      return DateTime.tryParse(value);
    }
    return null;
  }
}

/// Datos editables que devuelve el formulario al guardar.
class ProductFormData {
  const ProductFormData({
    required this.name,
    required this.price,
    required this.cost,
    required this.type,
    this.description,
    this.barcode,
  });

  final String name;
  final String? description;
  final String? barcode;
  final double price;
  final double cost;
  final String type;

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'description': description,
      'barcode': barcode,
      'price': price,
      'cost': cost,
      'type': type,
    };
  }

  /// Campos para `multipart/form-data` al crear un producto con fotos.
  Map<String, String> toFields() {
    return {
      'name': name,
      'description': description ?? '',
      'barcode': barcode ?? '',
      'price': price.toStringAsFixed(2),
      'cost': cost.toStringAsFixed(2),
      'type': type,
    };
  }
}
