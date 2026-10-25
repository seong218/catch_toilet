import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:kakao_map_sdk/kakao_map_sdk.dart';

import '../models/restroom_map_group.dart';
import '../services/location_service.dart';

/// Presentation only: reuse native POIs and styles as live counts change.
class KakaoMapMarkers {
  KakaoMapMarkers(this.controller, {required this.isActive});

  final KakaoMapController controller;
  final bool Function() isActive;
  final _markers = <String, Poi>{};
  final _styles = <Color, PoiStyle>{};
  PoiStyle? _gpsStyle;
  Poi? _gpsMarker;

  Future<void> update({
    required List<RestroomMapGroup> groups,
    required bool isLive,
    required UserLocation location,
    required ValueChanged<String> onSelectGroup,
  }) async {
    final ids = groups.map((group) => group.id).toSet();
    for (final id in _markers.keys.where((id) => !ids.contains(id)).toList()) {
      if (!isActive()) return;
      await _markers[id]!.remove();
      _markers.remove(id);
    }
    for (final group in groups) {
      if (!isActive()) return;
      final color =
          !isLive ||
              group.totalStalls == 0 ||
              (group.availableStalls == 0 && group.unknownStalls > 0)
          ? const Color(0xFF8291A5)
          : group.availableStalls > 0
          ? const Color(0xFF27BF87)
          : const Color(0xFFFF676D);
      final style = _styles[color] ??= PoiStyle(
        icon: await _icon(color),
        textGravity: const MapGravity(
          HorizontalAlign.center,
          VerticalAlign.top,
        ),
        textStyle: [
          PoiTextStyle(
            // Native iOS label text renders smaller than Android's dp-scaled text.
            size: defaultTargetPlatform == TargetPlatform.iOS ? 28 : 12,
            color: const Color(0xFF3E484A),
            stroke: 2,
            strokeColor: Colors.white,
          ),
        ],
      );
      if (!isActive()) return;
      final caption = group.title;
      final existing = _markers[group.id];
      if (existing == null) {
        _markers[group.id] = await controller.labelLayer.addPoi(
          LatLng(group.latitude, group.longitude),
          id: group.id,
          style: style,
          text: caption,
          rank: 1,
          onClick: () => onSelectGroup(group.id),
        );
      } else {
        if (existing.style != style) await existing.changeStyles(style);
        if (!isActive()) return;
        if (existing.text != caption) await existing.changeText(caption);
      }
    }
    if (!isActive()) return;
    if (!location.isGps) {
      if (_gpsMarker?.visible == true) await _gpsMarker!.hide();
      return;
    }
    final position = LatLng(location.latitude, location.longitude);
    if (_gpsMarker == null) {
      _gpsStyle ??= PoiStyle(
        icon: await _icon(const Color(0xFF388CF0), isGps: true),
        anchor: const KPoint(0.5, 0.5),
      );
      if (!isActive()) return;
      _gpsMarker = await controller.labelLayer.addPoi(
        position,
        id: 'current-gps-location',
        style: _gpsStyle!,
        rank: 2,
      );
    } else {
      if (_gpsMarker!.position != position) await _gpsMarker!.move(position);
      if (!isActive()) return;
      if (!_gpsMarker!.visible) await _gpsMarker!.show();
    }
  }

  // Draw simple UI symbols locally; no downloaded icons or extra image requests.
  static Future<KImage> _icon(Color color, {bool isGps = false}) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder)..scale(3);
    final size = isGps ? const Size(22, 22) : const Size(34, 44);
    if (isGps) {
      canvas.drawCircle(
        const Offset(11, 11),
        11,
        Paint()..color = color.withValues(alpha: 0.18),
      );
      canvas.drawCircle(
        const Offset(11, 11),
        5.5,
        Paint()..color = Colors.white,
      );
      canvas.drawCircle(const Offset(11, 11), 4, Paint()..color = color);
    } else {
      final pin = Path()
        ..moveTo(17, 43)
        ..cubicTo(12, 35, 1, 27, 1, 17)
        ..cubicTo(1, -4, 33, -4, 33, 17)
        ..cubicTo(33, 27, 22, 35, 17, 43)
        ..close();
      canvas.drawPath(pin, Paint()..color = color);
      canvas.drawCircle(const Offset(17, 16), 6, Paint()..color = Colors.white);
    }
    final picture = recorder.endRecording();
    final image = await picture.toImage(
      (size.width * 3).toInt(),
      (size.height * 3).toInt(),
    );
    try {
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      // The iOS plugin creates a screen-scale UIImage, while the map renders
      // its pixels at 2x. Normalize so 3x iPhones do not enlarge the symbols.
      final nativeScale = defaultTargetPlatform == TargetPlatform.iOS
          ? 2 / ui.PlatformDispatcher.instance.views.first.devicePixelRatio
          : 1.0;
      final displaySize = isGps ? size : const Size(28, 36);
      return KImage.fromData(
        bytes!.buffer.asUint8List(),
        (displaySize.width * nativeScale).round(),
        (displaySize.height * nativeScale).round(),
      );
    } finally {
      image.dispose();
      picture.dispose();
    }
  }
}
