import 'package:flutter/material.dart';

import '../config/app_theme.dart';
import '../models/restroom.dart';
import '../services/location_service.dart';
import '../services/map_projection.dart';

class LocationMap extends StatelessWidget {
  const LocationMap({
    super.key,
    required this.restrooms,
    required this.location,
    required this.onOpenDetail,
  });
  final List<Restroom> restrooms;
  final UserLocation location;
  final ValueChanged<int> onOpenDetail;

  @override
  Widget build(BuildContext context) {
    final projection = MapProjection(restrooms, location);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        height: 300,
        child: LayoutBuilder(
          builder: (context, box) => Stack(
            children: [
              Positioned.fill(child: CustomPaint(painter: _GridPainter())),
              const Positioned(
                left: 16,
                right: 16,
                top: 16,
                child: Text('위치 안내도 · 위쪽이 +Y'),
              ),
              Positioned(
                left: projection.horizontal(location.x) * (box.maxWidth - 48),
                top: projection.vertical(location.y) * 180 + 52,
                child: Tooltip(
                  message: '현재 기준 위치: ${location.label}',
                  child: Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: const Color(0xFFCDF58B),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: AppTheme.ink, width: 2),
                    ),
                    child: const Icon(
                      Icons.my_location_rounded,
                      semanticLabel: '현재 기준 위치',
                    ),
                  ),
                ),
              ),
              for (var i = 0; i < restrooms.length; i++)
                Positioned(
                  left:
                      projection.horizontal(restrooms[i].x) *
                      (box.maxWidth - 48),
                  top: projection.vertical(restrooms[i].y) * 180,
                  child: Tooltip(
                    message: restrooms[i].name,
                    child: Semantics(
                      label: '${restrooms[i].name} 상세 보기',
                      button: true,
                      child: SizedBox(
                        width: 48,
                        height: 48,
                        child: FilledButton(
                          style: FilledButton.styleFrom(
                            padding: EdgeInsets.zero,
                            backgroundColor: AppTheme.ink,
                          ),
                          onPressed: () => onOpenDetail(restrooms[i].id),
                          child: Text('${i + 1}'),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = const Color(0xFFEEF3EB),
    );
    final paint = Paint()
      ..color = const Color(0xFFD9E2D6)
      ..strokeWidth = 1;
    for (double x = 0; x < size.width; x += 28) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = 0; y < size.height; y += 28) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _GridPainter oldDelegate) => false;
}
