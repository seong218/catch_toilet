import 'json_fields.dart';
import 'restroom.dart';

class Recommendation {
  const Recommendation({
    required this.restroom,
    required this.statisticsUsed,
    this.historicalAvailabilityRate,
    this.historicalBidetAvailabilityRate,
  });

  final Restroom restroom;
  final bool statisticsUsed;
  final double? historicalAvailabilityRate;
  final double? historicalBidetAvailabilityRate;

  factory Recommendation.fromJson(Json json) {
    final restroom = Restroom.fromJson(json);
    final normal = nullableNumber(json, 'historical_availability_rate');
    final bidet = nullableNumber(json, 'historical_bidet_availability_rate');
    if (restroom.distance == null ||
        [normal, bidet].any((rate) => rate != null && (rate < 0 || rate > 1))) {
      throw const FormatException('Invalid recommendation');
    }
    return Recommendation(
      restroom: restroom,
      statisticsUsed: boolean(json, 'statistics_used'),
      historicalAvailabilityRate: normal,
      historicalBidetAvailabilityRate: bidet,
    );
  }

  Recommendation withRestroom(Restroom value) => Recommendation(
    restroom: value,
    statisticsUsed: statisticsUsed,
    historicalAvailabilityRate: historicalAvailabilityRate,
    historicalBidetAvailabilityRate: historicalBidetAvailabilityRate,
  );
}
