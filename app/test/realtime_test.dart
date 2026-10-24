import 'dart:convert';
import 'dart:io';

import 'package:catchy_toilet/repositories/api_restroom_repository.dart';
import 'package:catchy_toilet/services/api_service.dart';
import 'package:catchy_toilet/services/websocket_service.dart';
import 'package:catchy_toilet/state/app_controller.dart';
import 'package:flutter_test/flutter_test.dart';

// In-process contract fixture only, bound to loopback. Not the project Backend.
class ContractServer {
  late HttpServer server;
  final sockets = <WebSocket>[];
  bool firstOccupied = false;
  bool noBidet = false;
  bool rejectSocket = false;
  int listCalls = 0;
  int detailCalls = 0;
  int recommendationCalls = 0;
  int connections = 0;
  Uri get base => Uri.parse('http://127.0.0.1:${server.port}');
  Uri get ws => base.replace(scheme: 'ws', path: '/ws');

  Map<String, Object?> room(int id, {bool detail = false}) => {
    'id': id,
    'name': '화장실 $id',
    'building': '테스트',
    'floor': id,
    'x': id * 20,
    'y': 20,
    'distance': id * 20,
    'total_stalls': 1,
    'available_stalls': id == 1 && firstOccupied ? 0 : 1,
    'available_bidet_stalls': id == 2 && !noBidet ? 1 : 0,
    if (detail)
      'stalls': [
        {
          'id': id * 10,
          'stall_number': 1,
          'occupied': id == 1 && firstOccupied,
          'has_bidet': id == 2 && !noBidet,
        },
      ],
  };

  Map<String, Object?> event() => {
    'type': 'stall.updated',
    'restroom_id': 1,
    'stall_id': 10,
    'occupied': firstOccupied,
    'total_stalls': 1,
    'available_stalls': firstOccupied ? 0 : 1,
    'available_bidet_stalls': 0,
  };

  Future<void> start() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      if (request.uri.path == '/ws' && !rejectSocket) {
        final socket = await WebSocketTransformer.upgrade(request);
        sockets.add(socket);
        connections++;
        socket.listen(
          (_) {},
          onDone: () => sockets.remove(socket),
          onError: (Object _) => sockets.remove(socket),
        );
        return;
      }
      Object body;
      switch (request.uri.path) {
        case '/api/health':
          body = {'status': 'ok'};
        case '/api/restrooms':
          listCalls++;
          body = [room(1), room(2)];
        case '/api/restrooms/1':
          detailCalls++;
          body = room(1, detail: true);
        case '/api/restrooms/2':
          detailCalls++;
          body = room(2, detail: true);
        case '/api/restrooms/recommend':
          recommendationCalls++;
          if (request.uri.queryParameters['bidet_required'] == 'true' &&
              noBidet) {
            request.response.statusCode = 404;
            body = {'detail': 'No available bidet stalls'};
          } else {
            final id =
                request.uri.queryParameters['bidet_required'] == 'true' ||
                    firstOccupied
                ? 2
                : 1;
            body = {
              ...room(id),
              'statistics_used': false,
              'historical_availability_rate': null,
              'historical_bidet_availability_rate': null,
            };
          }
        default:
          request.response.statusCode = 503;
          body = {'detail': 'Database unavailable'};
      }
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode(body));
      await request.response.close();
    });
  }

  void send(Object value) {
    for (final socket in sockets.toList()) {
      socket.add(jsonEncode(value));
    }
  }

  Future<void> closeSockets() async {
    for (final socket in sockets.toList()) {
      await socket.close(1000);
    }
  }

  Future<void> close() async {
    await closeSockets();
    await server.close(force: true);
  }
}

