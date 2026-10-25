import '../models/recommendation.dart';
import '../models/restroom.dart';
import '../models/stall_update.dart';
import '../services/location_service.dart';

enum RealtimeStatus { demo, connecting, connected, disconnected }

class RepositoryException implements Exception {
  const RepositoryException(this.message, {this.statusCode, this.detail});
  final String message;
  final int? statusCode;
  final String? detail;
  bool get isNotFound => statusCode == 404;
  @override
  String toString() => message;
}

abstract class RestroomRepository {
  bool get isMock;
  RealtimeStatus get realtimeStatus;
  Stream<RealtimeStatus> get connectionChanges;
  Stream<StallUpdate> get updates;
  Future<void> connect();
  void suspend() {}
  Future<void> checkHealth();
  Future<List<Restroom>> getRestrooms(UserLocation location, {String? gender});
  Future<Restroom> getDetail(int id, UserLocation location);
  Future<Recommendation> getRecommendation(
    UserLocation location, {
    required bool bidetRequired,
    String? gender,
  });
  void dispose();
}
