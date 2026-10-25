import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import '../services/location_service.dart';

Future<UserLocation?> editLocation(
  BuildContext context,
  UserLocation current, {
  required LocationService service,
}) => showDialog<UserLocation>(
  context: context,
  builder: (_) => _LocationEditor(current: current, service: service),
);

class _LocationEditor extends StatefulWidget {
  const _LocationEditor({required this.current, required this.service});
  final UserLocation current;
  final LocationService service;
  @override
  State<_LocationEditor> createState() => _LocationEditorState();
}

class _LocationEditorState extends State<_LocationEditor> {
  late UserLocation _location = widget.current;
  late bool _hasSelection = widget.service.hasSelectedLocation;
  bool _loading = false;
  LocationFailure? _error;
  Future<void> _gps() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final value = await widget.service.currentGps(_location);
      if (mounted) {
        setState(() {
          _location = value;
          _hasSelection = true;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = error is LocationFailure
              ? error
              : const LocationFailure('위치를 확인하지 못했어요. 다시 시도해 주세요.'),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('내 위치'),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(_hasSelection ? _location.label : '현재 위치를 확인해 주세요.'),
          if (_location.accuracy != null)
            Text('위치 정확도 약 ${_location.accuracy!.round()}m'),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _loading ? null : _gps,
            icon: const Icon(Icons.my_location_rounded),
            label: Text(_loading ? '위치 확인 중…' : 'GPS로 현재 위치 가져오기'),
          ),
          if (_loading)
            const Padding(
              padding: EdgeInsets.only(top: 12),
              child: LinearProgressIndicator(),
            ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(_error!.message),
            ),
          if (_error?.openSettings == true)
            TextButton(
              onPressed: Geolocator.openAppSettings,
              child: const Text('기기 설정 열기'),
            ),
          TextButton(
            onPressed: _loading
                ? null
                : () => setState(() {
                    _location = UserLocation(
                      label: '디미고 본관 기준',
                      latitude: dimigoLatitude,
                      longitude: dimigoLongitude,
                    );
                    _error = null;
                    _hasSelection = true;
                  }),
            child: const Text('본관 기준 위치 사용'),
          ),
          const SizedBox(height: 16),
          const Text('GPS로 본관·신관·체육관까지의 거리를 확인해요. 층을 입력할 필요는 없습니다.'),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('취소'),
      ),
      FilledButton(
        onPressed: _loading || !_hasSelection
            ? null
            : () => Navigator.pop(context, _location),
        child: const Text('적용'),
      ),
    ],
  );
}
