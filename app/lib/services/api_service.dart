import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../repositories/restroom_repository.dart';

class ApiService {
  ApiService(
    String baseUrl, {
    http.Client? client,
    this.timeout = const Duration(seconds: 8),
  }) : baseUri = parseBaseUrl(baseUrl),
       _client = client ?? http.Client();

  final Uri baseUri;
  final http.Client _client;
  final Duration timeout;

  static Uri parseBaseUrl(String value) {
    final uri = Uri.tryParse(value);
    if (uri == null ||
        !['http', 'https'].contains(uri.scheme) ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment) {
      throw const FormatException(
        'API_BASE_URL must be an HTTP(S) server URL.',
      );
    }
    return uri;
  }

  Uri uri(String path, [Map<String, String>? query]) => baseUri.replace(
    path: '${baseUri.path.replaceFirst(RegExp(r'/+$'), '')}$path',
    queryParameters: query,
  );

  Uri get websocketUri =>
      uri('/ws').replace(scheme: baseUri.scheme == 'https' ? 'wss' : 'ws');

  Future<T> get<T>(
    String path,
    T Function(Object?) decode, {
    Map<String, String>? query,
  }) async {
    try {
      final response = await _client
          .get(uri(path, query), headers: {'Accept': 'application/json'})
          .timeout(timeout);
      if (response.statusCode != 200) {
        String? detail;
        try {
          final body = jsonDecode(utf8.decode(response.bodyBytes));
          if (body is Map<String, dynamic> && body['detail'] is String) {
            detail = body['detail'] as String;
          }
        } on FormatException {
          // Proxies can send a non-JSON error page; keep a usable error message.
        }
        throw RepositoryException(
          switch (response.statusCode) {
            404 => '요청한 화장실 정보를 찾을 수 없습니다.',
            422 => '위치 또는 요청 정보를 확인해 주세요.',
            503 => '서버가 잠시 응답하지 않습니다. 다시 시도해 주세요.',
            _ => '정보를 불러올 수 없습니다. 다시 시도해 주세요.',
          },
          statusCode: response.statusCode,
          detail: detail,
        );
      }
      return decode(jsonDecode(utf8.decode(response.bodyBytes)));
    } on TimeoutException {
      throw const RepositoryException('서버 응답이 늦어지고 있습니다. 다시 시도해 주세요.');
    } on http.ClientException {
      throw const RepositoryException('서버에 연결할 수 없습니다. 네트워크를 확인해 주세요.');
    } on FormatException {
      throw const RepositoryException('서버에서 올바르지 않은 정보를 받았습니다. 다시 시도해 주세요.');
    }
  }

  void dispose() => _client.close();
}
