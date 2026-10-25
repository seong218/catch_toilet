import 'json_fields.dart';

class StallUpdate {
  const StallUpdate({
    required this.restroomId,
    required this.stallId,
    required this.occupied,
    required this.totalStalls,
    required this.availableStalls,
    required this.availableBidetStalls,
    this.unknownStalls = 0,
    this.simulatedStalls = 0,
    this.isSimulated = false,
  });

  final int restroomId;
  final int stallId;
  final bool? occupied;
  final int simulatedStalls;
  final bool isSimulated;
  final int totalStalls;
  final int availableStalls;
  final int availableBidetStalls;
  final int unknownStalls;

  factory StallUpdate.fromJson(Json json) {
    final update = StallUpdate(
      restroomId: integer(json, 'restroom_id', minimum: 1),
      stallId: integer(json, 'stall_id', minimum: 1),
      occupied: nullableBoolean(json, 'occupied'),
      simulatedStalls: json.containsKey('simulated_stalls')
          ? integer(json, 'simulated_stalls', minimum: 0)
          : 0,
      isSimulated: json.containsKey('is_simulated')
          ? boolean(json, 'is_simulated')
          : false,
      totalStalls: integer(json, 'total_stalls', minimum: 0),
      availableStalls: integer(json, 'available_stalls', minimum: 0),
      availableBidetStalls: integer(json, 'available_bidet_stalls', minimum: 0),
      unknownStalls: json.containsKey('unknown_stalls')
          ? integer(json, 'unknown_stalls', minimum: 0)
          : 0,
    );
    validateCounts(
      update.totalStalls,
      update.availableStalls,
      update.availableBidetStalls,
    );
    if (update.unknownStalls + update.availableStalls > update.totalStalls ||
        update.simulatedStalls > update.totalStalls ||
        (update.isSimulated && update.simulatedStalls == 0)) {
      throw const FormatException('Invalid unknown stall count');
    }
    return update;
  }
}
