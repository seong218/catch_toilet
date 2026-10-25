import 'json_fields.dart';
import 'stall.dart';
import 'stall_update.dart';

class Restroom {
  const Restroom({
    required this.id,
    required this.name,
    required this.building,
    required this.floor,
    required this.x,
    required this.y,
    required this.distance,
    required this.totalStalls,
    required this.availableStalls,
    required this.availableBidetStalls,
    this.stalls,
    this.latitude,
    this.longitude,
    this.gender = 'unisex',
    this.locationSource = 'unverified',
    this.bidetStalls,
    this.accessibleStalls = 0,
    this.unknownStalls = 0,
    this.simulatedStalls = 0,
  });

  final int id;
  final String name;
  final String building;
  final int floor;
  final double x;
  final double y;
  final double? distance;
  final int totalStalls;
  final int availableStalls;
  final int availableBidetStalls;
  // null means detail has not been loaded; [] means there are no stalls.
  final List<Stall>? stalls;
  final double? latitude;
  final double? longitude;
  final String gender;
  final String locationSource;
  final int? bidetStalls;
  final int accessibleStalls;
  final int unknownStalls;
  final int simulatedStalls;
  String get availabilityLabel =>
      unknownStalls == totalStalls && totalStalls > 0
      ? '센서 연결 전 · 상태 미확인'
      : availableStalls > 0
      ? '빈칸 $availableStalls / $totalStalls'
      : unknownStalls > 0
      ? '확인된 빈칸 없음 · $unknownStalls칸 미확인'
      : '현재 빈칸 없음';
  String get facilityLabel =>
      '전체 $totalStalls칸 · ${bidetStalls == null ? '비데 수 미확인' : '비데 $bidetStalls개'}'
      '${accessibleStalls > 0 ? ' · 장애인 $accessibleStalls칸' : ''}';

  factory Restroom.fromJson(Json json, {bool requireStalls = false}) {
    final rawStalls = json['stalls'];
    if ((requireStalls || json.containsKey('stalls')) && rawStalls is! List) {
      throw const FormatException('Invalid stalls');
    }
    final stalls = rawStalls is List
        ? rawStalls.map((s) => Stall.fromJson(jsonObject(s))).toList()
        : null;
    final restroom = Restroom(
      id: integer(json, 'id', minimum: 1),
      name: string(json, 'name'),
      building: string(json, 'building'),
      floor: integer(json, 'floor'),
      x: number(json, 'x'),
      y: number(json, 'y'),
      distance: nullableNumber(json, 'distance'),
      totalStalls: integer(json, 'total_stalls', minimum: 0),
      availableStalls: integer(json, 'available_stalls', minimum: 0),
      availableBidetStalls: integer(json, 'available_bidet_stalls', minimum: 0),
      stalls: stalls == null ? null : List.unmodifiable(stalls),
      latitude: json.containsKey('latitude')
          ? nullableNumber(json, 'latitude')
          : null,
      longitude: json.containsKey('longitude')
          ? nullableNumber(json, 'longitude')
          : null,
      gender: json.containsKey('gender') ? string(json, 'gender') : 'unisex',
      locationSource: json.containsKey('location_source')
          ? string(json, 'location_source')
          : 'unverified',
      bidetStalls: json['bidet_stalls'] == null
          ? null
          : integer(json, 'bidet_stalls', minimum: 0),
      accessibleStalls: json.containsKey('accessible_stalls')
          ? integer(json, 'accessible_stalls', minimum: 0)
          : 0,
      unknownStalls: json.containsKey('unknown_stalls')
          ? integer(json, 'unknown_stalls', minimum: 0)
          : 0,
      simulatedStalls: json.containsKey('simulated_stalls')
          ? integer(json, 'simulated_stalls', minimum: 0)
          : 0,
    );
    if ((restroom.latitude == null) != (restroom.longitude == null) ||
        (restroom.latitude?.abs() ?? 0) > 90 ||
        (restroom.longitude?.abs() ?? 0) > 180 ||
        restroom.simulatedStalls > restroom.totalStalls ||
        restroom.unknownStalls + restroom.availableStalls >
            restroom.totalStalls) {
      throw const FormatException(
        'Invalid geographic location or unknown count',
      );
    }
    validateCounts(
      restroom.totalStalls,
      restroom.availableStalls,
      restroom.availableBidetStalls,
    );
    if (restroom.distance != null && restroom.distance! < 0) {
      throw const FormatException('Negative distance');
    }
    if (stalls != null &&
        (stalls.length != restroom.totalStalls ||
            stalls.where((s) => s.occupied == false).length !=
                restroom.availableStalls ||
            stalls
                    .where((s) => s.occupied == false && s.hasBidet == true)
                    .length !=
                restroom.availableBidetStalls ||
            stalls.where((s) => s.occupied == null).length !=
                restroom.unknownStalls ||
            stalls.where((s) => s.isSimulated).length !=
                restroom.simulatedStalls ||
            stalls.map((s) => s.id).toSet().length != stalls.length ||
            stalls.map((s) => s.stallNumber).toSet().length != stalls.length)) {
      throw const FormatException('Inconsistent restroom detail');
    }
    return restroom;
  }

  Restroom apply(StallUpdate event) => Restroom(
    id: id,
    name: name,
    building: building,
    floor: floor,
    x: x,
    y: y,
    distance: distance,
    totalStalls: event.totalStalls,
    availableStalls: event.availableStalls,
    availableBidetStalls: event.availableBidetStalls,
    latitude: latitude,
    longitude: longitude,
    gender: gender,
    locationSource: locationSource,
    bidetStalls: bidetStalls,
    accessibleStalls: accessibleStalls,
    unknownStalls: event.unknownStalls,
    simulatedStalls: event.simulatedStalls,
    stalls: stalls == null
        ? null
        : List.unmodifiable(
            stalls!.map(
              (stall) => stall.id == event.stallId
                  ? stall.withOccupied(
                      event.occupied,
                      simulated: event.isSimulated,
                    )
                  : stall,
            ),
          ),
  );

  Restroom withDistance(double value) => Restroom(
    id: id,
    name: name,
    building: building,
    floor: floor,
    x: x,
    y: y,
    distance: value,
    totalStalls: totalStalls,
    availableStalls: availableStalls,
    availableBidetStalls: availableBidetStalls,
    latitude: latitude,
    longitude: longitude,
    gender: gender,
    locationSource: locationSource,
    bidetStalls: bidetStalls,
    accessibleStalls: accessibleStalls,
    unknownStalls: unknownStalls,
    simulatedStalls: simulatedStalls,
    stalls: stalls,
  );
}
