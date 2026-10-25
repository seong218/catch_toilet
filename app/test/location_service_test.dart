import 'dart:convert';
import 'package:catch_toilet/services/location_service.dart';
import 'package:catch_toilet/models/restroom.dart';
import 'package:flutter_test/flutter_test.dart';
import 'models_test.dart' show detailJson;

void main() {
  test('GPS location uses latitude and longitude without user floor', () async {
    final service = LocationService(
      gpsReader: (_) async => const UserLocation(
        label: '현재 GPS 위치',
        latitude: 37.34,
        longitude: 126.83,
        isGps: true,
        accuracy: 8,
      ),
    );
    expect(service.hasSelectedLocation, isFalse);
    service.setLocation(await service.currentGps(service.current));
    expect(service.hasSelectedLocation, isTrue);
    expect(service.current.isGps, isTrue);
    expect(service.current.query, {'latitude': '37.34', 'longitude': '126.83'});
    for (final latitude in [double.nan, double.infinity, 91.0]) {
      expect(
        () => service.setLocation(
          UserLocation(label: 'invalid', latitude: latitude, longitude: 0),
        ),
        throwsFormatException,
      );
    }
  });

  test('location failure preserves the reference location', () async {
    final service = LocationService(
      gpsReader: (_) async => throw const LocationFailure('위치 권한 없음'),
    );
    final previous = service.current;
    await expectLater(
      service.currentGps(previous),
      throwsA(isA<LocationFailure>()),
    );
    expect(service.current, same(previous));
    expect(service.hasSelectedLocation, isFalse);
  });

  test('unknown sensor and facility state is never displayed as free', () {
    final json = jsonDecode(jsonEncode(detailJson())) as Map<String, dynamic>;
    json['unknown_stalls'] = 1;
    json['available_stalls'] = 1;
    json['available_bidet_stalls'] = 0;
    json['bidet_stalls'] = 1;
    json['latitude'] = dimigoLatitude;
    json['longitude'] = dimigoLongitude;
    json['stalls'][0]['occupied'] = null;
    json['stalls'][0]['has_bidet'] = null;
    final room = Restroom.fromJson(json, requireStalls: true);
    expect(room.stalls!.first.occupied, isNull);
    expect(room.unknownStalls, 1);
    expect(room.facilityLabel, contains('비데 1개'));
    expect(room.availableStalls, 1);
  });
}
