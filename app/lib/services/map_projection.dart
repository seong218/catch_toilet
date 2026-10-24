import 'dart:math';

import '../models/restroom.dart';
import 'location_service.dart';

// Viewport projection only. This never calculates distance or recommendations.
class MapProjection {
  MapProjection(List<Restroom> restrooms, UserLocation location) {
    final xs = [location.x, ...restrooms.map((r) => r.x)];
    final ys = [location.y, ...restrooms.map((r) => r.y)];
    _minX = xs.reduce(min);
    _minY = ys.reduce(min);
    _spanX = max(xs.reduce(max) - _minX, 40.0);
    _spanY = max(ys.reduce(max) - _minY, 40.0);
  }
  late final double _minX;
  late final double _minY;
  late final double _spanX;
  late final double _spanY;

  double horizontal(double x) => 0.12 + (x - _minX) / _spanX * 0.76;
  double vertical(double y) => 0.8 - (y - _minY) / _spanY * 0.6;
}
