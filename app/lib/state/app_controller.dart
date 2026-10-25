import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/recommendation.dart';
import '../models/restroom.dart';
import '../models/stall_update.dart';
import '../repositories/restroom_repository.dart';
import '../services/location_service.dart';

class AppController extends ChangeNotifier {
  AppController(
    this.repository, {
    LocationService? locationService,
    this.eventDelay = const Duration(milliseconds: 250),
  }) : locationService = locationService ?? LocationService(),
       realtimeStatus = repository.realtimeStatus;

  final RestroomRepository repository;
  final LocationService locationService;
  final Duration eventDelay;
  List<Restroom> restrooms = const [];
  Recommendation? recommendation;
  bool bidetRequired = false;
  bool accessibleOnly = false;
  String gender = 'male';
  bool loading = true;
  bool recommendationLoading = false;
  bool recommendationLocating = false;
  LocationFailure? recommendationLocationError;
  bool backendOnline = false;
  RealtimeStatus realtimeStatus;
  String? listError;
  String? recommendationError;
  String? recommendationEmpty;
  DateTime? lastUpdated;
  final Map<int, Restroom> details = {};
  final Map<int, String> detailErrors = {};
  final Set<int> loadingDetails = {};
  final Map<int, int> _eventVersions = {};
  final Set<int> _repairIds = {};
  final Map<int, int> _detailRequests = {};
  StreamSubscription<StallUpdate>? _events;
  StreamSubscription<RealtimeStatus>? _connections;
  Timer? _recommendationTimer;
  Timer? _repairTimer;
  int _listRequest = 0;
  int _recommendationRequest = 0;
  int _locationRequest = 0;
  int? _openDetailId;
  bool _started = false;
  bool _connecting = false;
  bool _suspended = false;
  bool _disposed = false;
  Future<void>? _resuming;
  int _resumeEpoch = 0;

  UserLocation get location => locationService.current;
  bool get hasSelectedLocation => locationService.hasSelectedLocation;
  bool get _canRecommend =>
      hasSelectedLocation &&
      !recommendationLocating &&
      recommendationLocationError == null;
  bool get isMock => repository.isMock;
  bool get accessibleFilterLoading =>
      accessibleOnly &&
      restrooms.any(
        (room) =>
            room.accessibleStalls > 0 &&
            (loadingDetails.contains(room.id) ||
                _repairIds.contains(room.id) ||
                (!details.containsKey(room.id) &&
                    !detailErrors.containsKey(room.id))),
      );

  bool hasAvailableAccessibleStall(int id, {bool bidetRequired = false}) {
    if (loading ||
        loadingDetails.contains(id) ||
        _repairIds.contains(id) ||
        detailErrors.containsKey(id)) {
      return false;
    }
    return details[id]?.stalls?.any(
          (stall) =>
              stall.occupied == false &&
              stall.isAccessible == true &&
              (!bidetRequired || stall.hasBidet == true),
        ) ??
        false;
  }

  Future<void> setAccessibleOnly(bool value) async {
    if (_disposed || accessibleOnly == value) return;
    accessibleOnly = value;
    _notify();
    if (value) await _loadAccessibleDetails();
  }

  Future<void> _loadAccessibleDetails() async {
    if (_disposed || !accessibleOnly) return;
    // List responses contain installation counts, not accessible availability.
    // Cache these few details so normal events can update each stall locally.
    await Future.wait([
      for (final room in restrooms)
        if (room.accessibleStalls > 0 && !loadingDetails.contains(room.id))
          loadDetail(room.id),
    ]);
  }

  bool get hasSimulatedData =>
      restrooms.any((room) => room.simulatedStalls > 0) ||
      (details[_openDetailId]?.simulatedStalls ?? 0) > 0 ||
      (recommendation?.restroom.simulatedStalls ?? 0) > 0;
  bool get isRealtime =>
      realtimeStatus == RealtimeStatus.connected &&
      backendOnline &&
      listError == null &&
      detailErrors.isEmpty &&
      !loading &&
      _repairIds.isEmpty &&
      loadingDetails.isEmpty;

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> start() async {
    if (_started || _disposed) return;
    _started = true;
    _events = repository.updates.listen(
      _applyEvent,
      onError: (Object error) {
        if (!_disposed && !_suspended) unawaited(refresh());
      },
    );
    _connections = repository.connectionChanges.listen((status) {
      if (_disposed) return;
      realtimeStatus = status;
      _notify();
      if (status == RealtimeStatus.connected && !_connecting && !_suspended) {
        unawaited(refresh());
      }
    });
    await resume();
  }

