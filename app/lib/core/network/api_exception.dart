/// Error de validación asociado a un campo del API.
class ApiFieldError {
  const ApiFieldError({required this.field, required this.message});

  final String field;
  final String message;

  factory ApiFieldError.fromJson(Map<String, dynamic> json) {
    return ApiFieldError(
      field: json['field'] as String? ?? '',
      message: json['message'] as String? ?? 'Valor inválido.',
    );
  }
}

/// Excepción normalizada del API.
class ApiException implements Exception {
  const ApiException({
    required this.code,
    required this.message,
    this.statusCode,
    this.details = const [],
  });

  final int? statusCode;
  final String code;
  final String message;
  final List<ApiFieldError> details;

  bool get isUnauthorized => statusCode == 401;
  bool get isForbidden => statusCode == 403;

  factory ApiException.network([String? message]) {
    return ApiException(
      code: 'network_error',
      message:
          message ??
          'No se pudo conectar con el servidor. Verifica que el API esté en línea e intenta de nuevo.',
    );
  }

  factory ApiException.fromResponse(int statusCode, dynamic body) {
    var code = 'http_error';
    var message = _defaultMessage(statusCode);
    var details = const <ApiFieldError>[];

    if (body is Map<String, dynamic>) {
      final error = body['error'];
      if (error is Map) {
        code = error['code'] as String? ?? code;
        message = error['message'] as String? ?? message;
        final rawDetails = error['details'];
        if (rawDetails is List) {
          details = rawDetails
              .whereType<Map>()
              .map(
                (item) =>
                    ApiFieldError.fromJson(Map<String, dynamic>.from(item)),
              )
              .toList(growable: false);
        }
      }
    }

    return ApiException(
      statusCode: statusCode,
      code: code,
      message: message,
      details: details,
    );
  }

  /// Mensaje más específico disponible (útil para errores de validación).
  String get displayMessage {
    if (details.isNotEmpty) {
      return details.first.message;
    }
    return message;
  }

  static String _defaultMessage(int statusCode) {
    return switch (statusCode) {
      400 => 'La solicitud no es válida.',
      401 => 'Tu sesión es inválida o expiró. Inicia sesión de nuevo.',
      403 => 'No tienes permisos para realizar esta acción.',
      404 => 'El recurso solicitado no existe.',
      409 => 'La operación entra en conflicto con datos existentes.',
      422 => 'Revisa los datos enviados.',
      >= 500 => 'Ocurrió un error en el servidor. Intenta de nuevo más tarde.',
      _ => 'Ocurrió un error inesperado.',
    };
  }

  @override
  String toString() => message;
}
