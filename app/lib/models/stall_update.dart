import 'json_fields.dart';

class StallUpdate {
  const StallUpdate({
    required this.restroomId,
    required this.stallId,
    required this.occupied,
    required this.totalStalls,
    required this.availableStalls,
    required this.availableBidetStalls,
  });

  final int restroomId;
  final int stallId;
  final bool occupied;
  final int totalStalls;
  final int availableStalls;
  final int availableBidetStalls;

  factory StallUpdate.fromJson(Json json) {
    final update = StallUpdate(
      restroomId: integer(json, 'restroom_id', minimum: 1),
      stallId: integer(json, 'stall_id', minimum: 1),
      occupied: boolean(json, 'occupied'),
      totalStalls: integer(json, 'total_stalls', minimum: 0),
      availableStalls: integer(json, 'available_stalls', minimum: 0),
      availableBidetStalls: integer(json, 'available_bidet_stalls', minimum: 0),
    );
    validateCounts(
      update.totalStalls,
      update.availableStalls,
      update.availableBidetStalls,
    );
    return update;
  }
}
