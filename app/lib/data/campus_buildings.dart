/// Display positions for the five campus buildings, not restroom/GPS fixes.
/// Derived from OpenStreetMap building footprints; see docs/KAKAO_MAP_SETUP.md.
/// Distances and recommendations continue to use the coordinates from the API.
class CampusBuilding {
  const CampusBuilding({
    required this.id,
    required this.name,
    required this.latitude,
    required this.longitude,
    this.aliases = const [],
  });

  final String id;
  final String name;
  final double latitude;
  final double longitude;
  final List<String> aliases;

  bool matches(String building) {
    final normalized = building.replaceAll(RegExp(r'\s+'), '');
    return [
      name,
      ...aliases,
    ].any((name) => name.replaceAll(RegExp(r'\s+'), '') == normalized);
  }
}

const campusBuildings = [
  CampusBuilding(
    id: 'building-main',
    name: '본관',
    latitude: 37.341886,
    longitude: 126.831469,
  ),
  CampusBuilding(
    id: 'building-new',
    name: '신관',
    latitude: 37.341374,
    longitude: 126.831241,
    aliases: ['정보기술문화센터', '정보기술문화센터(신관)'],
  ),
  CampusBuilding(
    id: 'building-woojung',
    name: '우정학사',
    latitude: 37.340460,
    longitude: 126.831022,
  ),
  CampusBuilding(
    id: 'building-hakbong',
    name: '학봉관',
    latitude: 37.342363,
    longitude: 126.830931,
  ),
  CampusBuilding(
    id: 'building-gym',
    name: '체육관',
    // The football pitch occupies the roof of the gym.
    latitude: 37.341820,
    longitude: 126.830704,
  ),
];