  Future<void> resume() {
    if (_disposed) return Future.value();
    if (_resuming != null) return _resuming!;
    final pending = _resume(++_resumeEpoch);
    _resuming = pending;
    return pending.whenComplete(() {
      if (identical(_resuming, pending)) _resuming = null;
    });
  }

  Future<void> _resume(int epoch) async {
    _suspended = false;
    _connecting = true;
    try {
      await repository.connect();
    } catch (_) {
      /* REST can still work when the socket handshake fails. */
    }
    if (_disposed || _suspended || epoch != _resumeEpoch) return;
    realtimeStatus = repository.realtimeStatus;
    // Keep suppressing the connected notification until this explicit snapshot
    // finishes; otherwise a second refresh can invalidate the awaited response.
    await refresh();
    if (epoch == _resumeEpoch) _connecting = false;
  }

  void suspend() {
    ++_resumeEpoch;
    _resuming = null;
    _connecting = false;
    _suspended = true;
    _recommendationTimer?.cancel();
    _repairTimer?.cancel();
    _repairTimer = null;
    repository.suspend();
    realtimeStatus = repository.realtimeStatus;
    _notify();
  }

  Future<void> refresh() async {
    if (_disposed) return;
    final repairs = {..._repairIds, ?_openDetailId};
    _repairIds.clear();
    await Future.wait([
      _loadList(),
      refreshRecommendation(),
      for (final id in repairs) loadDetail(id),
    ]);
  }

  Future<void> _loadList() async {
    final request = ++_listRequest;
    final origin = location;
    final versions = Map<int, int>.of(_eventVersions);
    loading = true;
    listError = null;
    _notify();
    try {
      await repository.checkHealth();
      final result = await repository.getRestrooms(origin, gender: gender);
      if (_disposed || request != _listRequest) return;
      final current = {for (final r in restrooms) r.id: r};
      final merged = <Restroom>[];
      for (final r in result) {
        if ((_eventVersions[r.id] ?? 0) != (versions[r.id] ?? 0)) {
          // Keep displayed event state; never replay a buffer over a snapshot.
          if (current[r.id] != null) merged.add(current[r.id]!);
          _scheduleRepair(r.id);
        } else {
          merged.add(r);
        }
      }
      restrooms = List.unmodifiable(merged);
      backendOnline = !isMock;
      lastUpdated = DateTime.now();
      // Also refresh filtered details after reconnect, pull-to-refresh, or a
      // gender/location change; a retained cache may have missed events.
      if (accessibleOnly) await _loadAccessibleDetails();
    } catch (error) {
      if (_disposed || request != _listRequest) return;
      backendOnline = false;
      listError = messageFor(error);
    } finally {
      if (!_disposed && request == _listRequest) {
        loading = false;
        _notify();
      }
    }
  }

  Future<void> setGender(String value) async {
    if (value == gender || !['male', 'female'].contains(value)) return;
    gender = value;
    await _reloadLocationData();
  }

  Future<void> setBidetRequired(bool value) async {
    if (value == bidetRequired) return;
    bidetRequired = value;
    recommendation = null;
    await refreshRecommendation();
  }

  Future<void> setLocation(UserLocation value) async {
    if (_disposed) return;
    locationService.setLocation(value);
    ++_locationRequest;
    recommendationLocating = false;
    recommendationLocationError = null;
    await _reloadLocationData();
  }

  Future<void> _reloadLocationData() async {
    details.clear();
    detailErrors.clear();
    for (final id in _detailRequests.keys.toList()) {
      _detailRequests[id] = _detailRequests[id]! + 1;
    }
    loadingDetails.clear();
    restrooms = const [];
    recommendation = null;
    await refresh();
  }

