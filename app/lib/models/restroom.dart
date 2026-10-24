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
    );
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
            stalls.where((s) => !s.occupied).length !=
                restroom.availableStalls ||
            stalls.where((s) => !s.occupied && s.hasBidet).length !=
                restroom.availableBidetStalls ||
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
    stalls: stalls == null
        ? null
        : List.unmodifiable(
            stalls!.map(
              (stall) => stall.id == event.stallId
                  ? stall.withOccupied(event.occupied)
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
    stalls: stalls,
  );
}
