import 'json_fields.dart';

class Stall {
  const Stall({
    required this.id,
    required this.stallNumber,
    required this.occupied,
    required this.hasBidet,
  });

  final int id;
  final int stallNumber;
  final bool occupied;
  final bool hasBidet;

  factory Stall.fromJson(Json json) => Stall(
    id: integer(json, 'id', minimum: 1),
    stallNumber: integer(json, 'stall_number', minimum: 1),
    occupied: boolean(json, 'occupied'),
    hasBidet: boolean(json, 'has_bidet'),
  );

  Stall withOccupied(bool value) => Stall(
    id: id,
    stallNumber: stallNumber,
    occupied: value,
    hasBidet: hasBidet,
  );
}
