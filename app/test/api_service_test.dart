import 'dart:async';
import 'dart:convert';

import 'package:catchy_toilet/repositories/api_restroom_repository.dart';
import 'package:catchy_toilet/repositories/restroom_repository.dart';
import 'package:catchy_toilet/services/api_service.dart';
import 'package:catchy_toilet/services/location_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'models_test.dart' show restroomJson, detailJson;

const location = UserLocation(label: '기준', longitude: -10, latitude: 20);

void main() {
  test(
    'REST contract paths, query booleans, UTF-8 and nullable statistics',
    () async {
      final paths = <String>[];
      final repository = ApiRestroomRepository(
        ApiService(
          'https://example.test',
          client: MockClient((request) async {
            paths.add(request.url.path);
            if (request.url.path == '/api/health') {
              return http.Response('{"status":"ok"}', 200);
            }
            expect(request.url.queryParameters['longitude'], '-10.0');
            expect(request.url.queryParameters['latitude'], '20.0');
            Object body;
            if (request.url.path.endsWith('/recommend')) {
              expect(request.url.queryParameters['bidet_required'], 'true');
              body = {
                ...restroomJson(),
                'distance': 42,
                'statistics_used': true,
                'historical_availability_rate': null,
                'historical_bidet_availability_rate': 0.82,
              };
            } else if (request.url.path.endsWith('/1')) {
              body = detailJson();
            } else {
              body = [restroomJson()];
            }
            return http.Response.bytes(utf8.encode(jsonEncode(body)), 200);
          }),
        ),
      );
      addTearDown(repository.dispose);
      await repository.checkHealth();
      expect((await repository.getRestrooms(location)).single.name, '본관 1층');
      expect((await repository.getDetail(1, location)).stalls!.length, 3);
      final result = await repository.getRecommendation(
        location,
        bidetRequired: true,
      );
      expect(result.statisticsUsed, isTrue);
      expect(result.historicalBidetAvailabilityRate, 0.82);
      expect(paths, [
        '/api/health',
        '/api/restrooms',
        '/api/restrooms/1',
        '/api/restrooms/recommend',
      ]);
      expect(repository.api.websocketUri.toString(), 'wss://example.test/ws');
    },
  );

  test('404 reason remains distinguishable from offline failure', () async {
    final api = ApiService(
      'http://example.test',
      client: MockClient(
        (_) async =>
            http.Response('{"detail":"No available bidet stalls"}', 404),
      ),
    );
    addTearDown(api.dispose);
    await expectLater(
      api.get('/api/restrooms/recommend', (v) => v),
      throwsA(
        isA<RepositoryException>()
            .having((e) => e.statusCode, 'status', 404)
            .having((e) => e.detail, 'reason', 'No available bidet stalls'),
      ),
    );
  });

  test('bad JSON and wrong field types become recoverable errors', () async {
    for (final body in [
      'not json',
      jsonEncode({...restroomJson(), 'id': '1'}),
    ]) {
      final api = ApiService(
        'http://example.test',
        client: MockClient(
          (_) async => http.Response.bytes(utf8.encode(body), 200),
        ),
      );
      final repository = ApiRestroomRepository(api);
      await expectLater(
        repository.getDetail(1, location),
        throwsA(isA<RepositoryException>()),
      );
      repository.dispose();
    }
  });

  test('timeouts and non-JSON gateway errors do not crash', () async {
    final timeout = ApiService(
      'http://example.test',
      timeout: const Duration(milliseconds: 10),
      client: MockClient((_) async {
        throw TimeoutException('test');
      }),
    );
    addTearDown(timeout.dispose);
    await expectLater(
      timeout.get('/api/health', (v) => v),
      throwsA(isA<RepositoryException>()),
    );
    final unavailable = ApiService(
      'http://example.test',
      client: MockClient(
        (_) async => http.Response('<html>offline</html>', 503),
      ),
    );
    addTearDown(unavailable.dispose);
    await expectLater(
      unavailable.get('/api/health', (v) => v),
      throwsA(
        isA<RepositoryException>().having((e) => e.statusCode, 'status', 503),
      ),
    );
  });

  test('invalid server URLs are rejected before starting a connection', () {
    for (final value in [
      'localhost:8000',
      'file:///test',
      'https://',
      'https://u:p@host',
    ]) {
      expect(() => ApiService.parseBaseUrl(value), throwsFormatException);
    }
  });
}