  // Explicit recommendation requests refresh GPS. Sensor/filter refreshes reuse
  // the confirmed location and never prompt for permission on their own.
  Future<void> requestRecommendation() async {
    if (_disposed || recommendationLocating) return;
    if (hasSelectedLocation && !location.isGps) {
      await refreshRecommendation();
      return;
    }
    final request = ++_locationRequest;
    ++_recommendationRequest;
    _recommendationTimer?.cancel();
    recommendationLocating = true;
    recommendationLoading = false;
    recommendation = null;
    recommendationError = null;
    recommendationEmpty = null;
    recommendationLocationError = null;
    _notify();
    try {
      final value = await locationService.currentGps(location);
      if (_disposed || request != _locationRequest) return;
      await setLocation(value);
    } catch (error) {
      if (_disposed || request != _locationRequest) return;
      recommendationLocating = false;
      recommendationLocationError = error is LocationFailure
          ? error
          : const LocationFailure('현재 위치를 확인하지 못했어요. 다시 시도해 주세요.');
      _notify();
    }
  }

  Future<void> refreshRecommendation() async {
    if (_disposed || !_canRecommend) return;
    _recommendationTimer?.cancel();
    final request = ++_recommendationRequest;
    recommendationLoading = true;
    recommendationError = null;
    recommendationEmpty = null;
    _notify();
    try {
      final result = await repository.getRecommendation(
        location,
        bidetRequired: bidetRequired,
        gender: gender,
      );
      if (_disposed || request != _recommendationRequest) return;
      recommendation = result;
    } on RepositoryException catch (error) {
      if (_disposed || request != _recommendationRequest) return;
      recommendation = null;
      if (error.isNotFound) {
        recommendationEmpty = switch (error.detail) {
          'Live availability unavailable' =>
            '아직 센서 상태가 확인되지 않았어요. 목록 탭에서 시설 정보를 확인하세요.',
          'Restroom location unavailable' => '화장실 위치를 확인하고 있어요.',
          'No available bidet stalls' => '현재 사용 가능하다고 확인된 비데 칸이 없어요.',
          _ => '아직 추천할 화장실이 없어요.',
        };
      } else {
        recommendationError = error.message;
      }
    } catch (error) {
      if (_disposed || request != _recommendationRequest) return;
      recommendation = null;
      recommendationError = messageFor(error);
    } finally {
      if (!_disposed && request == _recommendationRequest) {
        recommendationLoading = false;
        _notify();
      }
    }
  }

  void _scheduleRecommendation() {
    if (!_canRecommend) return;
    ++_recommendationRequest; // Invalidate responses started before this event.
    recommendationLoading = true;
    _recommendationTimer?.cancel();
    _recommendationTimer = Timer(eventDelay, () {
      if (!_disposed && !_suspended) unawaited(refreshRecommendation());
    });
  }

  Future<void> openDetail(int id) {
    _openDetailId = id;
    return loadDetail(id);
  }

  void closeDetail(int id) {
    if (_openDetailId == id) _openDetailId = null;
  }

  Future<void> loadDetail(int id) async {
    if (_disposed) return;
    final request = (_detailRequests[id] ?? 0) + 1;
    _detailRequests[id] = request;
    final version = _eventVersions[id] ?? 0;
    loadingDetails.add(id);
    detailErrors.remove(id);
    _notify();
    try {
      final result = await repository.getDetail(id, location);
      if (_disposed || _detailRequests[id] != request) return;
      if (version != (_eventVersions[id] ?? 0)) {
        _scheduleRepair(id);
        return;
      }
      details[id] = result;
      _repairIds.remove(id);
      _upsert(result);
      if (recommendation?.restroom.id == id) {
        recommendation = recommendation!.withRestroom(result);
      }
    } catch (error) {
      if (_disposed || _detailRequests[id] != request) return;
      detailErrors[id] = messageFor(error);
      if (error is RepositoryException && error.isNotFound) {
        details.remove(id);
        restrooms = List.unmodifiable(restrooms.where((r) => r.id != id));
        if (recommendation?.restroom.id == id) recommendation = null;
        _repairIds.remove(id);
      } else {
        backendOnline = false;
        listError = '최신 상태를 확인하지 못했습니다. 다시 시도해 주세요.';
      }
    } finally {
      if (!_disposed && _detailRequests[id] == request) {
        loadingDetails.remove(id);
        _notify();
      }
    }
  }

