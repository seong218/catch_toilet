import 'dart:async';

import 'package:catchy_toilet/models/recommendation.dart';
import 'package:catchy_toilet/models/restroom.dart';
import 'package:catchy_toilet/models/stall_update.dart';
import 'package:catchy_toilet/repositories/mock_restroom_repository.dart';
import 'package:catchy_toilet/repositories/restroom_repository.dart';
import 'package:catchy_toilet/services/location_service.dart';
import 'package:catchy_toilet/state/app_controller.dart';
import 'package:flutter_test/flutter_test.dart';

class ControlledRepository extends MockRestroomRepository {
  final requests = <({bool bidet, Completer<Recommendation> response})>[];
  bool listFails = false;

  @override
  Future<Recommendation> getRecommendation(
    UserLocation location, {
    required bool bidetRequired,
    String? gender,
  }) {
    final response = Completer<Recommendation>();
    requests.add((bidet: bidetRequired, response: response));
    return response.future;
  }

  @override
  Future<List<Restroom>> getRestrooms(UserLocation location, {String? gender}) {
    if (listFails) {
      throw const RepositoryException('서버에 연결할 수 없습니다.');
    }
    return super.getRestrooms(location);
  }
}

Recommendation response(int index) => Recommendation(
  restroom: MockRestroomRepository.fixtures[index],
  statisticsUsed: false,
);

class OverlappingRepository extends MockRestroomRepository {
  final events = StreamController<StallUpdate>.broadcast(sync: true);
  Restroom first = MockRestroomRepository.fixtures.first;
  Completer<List<Restroom>>? heldList;
  Completer<Restroom>? heldDetail;
  final listStarted = Completer<void>();
  int detailCalls = 0;
  @override
  Future<Recommendation> getRecommendation(
    UserLocation location, {
    required bool bidetRequired,
    String? gender,
  }) async => response(1);
  @override
  Stream<StallUpdate> get updates => events.stream;
  @override
  Future<List<Restroom>> getRestrooms(
    UserLocation location, {
    String? gender,
  }) async {
    if (heldList != null) {
      final pending = heldList!;
      heldList = null;
      listStarted.complete();
      return pending.future;
    }
    return [first, ...MockRestroomRepository.fixtures.skip(1)];
  }

  @override
  Future<Restroom> getDetail(int id, UserLocation location) async {
    detailCalls++;
    if (heldDetail != null) {
      final pending = heldDetail!;
      heldDetail = null;
      return pending.future;
    }
    return id == 1 ? first : await super.getDetail(id, location);
  }

  void occupyLastStall() {
    const event = StallUpdate(
      restroomId: 1,
      stallId: 2,
      occupied: true,
      totalStalls: 3,
      availableStalls: 0,
      availableBidetStalls: 0,
    );
    first = first.apply(event);
    events.add(event);
  }

  @override
  void dispose() {
    unawaited(events.close());
  }
}

