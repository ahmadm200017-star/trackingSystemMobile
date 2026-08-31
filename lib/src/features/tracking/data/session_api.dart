import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../../../core/config/app_config.dart';
import '../../../core/network/api_exception.dart';
import '../domain/session_dtos.dart';

final httpClientProvider = Provider<http.Client>((ref) {
  final client = http.Client();
  ref.onDispose(client.close);
  return client;
});

final sessionApiProvider = Provider<SessionApi>(
  (ref) => SessionApi(
    client: ref.watch(httpClientProvider),
    config: ref.watch(appConfigProvider),
  ),
);

/// REST half of the backend contract: session lifecycle plus the fallback path
/// for frames that could not be streamed.
class SessionApi {
  SessionApi({
    required http.Client client,
    required AppConfig config,
    this.timeout = const Duration(seconds: 10),
  })  : _client = client,
        _config = config;

  final http.Client _client;
  final AppConfig _config;
  final Duration timeout;

  static const _jsonHeaders = {'Content-Type': 'application/json'};

  Future<SessionSummary> startSession(StartSessionRequest request) async {
    final body = await _send('POST', '/api/sessions', request.toJson());
    if (body is! Map<String, dynamic>) {
      throw ApiException('Malformed session payload', uri: _config.rest('/api/sessions'));
    }
    return SessionSummary.fromJson(body);
  }

  Future<void> completeSession(String sessionId, CompleteSessionRequest request) =>
      _send('POST', '/api/sessions/$sessionId/end', request.toJson());

  /// Uploads the first-frame crop and returns the description Groq produced.
  ///
  /// The round trip includes a model call, so it gets a longer deadline than the
  /// lifecycle calls above.
  Future<String?> describeObject(String sessionId, DescribeObjectRequest request) async {
    final body = await _send(
      'POST',
      '/api/sessions/$sessionId/description',
      request.toJson(),
      // Must exceed the server's own Groq deadline (Groq:TimeoutSeconds, 30s).
      timeout: const Duration(seconds: 45),
    );
    if (body is! Map<String, dynamic>) return null;
    return body['objectDescription'] as String?;
  }

  // There is no REST ingest path: frames and lifecycle events only reach the
  // backend over the tracking socket. `/api/sessions/{id}/frames` and `/events`
  // are read-only (GET) and belong to the dashboard.

  Future<Object?> _send(
    String method,
    String path,
    Map<String, dynamic> body, {
    Duration? timeout,
  }) async {
    final uri = _config.rest(path);
    final deadline = timeout ?? this.timeout;
    try {
      final request = http.Request(method, uri)
        ..headers.addAll(_jsonHeaders)
        ..body = jsonEncode(body);

      final streamed = await _client.send(request).timeout(deadline);
      final response = await http.Response.fromStream(streamed);

      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw ApiException(
          response.body.isEmpty ? response.reasonPhrase ?? 'Request failed' : response.body,
          statusCode: response.statusCode,
          uri: uri,
        );
      }

      if (response.body.isEmpty) return null;
      return jsonDecode(response.body) as Object?;
    } on ApiException {
      rethrow;
    } on TimeoutException {
      throw ApiException('Request timed out after ${deadline.inSeconds}s', uri: uri);
    } catch (error) {
      throw ApiException('$error', uri: uri);
    }
  }
}