Future<void> until(bool Function() ready) async {
  final deadline = DateTime.now().add(const Duration(seconds: 5));
  while (!ready()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('Timed out waiting for expected state');
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

void main() {
  late ContractServer server;
  late AppController controller;
  setUp(() async {
    server = ContractServer();
    await server.start();
    final api = ApiService(server.base.toString());
    controller = AppController(
      ApiRestroomRepository(
        api,
        websocket: WebsocketService(
          server.ws,
          retryDelay: const Duration(milliseconds: 30),
          connectionTimeout: const Duration(milliseconds: 300),
        ),
      ),
      eventDelay: const Duration(milliseconds: 30),
    );
  });
  tearDown(() async {
    controller.dispose();
    await server.close();
  });

  test(
    'real HTTP + WebSocket update detail/counts and re-request recommendation',
    () async {
      await controller.start();
      await controller.openDetail(1);
      expect(controller.recommendation!.restroom.id, 1);
      final initialListCalls = server.listCalls;
      final initialRecommendations = server.recommendationCalls;
      server.firstOccupied = true;
      server.send(server.event());
      server.send(server.event());
      await until(() => controller.restrooms.first.availableStalls == 0);
      expect(controller.details[1]!.stalls!.single.occupied, isTrue);
      await until(() => controller.recommendation?.restroom.id == 2);
      expect(server.listCalls, initialListCalls);
      expect(server.recommendationCalls, initialRecommendations + 1);
      // Freeing another restroom must also trigger Backend reconsideration.
      server.firstOccupied = false;
      server.send(server.event());
      await until(() => controller.recommendation?.restroom.id == 1);
      expect(server.listCalls, initialListCalls);
    },
  );

  test(
    '404 does not stop events, and restored bidet availability is recommended',
    () async {
      await controller.start();
      server.noBidet = true;
      await controller.setBidetRequired(true);
      expect(controller.recommendation, isNull);
      expect(controller.recommendationEmpty, contains('비데'));
      server.noBidet = false;
      server.firstOccupied = true;
      server.send(server.event());
      await until(() => controller.recommendation?.restroom.id == 2);
      expect(controller.bidetRequired, isTrue);
    },
  );

  test('reconnect restores list and open detail after missed events', () async {
    await controller.start();
    await controller.openDetail(1);
    server.firstOccupied =
        true; // No event: emulate a change during disconnection.
    final initialLists = server.listCalls;
    await server.closeSockets();
    await until(
      () =>
          server.connections >= 2 &&
          server.listCalls > initialLists &&
          controller.details[1]!.stalls!.single.occupied &&
          controller.isRealtime,
    );
    expect(controller.recommendation!.restroom.id, 2);
  });

  test('handshake failure still loads REST and later reconnects', () async {
    server.rejectSocket = true;
    await controller.start();
    expect(controller.restrooms.length, 2);
    expect(controller.isRealtime, isFalse);
    server.rejectSocket = false;
    await until(() => controller.isRealtime);
  });

  test(
    'unknown types are ignored, malformed known events reconnect safely',
    () async {
      await controller.start();
      server.send({'type': 'future.event'});
      server.send({'type': 'stall.updated', 'occupied': 'bad'});
      await until(() => server.connections >= 2 && controller.isRealtime);
      expect(controller.restrooms.first.availableStalls, 1);
    },
  );

  test('unknown stall refreshes only its restroom detail', () async {
    await controller.start();
    await controller.openDetail(1);
    final lists = server.listCalls;
    final details = server.detailCalls;
    server.send({...server.event(), 'stall_id': 999});
    await until(
      () =>
          server.detailCalls > details &&
          !controller.loadingDetails.contains(1),
    );
    expect(server.listCalls, lists);
    expect(controller.details[1]!.stalls!.single.id, 10);
  });

  test(
    'foreground resume reopens socket and refreshes current state',
    () async {
      await controller.start();
      controller.suspend();
      server.firstOccupied = true;
      await controller.resume();
      expect(controller.restrooms.first.availableStalls, 0);
      expect(controller.recommendation!.restroom.id, 2);
    },
  );
}
