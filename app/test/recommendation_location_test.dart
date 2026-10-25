import 'dart:async';

import 'package:catch_toilet/models/recommendation.dart';
import 'package:catch_toilet/models/stall_update.dart';
import 'package:catch_toilet/repositories/mock_restroom_repository.dart';
import 'package:catch_toilet/services/location_service.dart';
import 'package:catch_toilet/state/app_controller.dart';
import 'package:flutter_test/flutter_test.dart';

const gps = UserLocation(
  label: '현재 GPS 위치',
  latitude: 37.35,
  longitude: 126.84,
  isGps: true,
);
const movedGps = UserLocation(
  label: '현재 GPS 위치',
  latitude: 37.36,
  longitude: 126.85,
  isGps: true,
);
const manual = UserLocation(
  label: '디미고 본관 기준',
  latitude: dimigoLatitude,
  longitude: dimigoLongitude,
);

void main() {
  test(
    'startup, preferences and sensor events never recommend from an unconfirmed origin',
    () async {
      var reads = 0;
      final pendingGps = Completer<UserLocation>();
      final repository = LocationRepository();
      final controller = AppController(
        repository,
        eventDelay: Duration.zero,
        locationService: LocationService(
          gpsReader: (_) {
            reads++;
            return pendingGps.future;
          },
        ),
      );
      addTearDown(controller.dispose);
      await controller.start();
      await controller.setGender('female');
      await controller.setBidetRequired(true);
      repository.emit();
      await Future<void>.delayed(const Duration(milliseconds: 5));
      expect(controller.hasSelectedLocation, isFalse);
      expect(repository.origins, isEmpty);
      expect(reads, 0);
      final requesting = controller.requestRecommendation();
      await controller.requestRecommendation();
      await controller.refresh();
      expect(controller.recommendationLocating, isTrue);
      expect(repository.origins, isEmpty);
      expect(reads, 1);
      pendingGps.complete(gps);
      await requesting;
      expect(repository.origins, [gps]);
      expect(repository.lastGender, 'female');
      expect(repository.lastBidet, isTrue);
      await controller.refreshRecommendation();
      expect(reads, 1); // Automatic refreshes reuse confirmed GPS.
    },
  );

  for (final failure in [
    const LocationFailure('권한 거부', openSettings: true),
    const LocationFailure('위치 서비스 꺼짐', openSettings: true),
    const LocationFailure('GPS 시간 초과'),
  ]) {
    test(
      '${failure.message} never falls back to a previous GPS or campus point',
      () async {
        var reads = 0;
        final repository = LocationRepository();
        final controller = AppController(
          repository,
          eventDelay: Duration.zero,
          locationService: LocationService(
            gpsReader: (_) async {
              reads++;
              if (reads == 2) throw failure;
              return reads == 1 ? gps : movedGps;
            },
          ),
        );
        addTearDown(controller.dispose);
        await controller.start();
        await controller.requestRecommendation();
        expect(repository.origins, [gps]);
        await controller.requestRecommendation();
        expect(controller.recommendationLocationError, same(failure));
        expect(controller.recommendation, isNull);
        await controller.setGender('female');
        await controller.setBidetRequired(true);
        repository.emit();
        await Future<void>.delayed(const Duration(milliseconds: 5));
        expect(repository.origins, [gps]);
        await controller.requestRecommendation();
        expect(repository.origins, [gps, movedGps]);
        expect(controller.recommendationLocationError, isNull);
      },
    );
  }

  test(
    'late GPS cannot replace an explicitly selected manual location',
    () async {
      final pendingGps = Completer<UserLocation>();
      final repository = LocationRepository();
      final controller = AppController(
        repository,
        locationService: LocationService(gpsReader: (_) => pendingGps.future),
      );
      addTearDown(controller.dispose);
      final requesting = controller.requestRecommendation();
      await controller.setLocation(manual);
      pendingGps.complete(gps);
      await requesting;
      expect(controller.location, same(manual));
      expect(repository.origins, [manual]);
      await controller.requestRecommendation();
      expect(repository.origins, [manual, manual]);
    },
  );

  test(
    'old recommendation cannot appear while the new GPS is pending',
    () async {
      final pendingGps = Completer<UserLocation>();
      final service = LocationService(gpsReader: (_) => pendingGps.future)
        ..setLocation(gps);
      final repository = LocationRepository();
      final controller = AppController(repository, locationService: service);
      addTearDown(controller.dispose);
      final pendingResponse = Completer<Recommendation>();
      repository.pending = pendingResponse;
      final old = controller.refreshRecommendation();
      final requesting = controller.requestRecommendation();
      pendingResponse.complete(
        Recommendation(
          restroom: MockRestroomRepository.fixtures.first,
          statisticsUsed: false,
        ),
      );
      await old;
      expect(controller.recommendation, isNull);
      expect(controller.recommendationLocating, isTrue);
      pendingGps.complete(movedGps);
      await requesting;
      expect(controller.location, same(movedGps));
      expect(repository.origins, [gps, movedGps]);
      expect(controller.recommendation, isNotNull);
    },
  );

  test('GPS completed after disposal does not send a recommendation', () async {
    final pendingGps = Completer<UserLocation>();
    final repository = LocationRepository();
    final controller = AppController(
      repository,
      locationService: LocationService(gpsReader: (_) => pendingGps.future),
    );
    final requesting = controller.requestRecommendation();
    controller.dispose();
    pendingGps.complete(gps);
    await requesting;
    expect(repository.origins, isEmpty);
  });
}

class LocationRepository extends MockRestroomRepository {
  final origins = <UserLocation>[];
  final events = StreamController<StallUpdate>.broadcast(sync: true);
  String? lastGender;
  bool? lastBidet;
  Completer<Recommendation>? pending;
  @override
  Stream<StallUpdate> get updates => events.stream;

  void emit() => events.add(
    const StallUpdate(
      restroomId: 1,
      stallId: 2,
      occupied: true,
      totalStalls: 3,
      availableStalls: 0,
      availableBidetStalls: 0,
    ),
  );

  @override
  Future<Recommendation> getRecommendation(
    UserLocation location, {
    required bool bidetRequired,
    String? gender,
  }) async {
    origins.add(location);
    lastGender = gender;
    lastBidet = bidetRequired;
    final held = pending;
    pending = null;
    return held == null
        ? Recommendation(
            restroom: MockRestroomRepository.fixtures.first,
            statisticsUsed: false,
          )
        : await held.future;
  }

  @override
  void dispose() {
    unawaited(events.close());
    super.dispose();
  }
}
