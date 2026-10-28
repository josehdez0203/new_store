import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../storage/token_storage.dart';
import 'api_exception.dart';

/// Respuesta normalizada del API: `data` más la metadata de paginación.
class ApiResult {
  const ApiResult({this.data, this.meta});

  final dynamic data;
  final Map<String, dynamic>? meta;

  List<Map<String, dynamic>> get asList {
    final value = data;
    if (value is List) {
      return value
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList(growable: false);
    }
    return const [];
  }

  Map<String, dynamic> get asMap {
    final value = data;
    if (value is Map<String, dynamic>) {
      return value;
    }
    if (value is Map) {
      return Map<String, dynamic>.from(value);
    }
    return const {};
  }
}

/// Cliente HTTP del API con renovación automática del access token.
class ApiClient {
  ApiClient({
    required String baseUrl,
    required this.storage,
    http.Client? client,
    this.timeout = const Duration(seconds: 20),
  }) : _baseUrl = baseUrl.endsWith('/')
           ? baseUrl.substring(0, baseUrl.length - 1)
           : baseUrl,
       _client = client ?? http.Client();

  final String _baseUrl;
  final TokenStorage storage;
  final http.Client _client;
  final Duration timeout;

  /// Se invoca cuando la sesión ya no puede renovarse.
  void Function()? onSessionExpired;

  Future<bool>? _refreshFuture;

  Future<ApiResult> get(String path, {Map<String, String>? query}) {
    return _request('GET', path, query: query);
  }

  Future<ApiResult> post(String path, {Object? body, bool auth = true}) {
    return _request('POST', path, body: body, auth: auth);
  }

  Future<ApiResult> patch(String path, {Object? body, bool auth = true}) {
    return _request('PATCH', path, body: body, auth: auth);
  }

  Future<ApiResult> put(String path, {Object? body, bool auth = true}) {
    return _request('PUT', path, body: body, auth: auth);
  }

  Future<void> delete(String path, {bool auth = true}) async {
    await _request('DELETE', path, auth: auth);
  }

  /// Sube un formulario multipart (por ejemplo, fotos de productos).
  Future<ApiResult> postMultipart(
    String path, {
    required Map<String, String> fields,
    required List<http.MultipartFile> files,
  }) {
    return _multipartRequest('POST', path, fields: fields, files: files);
  }

  /// Reemplaza un recurso mediante multipart.
  Future<ApiResult> putMultipart(
    String path, {
    Map<String, String> fields = const {},
    required List<http.MultipartFile> files,
  }) {
    return _multipartRequest('PUT', path, fields: fields, files: files);
  }

  /// Resuelve una ruta relativa del API (p. ej. /downloads/...) a URL absoluta.
  String resolveUrl(String path) {
    if (path.startsWith('http://') || path.startsWith('https://')) {
      return path;
    }
    final base = Uri.parse(_baseUrl);
    return base
        .replace(path: path.startsWith('/') ? path : '/$path')
        .toString();
  }

  void dispose() {
    _client.close();
  }

  Future<ApiResult> _request(
    String method,
    String path, {
    Object? body,
    Map<String, String>? query,
    bool auth = true,
    bool retry = true,
  }) async {
    final uri = _uri(path, query);
    final headers = <String, String>{'Accept': 'application/json'};

    if (body != null) {
      headers['Content-Type'] = 'application/json';
    }

    if (auth) {
      final token = storage.accessToken;
      if (token != null && token.isNotEmpty) {
        headers['Authorization'] = 'Bearer $token';
      }
    }

    http.Response response;
    try {
      final request = http.Request(method, uri)..headers.addAll(headers);
      if (body != null) {
        request.body = jsonEncode(body);
      }
      final streamed = await _client.send(request).timeout(timeout);
      response = await http.Response.fromStream(streamed).timeout(timeout);
    } on TimeoutException {
      throw ApiException.network(
        'El servidor tardó demasiado en responder. Intenta de nuevo.',
      );
    } on http.ClientException {
      throw ApiException.network();
    } catch (_) {
      throw ApiException.network();
    }

    if (response.statusCode == 401 && auth) {
      if (retry && storage.refreshToken != null) {
        final refreshed = await _refreshTokens();
        if (refreshed) {
          return _request(
            method,
            path,
            body: body,
            query: query,
            auth: auth,
            retry: false,
          );
        }
      } else if (!retry) {
        await _clearSession();
      }
    }

    return _parse(response);
  }

