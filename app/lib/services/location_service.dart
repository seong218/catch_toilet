import 'package:geolocator/geolocator.dart';

// School representative point, not a surveyed restroom entrance.
// https://www.hifive.go.kr/search/schoolMap.do?sch_seq=653
const dimigoLatitude = 37.34156740773243;
const dimigoLongitude = 126.83126714636612;

class UserLocation {
  const UserLocation({
    required this.label,
    required this.latitude,
    required this.longitude,
    this.isGps = false,
    this.accuracy,
  });
  final String label;
  final double latitude;
  final double longitude;
  final bool isGps;
  final double? accuracy;
  Map<String, String> get query => {
    'latitude': '$latitude',
    'longitude': '$longitude',
  };
}

class LocationFailure implements Exception {
  const LocationFailure(this.message, {this.openSettings = false});
  final String message;
  final bool openSettings;
}

class LocationService {
  LocationService({this.gpsReader});
  final Future<UserLocation> Function(UserLocation)? gpsReader;
  // The initial campus point centers the map; it is not the user's location.
  bool get hasSelectedLocation => _hasSelectedLocation;
  bool _hasSelectedLocation = false;
  UserLocation current = const UserLocation(
    label: '디미고 본관 기준',
    latitude: dimigoLatitude,
    longitude: dimigoLongitude,
  );

  void setLocation(UserLocation value) {
    if (!value.latitude.isFinite ||
        !value.longitude.isFinite ||
        value.latitude.abs() > 90 ||
        value.longitude.abs() > 180 ||
        value.label.trim().isEmpty) {
      throw const FormatException('Invalid geographic location');
    }
    current = value;
    _hasSelectedLocation = true;
  }

  Future<UserLocation> currentGps(UserLocation reference) async {
    if (gpsReader != null) return gpsReader!(reference);
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw const LocationFailure('기기의 위치 서비스를 켜 주세요.', openSettings: true);
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.deniedForever) {
      throw const LocationFailure('설정에서 위치 접근을 허용해 주세요.', openSettings: true);
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.unableToDetermine) {
      throw const LocationFailure(
        '위치 권한이 없어요. GPS를 허용하거나 위치 변경에서 기준 위치를 선택해 주세요.',
      );
    }
    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 15),
        ),
      );
      return UserLocation(
        label: '현재 GPS 위치',
        latitude: position.latitude,
        longitude: position.longitude,
        isGps: true,
        accuracy: position.accuracy,
      );
    } catch (_) {
      throw const LocationFailure(
        '위치를 가져오지 못했어요. 다시 시도하거나 위치 변경에서 기준 위치를 선택해 주세요.',
      );
    }
  }

  // Demo-only distance. Real ranking and distances come from Backend.
  static double demoDistance(
    UserLocation origin,
    double longitude,
    double latitude,
  ) => Geolocator.distanceBetween(
    origin.latitude,
    origin.longitude,
    latitude,
    longitude,
  );
}
