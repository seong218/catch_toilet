import 'package:catchy_toilet/models/recommendation.dart';
import 'package:catchy_toilet/models/restroom.dart';
import 'package:catchy_toilet/models/stall_update.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> restroomJson() => {
  'id': 1,
  'name': '본관 1층',
  'building': '본관',
  'floor': 1,
  'x': 10,
  'y': 20.0,
  'distance': null,
  'total_stalls': 3,
  'available_stalls': 2,
  'available_bidet_stalls': 1,
};

Map<String, dynamic> detailJson() => {
  ...restroomJson(),
  'stalls': [
    {'id': 1, 'stall_number': 1, 'occupied': false, 'has_bidet': true},
    {'id': 2, 'stall_number': 2, 'occupied': true, 'has_bidet': false},
    {'id': 3, 'stall_number': 3, 'occupied': false, 'has_bidet': false},
  ],
};

void main() {
  test('contract numbers accept integer coordinates and nullable distance', () {
    final restroom = Restroom.fromJson(restroomJson());
    expect(restroom.x, 10.0);
    expect(restroom.distance, isNull);
    expect(restroom.stalls, isNull);
  });

  test(
    'contract detail checks counts and does not confuse index with stall ID',
    () {
      final restroom = Restroom.fromJson(detailJson(), requireStalls: true);
      expect(restroom.stalls!.last.id, 3);
      expect(
        () => Restroom.fromJson({...detailJson(), 'available_stalls': 1}),
        throwsFormatException,
      );
      expect(
        () => Restroom.fromJson(restroomJson(), requireStalls: true),
        throwsFormatException,
      );
    },
  );

  test(
    'malformed fields are rejected instead of reporting false availability',
    () {
      expect(
        () => Restroom.fromJson({...restroomJson(), 'available_stalls': '2'}),
        throwsFormatException,
      );
      expect(
        () =>
            Restroom.fromJson({...restroomJson(), 'available_bidet_stalls': 3}),
        throwsFormatException,
      );
      expect(
        () => Restroom.fromJson({...restroomJson(), 'x': double.nan}),
        throwsFormatException,
      );
      final missingDistance = restroomJson()..remove('distance');
      expect(() => Restroom.fromJson(missingDistance), throwsFormatException);
    },
  );

  test('unknown added fields do not break parsing', () {
    expect(Restroom.fromJson({...restroomJson(), 'future_field': true}).id, 1);
  });

  test('statistics flag is independent from nullable rates', () {
    final recommendation = Recommendation.fromJson({
      ...restroomJson(),
      'distance': 42,
      'statistics_used': false,
      'historical_availability_rate': 0.82,
      'historical_bidet_availability_rate': null,
    });
    expect(recommendation.statisticsUsed, isFalse);
    expect(recommendation.historicalAvailabilityRate, 0.82);
    expect(recommendation.historicalBidetAvailabilityRate, isNull);
  });

  test('event assignment is idempotent and preserves bidet metadata', () {
    final restroom = Restroom.fromJson(detailJson());
    final event = StallUpdate.fromJson({
      'type': 'stall.updated',
      'restroom_id': 1,
      'stall_id': 3,
      'occupied': true,
      'total_stalls': 3,
      'available_stalls': 1,
      'available_bidet_stalls': 1,
    });
    final twice = restroom.apply(event).apply(event);
    expect(twice.availableStalls, 1);
    expect(twice.availableBidetStalls, 1);
    expect(twice.stalls!.last.occupied, isTrue);
    expect(twice.stalls!.first.hasBidet, isTrue);
  });
}
