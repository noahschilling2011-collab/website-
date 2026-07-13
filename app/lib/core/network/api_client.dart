import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

/// Thin typed HTTP client for the Nexus REST API.
/// Handles auth headers, JSON codec, error mapping and SSE streaming.
class ApiClient {
  ApiClient({required this.baseUrl, http.Client? client, this.onUnauthorized})
      : _http = client ?? http.Client();

  static const defaultBaseUrl =
      String.fromEnvironment('API_BASE_URL', defaultValue: 'http://localhost:8080');

  final String baseUrl;
  final http.Client _http;
  String? _accessToken;

  /// Called on a 401 response; returns a fresh access token (refresh flow)
  /// or null when the session is gone. The failed request is retried once.
  final Future<String?> Function()? onUnauthorized;

  set accessToken(String? token) => _accessToken = token;

  Map<String, String> get _headers => {
        'content-type': 'application/json',
        if (_accessToken != null) 'authorization': 'Bearer $_accessToken',
      };

  Future<Map<String, dynamic>> get(String path, {Map<String, String>? query}) =>
      _send('GET', path, query: query);

  Future<Map<String, dynamic>> post(String path, [Object? body]) => _send('POST', path, body: body);

  Future<Map<String, dynamic>> patch(String path, [Object? body]) => _send('PATCH', path, body: body);

  Future<void> delete(String path) async {
    await _send('DELETE', path);
  }

  Future<Map<String, dynamic>> _send(
    String method,
    String path, {
    Object? body,
    Map<String, String>? query,
    bool retried = false,
  }) async {
    final uri = Uri.parse('$baseUrl$path').replace(queryParameters: query);
    final request = http.Request(method, uri)..headers.addAll(_headers);
    if (body != null) request.body = jsonEncode(body);

    final streamed = await _http.send(request).timeout(const Duration(seconds: 60));
    final response = await http.Response.fromStream(streamed);

    // Expired access token: refresh once and replay the request.
    if (response.statusCode == 401 && !retried && onUnauthorized != null && !path.startsWith('/api/auth/')) {
      final fresh = await onUnauthorized!();
      if (fresh != null) {
        _accessToken = fresh;
        return _send(method, path, body: body, query: query, retried: true);
      }
    }

    if (response.statusCode == 204) return const {};
    final decoded = response.body.isEmpty ? const <String, dynamic>{} : jsonDecode(response.body);
    if (response.statusCode >= 400) {
      final error = (decoded is Map ? decoded['error'] : null) as Map<String, dynamic>?;
      throw ApiException(
        statusCode: response.statusCode,
        code: error?['code'] as String? ?? 'unknown',
        message: error?['message'] as String? ?? 'Request failed',
      );
    }
    return (decoded as Map).cast<String, dynamic>();
  }

  /// Multipart upload (files for OCR, PDF analysis, transcription, storage).
  Future<Map<String, dynamic>> postMultipart(
    String path, {
    required List<int> bytes,
    required String filename,
    Map<String, String>? fields,
  }) async {
    final request = http.MultipartRequest('POST', Uri.parse('$baseUrl$path'))
      ..headers.addAll({if (_accessToken != null) 'authorization': 'Bearer $_accessToken'})
      ..files.add(http.MultipartFile.fromBytes('file', bytes, filename: filename));
    if (fields != null) request.fields.addAll(fields);

    final response = await http.Response.fromStream(await _http.send(request));
    final decoded = response.body.isEmpty ? const <String, dynamic>{} : jsonDecode(response.body);
    if (response.statusCode >= 400) {
      final error = (decoded is Map ? decoded['error'] : null) as Map<String, dynamic>?;
      throw ApiException(
        statusCode: response.statusCode,
        code: error?['code'] as String? ?? 'upload_failed',
        message: error?['message'] as String? ?? 'Upload failed',
      );
    }
    return (decoded as Map).cast<String, dynamic>();
  }

  /// Streams SSE `data:` payloads from a POST endpoint (AI chat streaming).
  Stream<String> postSse(String path, Object body) async* {
    final request = http.Request('POST', Uri.parse('$baseUrl$path'))
      ..headers.addAll(_headers)
      ..body = jsonEncode(body);
    final response = await _http.send(request);
    if (response.statusCode >= 400) {
      throw ApiException(statusCode: response.statusCode, code: 'stream_failed', message: 'Stream failed');
    }
    var buffer = '';
    await for (final chunk in response.stream.transform(utf8.decoder)) {
      buffer += chunk;
      while (true) {
        final idx = buffer.indexOf('\n\n');
        if (idx == -1) break;
        final event = buffer.substring(0, idx);
        buffer = buffer.substring(idx + 2);
        for (final line in event.split('\n')) {
          if (line.startsWith('data:')) {
            final data = line.substring(5).trim();
            if (data == '[DONE]') return;
            yield data;
          }
        }
      }
    }
  }
}

class ApiException implements Exception {
  ApiException({required this.statusCode, required this.code, required this.message});

  final int statusCode;
  final String code;
  final String message;

  @override
  String toString() => 'ApiException($statusCode, $code): $message';
}