void main() {
  test(
    'REST list overlapping an event cannot roll back current counts',
    () async {
      final repository = OverlappingRepository();
      final controller = AppController(
        repository,
        locationService: selectedLocation(),
        eventDelay: const Duration(milliseconds: 10),
      );
      addTearDown(controller.dispose);
      await controller.start();
      final pending = Completer<List<Restroom>>();
      repository.heldList = pending;
      final refreshing = controller.refresh();
      await repository.listStarted.future;
      repository.occupyLastStall();
      pending.complete(MockRestroomRepository.fixtures);
      await refreshing;
      expect(controller.restrooms.first.availableStalls, 0);
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(repository.detailCalls, 1);
      expect(controller.details[1]!.availableStalls, 0);
    },
  );

  test(
    'detail response overlapped by an event is refetched, not replayed',
    () async {
      final repository = OverlappingRepository();
      final controller = AppController(
        repository,
        locationService: selectedLocation(),
        eventDelay: const Duration(milliseconds: 10),
      );
      addTearDown(controller.dispose);
      await controller.start();
      final pending = Completer<Restroom>();
      repository.heldDetail = pending;
      final loading = controller.openDetail(1);
      repository.occupyLastStall();
      pending.complete(MockRestroomRepository.fixtures.first);
      await loading;
      expect(controller.details[1], isNull);
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(repository.detailCalls, 2);
      expect(controller.details[1]!.availableStalls, 0);
    },
  );
  test('mock initial load and bidet option return scripted results', () async {
    final controller = AppController(
      MockRestroomRepository(),
      locationService: selectedLocation(),
    );
    addTearDown(controller.dispose);
    await controller.refresh();
    expect(controller.restrooms.length, 3);
    expect(controller.recommendation!.restroom.id, 1);
    expect(controller.backendOnline, isFalse);
    await controller.setBidetRequired(true);
    expect(controller.recommendation!.restroom.id, 2);
    expect(controller.recommendation!.restroom.availableBidetStalls, 1);
  });

  test(
    'late old-option response cannot overwrite the current choice',
    () async {
      final repository = ControlledRepository();
      final controller = AppController(
        repository,
        locationService: selectedLocation(),
      );
      addTearDown(controller.dispose);
      final original = controller.refreshRecommendation();
      final changed = controller.setBidetRequired(true);
      expect(repository.requests.map((r) => r.bidet), [false, true]);
      repository.requests[1].response.complete(response(1));
      await changed;
      repository.requests[0].response.complete(response(0));
      await original;
      expect(controller.recommendation!.restroom.id, 2);
      expect(controller.bidetRequired, isTrue);
    },
  );

  test('recommendation 404 keeps list and bidet preference', () async {
    final repository = ControlledRepository();
    final controller = AppController(
      repository,
      locationService: selectedLocation(),
    );
    addTearDown(controller.dispose);
    final initial = controller.refresh();
    repository.requests.last.response.complete(response(0));
    await initial;
    final changed = controller.setBidetRequired(true);
    repository.requests.last.response.completeError(
      const RepositoryException(
        'Not found',
        statusCode: 404,
        detail: 'No available bidet stalls',
      ),
    );
    await changed;
    expect(controller.bidetRequired, isTrue);
    expect(controller.restrooms.length, 3);
    expect(controller.recommendation, isNull);
    expect(controller.recommendationEmpty, contains('비데'));
    expect(controller.recommendationError, isNull);
  });

  test('failed refresh retains list and a later retry recovers', () async {
    final repository = ControlledRepository();
    final controller = AppController(
      repository,
      locationService: selectedLocation(),
    );
    addTearDown(controller.dispose);
    final initial = controller.refresh();
    repository.requests.last.response.complete(response(0));
    await initial;
    repository.listFails = true;
    final failure = controller.refresh();
    repository.requests.last.response.completeError(
      const RepositoryException('서버에 연결할 수 없습니다.'),
    );
    await failure;
    expect(controller.restrooms.length, 3);
    expect(controller.listError, isNotNull);
    expect(controller.loading, isFalse);
    repository.listFails = false;
    final retry = controller.refresh();
    repository.requests.last.response.complete(response(0));
    await retry;
    expect(controller.listError, isNull);
    expect(controller.recommendationError, isNull);
  });

  test('changing origin invalidates detail and updates distances', () async {
    final controller = AppController(
      MockRestroomRepository(),
      locationService: selectedLocation(),
    );
    addTearDown(controller.dispose);
    await controller.refresh();
    await controller.loadDetail(1);
    expect(controller.details[1]!.distance, isPositive);
    await controller.setLocation(
      const UserLocation(label: '테스트 GPS', longitude: 30, latitude: 20),
    );
    expect(controller.details, isEmpty);
    expect(controller.restrooms.first.distance, 0);
  });

  test('completing a request after disposal is safe', () async {
    final repository = ControlledRepository();
    final controller = AppController(
      repository,
      locationService: selectedLocation(),
    );
    final pending = controller.refreshRecommendation();
    controller.dispose();
    repository.requests.single.response.complete(response(0));
    await pending;
  });
}

// These tests exercise refreshes after the user has confirmed a location.
LocationService selectedLocation() => LocationService()
  ..setLocation(
    const UserLocation(label: '테스트 기준 위치', latitude: 37.35, longitude: 126.84),
  );