  void _upsert(Restroom room) {
    if (!isMock && room.gender != gender) return;
    final updated = [...restrooms.where((r) => r.id != room.id), room];
    updated.sort((a, b) {
      final distance = (a.distance ?? double.infinity).compareTo(
        b.distance ?? double.infinity,
      );
      return distance != 0 ? distance : a.id.compareTo(b.id);
    });
    restrooms = List.unmodifiable(updated);
  }

  void _scheduleRepair(int id) {
    _repairIds.add(id);
    _repairTimer ??= Timer(eventDelay, () {
      _repairTimer = null;
      if (_disposed || _suspended) return;
      final ids = _repairIds.toList();
      _repairIds.clear();
      for (final id in ids) {
        unawaited(loadDetail(id));
      }
    });
  }

  void _applyEvent(StallUpdate event) {
    if (_disposed || _suspended) return;
    Restroom? before;
    for (final room in restrooms) {
      if (room.id == event.restroomId) {
        before = room;
        break;
      }
    }
    final cached = details[event.restroomId];
    final knownStalls = cached?.stalls?.where((s) => s.id == event.stallId);
    final unknownStall = cached != null && (knownStalls?.isEmpty ?? true);
    final sameStall =
        knownStalls?.isNotEmpty == true &&
        knownStalls!.first.occupied == event.occupied &&
        knownStalls.first.isSimulated == event.isSimulated;
    if (before != null &&
        !unknownStall &&
        before.totalStalls == event.totalStalls &&
        before.availableStalls == event.availableStalls &&
        before.availableBidetStalls == event.availableBidetStalls &&
        before.unknownStalls == event.unknownStalls &&
        before.simulatedStalls == event.simulatedStalls &&
        (cached == null || sameStall)) {
      return;
    }

    _eventVersions[event.restroomId] =
        (_eventVersions[event.restroomId] ?? 0) + 1;
    restrooms = List.unmodifiable(
      restrooms.map((r) => r.id == event.restroomId ? r.apply(event) : r),
    );
    if (cached != null) details[event.restroomId] = cached.apply(event);
    if (recommendation?.restroom.id == event.restroomId) {
      recommendation = recommendation!.withRestroom(
        recommendation!.restroom.apply(event),
      );
      // Only Backend may choose an all-full fallback.
      if (event.availableStalls == 0 ||
          (bidetRequired && event.availableBidetStalls == 0)) {
        recommendation = null;
      }
    }
    final updatedDetail = details[event.restroomId];
    final inconsistent =
        updatedDetail != null &&
        (updatedDetail.stalls!.length != updatedDetail.totalStalls ||
            updatedDetail.stalls!.where((s) => s.occupied == false).length !=
                updatedDetail.availableStalls ||
            updatedDetail.stalls!
                    .where((s) => s.occupied == false && s.hasBidet == true)
                    .length !=
                updatedDetail.availableBidetStalls ||
            updatedDetail.stalls!.where((s) => s.occupied == null).length !=
                updatedDetail.unknownStalls ||
            updatedDetail.stalls!.where((s) => s.isSimulated).length !=
                updatedDetail.simulatedStalls);
    if (before == null || unknownStall || inconsistent) {
      _scheduleRepair(event.restroomId);
    }
    lastUpdated = DateTime.now();
    _scheduleRecommendation();
    _notify();
  }

  static String messageFor(Object error) => error is RepositoryException
      ? error.message
      : '정보를 불러올 수 없습니다. 잠시 후 다시 시도해 주세요.';

  @override
  void dispose() {
    _disposed = true;
    _recommendationTimer?.cancel();
    _repairTimer?.cancel();
    unawaited(_events?.cancel());
    unawaited(_connections?.cancel());
    repository.dispose();
    super.dispose();
  }
}
