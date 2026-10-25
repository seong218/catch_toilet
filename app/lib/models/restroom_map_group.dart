import '../data/campus_buildings.dart';
import 'restroom.dart';

/// Only presentation grouping; ranking and distances remain Backend-owned.
class RestroomMapGroup {
  const RestroomMapGroup({
    required this.id,
    required this.title,
    required this.latitude,
    required this.longitude,
    required this.restrooms,
  });

  final String id;
  final String title;
  final double latitude;
  final double longitude;
  final List<Restroom> restrooms;

  int get availableStalls =>
      restrooms.fold(0, (count, room) => count + room.availableStalls);
  int get unknownStalls =>
      restrooms.fold(0, (count, room) => count + room.unknownStalls);
  int get totalStalls =>
      restrooms.fold(0, (count, room) => count + room.totalStalls);
  bool get isSchoolReference =>
      restrooms.any((room) => room.locationSource == 'school_reference');
  String statusLabel({required bool isLive}) {
    if (restrooms.isEmpty) return '화장실 정보 준비 중';
    if (!isLive) return '최신 상태 확인 필요';
    if (totalStalls == 0) return '등록된 칸 없음';
    if (unknownStalls == totalStalls) return '상태 미확인';
    if (availableStalls == 0 && unknownStalls == 0) return '현재 만석';
    return '빈칸 $availableStalls칸'
        '${unknownStalls > 0 ? ' · 미확인 $unknownStalls칸' : ''}';
  }

  static List<RestroomMapGroup> fromRestrooms(Iterable<Restroom> restrooms) {
    // Buildings remain visible before facilities are registered or loaded.
    // API coordinates may be shared school references, so group by building.
    return campusBuildings.map((building) {
      final rooms =
          restrooms.where((room) => building.matches(room.building)).toList()
            ..sort((a, b) {
              final floor = a.floor.compareTo(b.floor);
              return floor != 0 ? floor : a.id.compareTo(b.id);
            });
      return RestroomMapGroup(
        id: building.id,
        title: building.name,
        latitude: building.latitude,
        longitude: building.longitude,
        restrooms: List.unmodifiable(rooms),
      );
    }).toList();
  }
}
