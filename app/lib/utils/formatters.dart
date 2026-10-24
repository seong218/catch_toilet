String distanceLabel(double? distance) {
  if (distance == null) return '거리 정보 없음';
  if (distance >= 1000) return '${(distance / 1000).toStringAsFixed(1)} km';
  return '${distance.round()} m';
}

String floorLabel(int floor) => floor < 0 ? '지하 ${-floor}층' : '$floor층';
