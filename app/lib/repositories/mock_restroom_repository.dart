import '../models/recommendation.dart';
import '../models/restroom.dart';
import '../models/stall.dart';
import '../models/stall_update.dart';
import '../services/location_service.dart';
import 'restroom_repository.dart';

// Clearly fictional fixtures. Recommendations are scripted responses, not a
// client-side ranking algorithm or real historical observations.
class MockRestroomRepository extends RestroomRepository {
  static const fixtures = [
    Restroom(
      id: 1,
      name: '본관 1층',
      building: '본관',
      floor: 1,
      x: 30,
      y: 20,
      distance: 20,
      totalStalls: 3,
      availableStalls: 1,
      availableBidetStalls: 0,
      stalls: [
        Stall(id: 1, stallNumber: 1, occupied: true, hasBidet: true),
        Stall(id: 2, stallNumber: 2, occupied: false, hasBidet: false),
        Stall(id: 3, stallNumber: 3, occupied: true, hasBidet: false),
      ],
    ),
    Restroom(
      id: 2,
      name: '본관 2층',
      building: '본관',
      floor: 2,
      x: 40,
      y: 60,
      distance: 50,
      totalStalls: 5,
      availableStalls: 2,
      availableBidetStalls: 1,
      stalls: [
        Stall(id: 4, stallNumber: 1, occupied: false, hasBidet: true),
        Stall(id: 5, stallNumber: 2, occupied: true, hasBidet: true),
        Stall(id: 6, stallNumber: 3, occupied: true, hasBidet: false),
        Stall(id: 7, stallNumber: 4, occupied: false, hasBidet: false),
        Stall(id: 8, stallNumber: 5, occupied: true, hasBidet: false),
      ],
    ),
    Restroom(
      id: 3,
      name: '체육관 화장실',
      building: '체육관',
      floor: 1,
      x: 130,
      y: 20,
      distance: 120,
      totalStalls: 3,
      availableStalls: 3,
      availableBidetStalls: 1,
      stalls: [
        Stall(id: 9, stallNumber: 1, occupied: false, hasBidet: true),
        Stall(id: 10, stallNumber: 2, occupied: false, hasBidet: false),
        Stall(id: 11, stallNumber: 3, occupied: false, hasBidet: false),
      ],
    ),
  ];

  @override
  bool get isMock => true;
  @override
  RealtimeStatus get realtimeStatus => RealtimeStatus.demo;
  @override
  Stream<RealtimeStatus> get connectionChanges => const Stream.empty();
  @override
  Stream<StallUpdate> get updates => const Stream.empty();
  @override
  Future<void> connect() async {}
  @override
  Future<void> checkHealth() async {}
  @override
  Future<List<Restroom>> getRestrooms(
    UserLocation location, {
    String? gender,
  }) async =>
      fixtures
          .map(
            (r) => r.withDistance(
              LocationService.demoDistance(location, r.x, r.y),
            ),
          )
          .toList()
        ..sort((a, b) => a.distance!.compareTo(b.distance!));
  @override
  Future<Restroom> getDetail(int id, UserLocation location) async {
    final matches = fixtures.where((r) => r.id == id);
    if (matches.isEmpty) {
      throw const RepositoryException('화장실을 찾을 수 없습니다.', statusCode: 404);
    }
    final r = matches.first;
    return r.withDistance(LocationService.demoDistance(location, r.x, r.y));
  }

  @override
  Future<Recommendation> getRecommendation(
    UserLocation location, {
    required bool bidetRequired,
    String? gender,
  }) async => Recommendation(
    restroom: await getDetail(bidetRequired ? 2 : 1, location),
    statisticsUsed: false,
  );
  @override
  void dispose() {}
}
