import 'dart:math';

class UserLocation {
  const UserLocation({required this.label, required this.x, required this.y});
  final String label;
  final double x;
  final double y;
  Map<String, String> get query => {'x': '$x', 'y': '$y'};
}

// MVP reference coordinates. A GPS/indoor provider can replace this service.
class LocationService {
  UserLocation current = const UserLocation(label: '본관 입구', x: 10, y: 20);

  void setLocation(UserLocation value) {
    if (!value.x.isFinite || !value.y.isFinite || value.label.trim().isEmpty) {
      throw const FormatException('Invalid reference location');
    }
    current = value;
  }

  // Only demo fixtures use this. API distances are always supplied by Backend.
  static double demoDistance(UserLocation origin, double x, double y) =>
      sqrt(pow(origin.x - x, 2) + pow(origin.y - y, 2));
}
