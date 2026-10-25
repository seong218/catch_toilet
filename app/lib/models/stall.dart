import 'json_fields.dart';

class Stall {
  const Stall({
    required this.id,
    required this.stallNumber,
    required this.occupied,
    required this.hasBidet,
    this.isAccessible,
    this.isSimulated = false,
  });

  final int id;
  final int stallNumber;
  final bool? occupied;
  final bool? hasBidet;
  final bool? isAccessible;
  final bool isSimulated;

  factory Stall.fromJson(Json json) => Stall(
    id: integer(json, 'id', minimum: 1),
    stallNumber: integer(json, 'stall_number', minimum: 1),
    occupied: nullableBoolean(json, 'occupied'),
    hasBidet: nullableBoolean(json, 'has_bidet'),
    isAccessible: json.containsKey('is_accessible')
        ? nullableBoolean(json, 'is_accessible')
        : null,
    isSimulated: json.containsKey('is_simulated')
        ? boolean(json, 'is_simulated')
        : false,
  );

  Stall withOccupied(bool? value, {bool? simulated}) => Stall(
    id: id,
    stallNumber: stallNumber,
    occupied: value,
    hasBidet: hasBidet,
    isAccessible: isAccessible,
    isSimulated: simulated ?? isSimulated,
  );
}