  Future<ApiResult> _multipartRequest(
    String method,
    String path, {
    required Map<String, String> fields,
    required List<http.MultipartFile> files,
  }) async {
    final uri = _uri(path, null);
    final request = http.MultipartRequest(method, uri);
    request.headers['Accept'] = 'application/json';

    final token = storage.accessToken;
    if (token != null && token.isNotEmpty) {
      request.headers['Authorization'] = 'Bearer $token';
    }
    request.fields.addAll(fields);
    request.files.addAll(files);

    http.Response response;
    try {
      final streamed = await _client
          .send(request)
          .timeout(const Duration(minutes: 2));
      response = await http.Response.fromStream(
        streamed,
      ).timeout(const Duration(minutes: 2));
    } on TimeoutException {
      throw ApiException.network(
        'La carga tardó demasiado. Intenta de nuevo con fotos más pequeñas.',
      );
    } on http.ClientException {
      throw ApiException.network();
    } catch (_) {
      throw ApiException.network();
    }

    if (response.statusCode == 401 && storage.refreshToken != null) {
      final refreshed = await _refreshTokens();
      if (refreshed) {
        // Los archivos multipart ya se consumieron; no se pueden reenviar.
        throw const ApiException(
          code: 'retry_upload',
          message: 'La sesión se renovó. Vuelve a intentar la carga de fotos.',
        );
      }
      await _clearSession();
    }

    return _parse(response);
  }

  Future<bool> _refreshTokens() {
    final pending = _refreshFuture;
    if (pending != null) {
      return pending;
    }

    final future = _performRefresh();
    _refreshFuture = future;
    return future.whenComplete(() {
      if (identical(_refreshFuture, future)) {
        _refreshFuture = null;
      }
    });
  }

  Future<bool> _performRefresh() async {
    final refreshToken = storage.refreshToken;
    if (refreshToken == null || refreshToken.isEmpty) {
      return false;
    }

    try {
      final result = await _request(
        'POST',
        '/auth/refresh',
        body: {'refresh_token': refreshToken},
        auth: false,
        retry: false,
      );
      final data = result.asMap;
      final accessToken = data['access_token'] as String?;
      final newRefreshToken = data['refresh_token'] as String?;
      if (accessToken == null || newRefreshToken == null) {
        await _clearSession();
        return false;
      }
      await storage.saveTokens(
        accessToken: accessToken,
        refreshToken: newRefreshToken,
      );
      return true;
    } on ApiException {
      await _clearSession();
      return false;
    }
  }

  Future<void> _clearSession() async {
    await storage.clear();
    onSessionExpired?.call();
  }

  ApiResult _parse(http.Response response) {
    final statusCode = response.statusCode;
    dynamic decoded;

    if (response.bodyBytes.isNotEmpty) {
      try {
        decoded = jsonDecode(utf8.decode(response.bodyBytes));
      } catch (_) {
        decoded = null;
      }
    }

    if (statusCode >= 200 && statusCode < 300) {
      if (decoded is Map<String, dynamic>) {
        final meta = decoded['meta'];
        return ApiResult(
          data: decoded.containsKey('data') ? decoded['data'] : decoded,
          meta: meta is Map<String, dynamic> ? meta : null,
        );
      }
      return ApiResult(data: decoded);
    }

    throw ApiException.fromResponse(statusCode, decoded);
  }

  Uri _uri(String path, Map<String, String>? query) {
    final uri = Uri.parse('$_baseUrl$path');
    if (query == null || query.isEmpty) {
      return uri;
    }
    return uri.replace(queryParameters: {...uri.queryParameters, ...query});
  }
}
