import 'dart:async';

import 'package:flutter/material.dart';
import 'package:kakao_map_sdk/kakao_map_sdk.dart';

import '../models/restroom_map_group.dart';
import '../services/location_service.dart';
import '../services/kakao_map_service.dart';
import 'kakao_map_markers.dart';

class LocationMap extends StatefulWidget {
  const LocationMap({
    super.key,
    required this.groups,
    required this.location,
    required this.isLive,
    required this.onSelectGroup,
    required this.onShowRestrooms,
    required this.onMapTapped,
    required this.contentPadding,
    this.cameraTarget,
  });

  final List<RestroomMapGroup> groups;
  final UserLocation location;
  final UserLocation? cameraTarget;
  final bool isLive;
  final ValueChanged<String> onSelectGroup;
  final VoidCallback onShowRestrooms;
  final VoidCallback onMapTapped;
  final EdgeInsets contentPadding;

  @override
  State<LocationMap> createState() => _LocationMapState();
}

class _LocationMapState extends State<LocationMap> {
  final _service = KakaoMapService.instance;
  KakaoMapController? _controller;
  KakaoMapMarkers? _markers;
  Future<void> _updates = Future.value();
  Timer? _loadTimer;
  MapFailure? _failure;
  int _attempt = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_initialize());
  }

  Future<void> _initialize() async {
    await _service.initialize();
    if (mounted &&
        _service.availability == MapAvailability.ready &&
        _controller == null) {
      _startLoadTimer();
    }
  }

  void _startLoadTimer() {
    _loadTimer?.cancel();
    _loadTimer = Timer(const Duration(seconds: 20), () {
      if (mounted) setState(() => _failure = MapFailure.connection);
    });
  }

  @override
  void didUpdateWidget(covariant LocationMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    _queueUpdate();
    if (oldWidget.contentPadding != widget.contentPadding) {
      _enqueue(_positionLogo);
    }
    if (oldWidget.cameraTarget != widget.cameraTarget &&
        widget.cameraTarget != null) {
      _enqueue((controller) => _moveCamera(controller, widget.cameraTarget!));
    }
  }

  Future<void> _moveCamera(
    KakaoMapController controller,
    UserLocation target,
  ) => controller.moveCamera(
    CameraUpdate.newCenterPosition(
      LatLng(target.latitude, target.longitude),
      zoomLevel: 17,
    ),
    animation: const CameraAnimation(300),
  );

  void _enqueue(Future<void> Function(KakaoMapController) update) {
    final controller = _controller;
    if (controller == null) return;
    _updates = _updates
        .then((_) async {
          if (mounted && controller == _controller && _failure == null) {
            await update(controller);
          }
        })
        .catchError((Object error) {
          if (mounted && controller == _controller) _onError(error);
        });
  }

  void _queueUpdate() {
    final markers = _markers;
    if (markers == null) return;
    _enqueue(
      (_) => markers.update(
        groups: widget.groups,
        isLive: widget.isLive,
        location: widget.location,
        onSelectGroup: (id) => widget.onSelectGroup(id),
      ),
    );
  }

  Future<void> _positionLogo(KakaoMapController controller) =>
      controller.logo.changePosition(
        const MapGravity(HorizontalAlign.left, VerticalAlign.bottom),
        16,
        widget.contentPadding.bottom + 8,
      );

  void _onReady(KakaoMapController controller) {
    if (!mounted) return;
    _loadTimer?.cancel();
    _controller = controller;
    _markers = KakaoMapMarkers(
      controller,
      isActive: () => mounted && controller == _controller && _failure == null,
    );
    setState(() => _failure = null);
    _enqueue((controller) async {
      await _positionLogo(controller);
      await controller.scaleBar.hide();
      await controller.setBuildingHeightScale(0);
      await controller.setGesture(GestureType.rotate, false);
      await controller.setGesture(GestureType.tilt, false);
    });
    _queueUpdate();
    if (widget.cameraTarget != null) {
      _enqueue((controller) => _moveCamera(controller, widget.cameraTarget!));
    }
  }

  void _onError(Object error) {
    _loadTimer?.cancel();
    if (mounted) {
      setState(() => _failure = KakaoMapService.classifyError(error));
    }
  }

  void _retryTiles() {
    setState(() {
      _controller = null;
      _markers = null;
      _failure = null;
      _attempt++;
    });
    _startLoadTimer();
  }

  @override
  void dispose() {
    _loadTimer?.cancel();
    _controller = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _service,
    builder: (context, _) {
      if (_service.availability != MapAvailability.ready) {
        final message = switch (_service.availability) {
          MapAvailability.idle => '지도를 준비하고 있어요',
          MapAvailability.unconfigured => '학교 지도를 준비 중이에요',
          MapAvailability.unsupported => '학교 지도는 Android·iPhone 앱에서 볼 수 있어요',
          _ => '지도를 불러오지 못했어요',
        };
        return ColoredBox(
          color: const Color(0xFFF0F3F1),
          child: Center(
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                32,
                widget.contentPadding.top,
                32,
                widget.contentPadding.bottom,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.map_outlined,
                      size: 46,
                      color: Color(0xFF879B93),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      message,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      '화장실 위치와 칸 상태는 목록에서 확인할 수 있어요.',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    OutlinedButton(
                      onPressed: widget.onShowRestrooms,
                      child: const Text('층별 화장실 보기'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      }
      return Stack(
        fit: StackFit.expand,
        children: [
          KakaoMap(
            key: ValueKey(_attempt),
            option: const KakaoMapOption(
              position: LatLng(dimigoLatitude, dimigoLongitude),
              zoomLevel: 17,
            ),
            onMapReady: _onReady,
            onMapError: _onError,
            onTerrainClick: (_, _) => widget.onMapTapped(),
          ),
          if (_failure != null)
            Center(
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(switch (_failure!) {
                        MapFailure.quota =>
                          '지도 이용량을 모두 사용했어요.\n화장실 목록은 계속 이용할 수 있어요.',
                        MapFailure.authentication =>
                          '지도 연결 설정을 확인하고 있어요.\n화장실 목록을 이용해 주세요.',
                        MapFailure.connection => '지도 연결이 원활하지 않아요.',
                      }, textAlign: TextAlign.center),
                      if (_failure == MapFailure.connection)
                        TextButton(
                          onPressed: _retryTiles,
                          child: const Text('지도 다시 불러오기'),
                        ),
                      TextButton(
                        onPressed: widget.onShowRestrooms,
                        child: const Text('층별 화장실 보기'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      );
    },
  );
}
