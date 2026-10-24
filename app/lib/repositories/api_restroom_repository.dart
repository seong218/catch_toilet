import '../models/json_fields.dart';
import '../models/recommendation.dart';
import '../models/restroom.dart';
import '../models/stall_update.dart';
import '../services/api_service.dart';
import '../services/location_service.dart';
import '../services/websocket_service.dart';
import 'restroom_repository.dart';

class ApiRestroomRepository extends RestroomRepository {
  ApiRestroomRepository(this.api, {WebsocketService? websocket})
    : websocket = websocket ?? WebsocketService(api.websocketUri);

  final ApiService api;
  final WebsocketService websocket;
  @override
  bool get isMock => false;
  @override
  RealtimeStatus get realtimeStatus => websocket.status;
  @override
  Stream<RealtimeStatus> get connectionChanges => websocket.connectionChanges;
  @override
  Stream<StallUpdate> get updates => websocket.updates;
  @override
  Future<void> connect() => websocket.connect();
  @override
  void suspend() => websocket.suspend();
  @override
  Future<void> checkHealth() => api.get('/api/health', (value) {
    if (jsonObject(value)['status'] != 'ok') {
      throw const FormatException('Invalid health status');
    }
  });
  @override
  Future<List<Restroom>> getRestrooms(UserLocation location) =>
      api.get('/api/restrooms', (value) {
        if (value is! List) throw const FormatException('Expected array');
        final result = value
            .map((r) => Restroom.fromJson(jsonObject(r)))
            .toList();
        if (result.map((r) => r.id).toSet().length != result.length) {
          throw const FormatException('Duplicate restroom IDs');
        }
        return result;
      }, query: location.query);
  @override
  Future<Restroom> getDetail(int id, UserLocation location) => api.get(
    '/api/restrooms/$id',
    (value) {
      final result = Restroom.fromJson(jsonObject(value), requireStalls: true);
      if (result.id != id) throw const FormatException('Wrong restroom ID');
      return result;
    },
    query: location.query,
  );
  @override
  Future<Recommendation> getRecommendation(
    UserLocation location, {
    required bool bidetRequired,
  }) => api.get('/api/restrooms/recommend', (value) {
    final result = Recommendation.fromJson(jsonObject(value));
    final rate = bidetRequired
        ? result.historicalBidetAvailabilityRate
        : result.historicalAvailabilityRate;
    if (result.statisticsUsed && rate == null) {
      throw const FormatException('Statistics flag requires the relevant rate');
    }
    return result;
  }, query: {...location.query, 'bidet_required': '$bidetRequired'});
  @override
  void dispose() {
    websocket.dispose();
    api.dispose();
  }
}
