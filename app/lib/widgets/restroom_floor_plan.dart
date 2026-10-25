import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/stall.dart';

/// Schematic only: the API provides stall inventory, not surveyed coordinates
/// or counts of sinks/urinals. Every cubicle below represents one actual Stall.
class RestroomFloorPlan extends StatelessWidget {
  const RestroomFloorPlan({super.key, required this.stalls});

  final List<Stall> stalls;

  static const availableColor = Color(0xFF08BE7D);
  static const occupiedColor = Color(0xFFFF6469);
  static const unknownColor = Color(0xFF929AA3);

  @override
  Widget build(BuildContext context) {
    if (stalls.isEmpty) {
      return const SizedBox(
        height: 320,
        child: Center(child: Text('아직 등록된 칸이 없어요.')),
      );
    }
    // Keep the API's stall numbers (never derive them from array indices).
    // Accessible stalls sit nearest the schematic entrance, as in the design.
    final ordered = [...stalls]
      ..sort((a, b) {
        final accessible = (a.isAccessible == true ? 1 : 0).compareTo(
          b.isAccessible == true ? 1 : 0,
        );
        return accessible != 0
            ? accessible
            : a.stallNumber.compareTo(b.stallNumber);
      });
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final unit = width / 300;
        final rowHeight = math.max(
          80.0,
          80 + (MediaQuery.textScalerOf(context).scale(30) - 30) * 2,
        );
        final height = math.max(350.0, ordered.length * rowHeight + 24);
        final interiorHeight = height - 24;
        return Semantics(
          label: '화장실 약도, 전체 ${stalls.length}칸',
          explicitChildNodes: true,
          child: SizedBox(
            height: height,
            child: Stack(
              children: [
                Positioned.fill(
                  child: CustomPaint(
                    painter: _RoomPainter(stallCount: ordered.length),
                  ),
                ),
                Positioned(
                  left: 42 * unit,
                  top: 32,
                  width: 102 * unit,
                  child: const _SharedArea(),
                ),
                Positioned(
                  left: 39 * unit,
                  bottom: 50,
                  child: const Text(
                    '출입구',
                    style: TextStyle(
                      color: Color(0xFF7C8187),
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                for (var i = 0; i < ordered.length; i++)
                  Positioned(
                    left: 184 * unit,
                    right: 13 * unit,
                    top: 12 + interiorHeight * i / ordered.length,
                    height: interiorHeight / ordered.length,
                    child: _PlanStall(
                      key: ValueKey('plan-stall-${ordered[i].id}'),
                      stall: ordered[i],
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _PlanStall extends StatelessWidget {
  const _PlanStall({super.key, required this.stall});
  final Stall stall;

  @override
  Widget build(BuildContext context) {
    final color = switch (stall.occupied) {
      true => RestroomFloorPlan.occupiedColor,
      false => RestroomFloorPlan.availableColor,
      null => RestroomFloorPlan.unknownColor,
    };
    final status = switch (stall.occupied) {
      true => '사용 중',
      false => '사용 가능',
      null => '상태 미확인',
    };
    final bidet = switch (stall.hasBidet) {
      true => '비데 있음',
      false => '비데 없음',
      null => '비데 미확인',
    };
    final description =
        '${stall.stallNumber}번 칸, $status, $bidet'
        '${stall.isSimulated ? ', 테스트 상태' : ''}'
        '${stall.isAccessible == true ? ', 장애인 이용 가능 칸' : ''}';
    return Semantics(
      container: true,
      label: description,
      excludeSemantics: true,
      child: Tooltip(
        message: description,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              '${stall.stallNumber}번 칸',
              style: const TextStyle(
                fontSize: 10,
                height: 1.2,
                fontWeight: FontWeight.w600,
                color: Color(0xFF686C72),
              ),
            ),
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    color,
                    color.withValues(alpha: 0.85),
                    color.withValues(alpha: 0.08),
                  ],
                  stops: const [0.3, 0.64, 1],
                ),
              ),
              child: Center(
                child: stall.isAccessible == true
                    ? const Icon(
                        Icons.accessible_rounded,
                        color: Colors.white,
                        size: 27,
                      )
                    : const CustomPaint(
                        size: Size(26, 26),
                        painter: _ToiletPainter(),
                      ),
              ),
            ),
            if (stall.hasBidet != false)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    stall.hasBidet == true
                        ? Icons.water_drop_outlined
                        : Icons.help_outline_rounded,
                    size: 10,
                    color: const Color(0xFF606970),
                  ),
                  const SizedBox(width: 2),
                  Flexible(
                    child: Text(
                      stall.hasBidet == true ? '비데' : '비데 미확인',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 9,
                        height: 1.2,
                        color: Color(0xFF606970),
                      ),
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class RestroomPlanLegend extends StatelessWidget {
  const RestroomPlanLegend({super.key});

  @override
  Widget build(BuildContext context) => const Wrap(
    alignment: WrapAlignment.center,
    spacing: 16,
    runSpacing: 8,
    children: [
      _LegendItem(color: RestroomFloorPlan.availableColor, label: '사용 가능'),
      _LegendItem(color: RestroomFloorPlan.occupiedColor, label: '사용 중'),
      _LegendItem(color: RestroomFloorPlan.unknownColor, label: '미확인'),
    ],
  );
}

class _LegendItem extends StatelessWidget {
  const _LegendItem({required this.color, required this.label});
  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 7,
        height: 7,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
      const SizedBox(width: 5),
      Text(
        label,
        style: const TextStyle(fontSize: 11, color: Color(0xFF797979)),
      ),
    ],
  );
}

class _SharedArea extends StatelessWidget {
  const _SharedArea();

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(vertical: 10),
    decoration: BoxDecoration(
      color: const Color(0xFFEAECEE),
      border: Border.all(color: const Color(0xFFA8ACAF)),
      borderRadius: BorderRadius.circular(3),
    ),
    child: const Column(
      children: [
        Icon(Icons.wash_outlined, size: 25, color: Color(0xFF959A9F)),
        SizedBox(height: 4),
        Text('공용 공간', style: TextStyle(fontSize: 10, color: Color(0xFF7C8187))),
      ],
    ),
  );
}

class _RoomPainter extends CustomPainter {
  const _RoomPainter({required this.stallCount});
  final int stallCount;

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.width / 300;
    final height = size.height;
    // Work in a fixed horizontal grid; vertical spacing follows the inventory.
    canvas.save();
    canvas.scale(scale, 1);
    final room = Rect.fromLTRB(22, 8, 292, height - 8);
    canvas.drawRect(
      room.shift(const Offset(2, 3)),
      Paint()..color = const Color(0x22000000),
    );
    canvas.drawRect(room, Paint()..color = const Color(0xFFE2E3E4));

    canvas.save();
    canvas.clipRect(room);
    final tile = Paint()
      ..color = const Color(0xFFCFD2D5)
      ..strokeWidth = 0.7;
    for (double x = 22; x < 292; x += 26) {
      canvas.drawLine(Offset(x, 8), Offset(x, height - 8), tile);
    }
    for (double y = 8; y < height - 8; y += 26) {
      canvas.drawLine(Offset(22, y), Offset(292, y), tile);
    }
    canvas.restore();

    final wall = Paint()
      ..color = const Color(0xFF414548)
      ..strokeWidth = 10
      ..strokeCap = StrokeCap.square
      ..style = PaintingStyle.stroke;
    final entrance = height * 0.64;
    final outline = Path()
      ..moveTo(26, entrance - 32)
      ..lineTo(26, 12)
      ..lineTo(288, 12)
      ..lineTo(288, height - 12)
      ..lineTo(26, height - 12)
      ..lineTo(26, entrance + 32);
    canvas.drawPath(outline, wall);
    canvas.drawPath(
      outline,
      Paint()
        ..color = const Color(0xFF787C7F)
        ..strokeWidth = 1
        ..style = PaintingStyle.stroke,
    );

    final partition = Paint()
      ..color = const Color(0xFF8B9094)
      ..strokeWidth = 4
      ..style = PaintingStyle.stroke;
    final edge = Paint()
      ..color = const Color(0xFFF8F8F8)
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;
    final door = Paint()
      ..color = const Color(0xFF8B9094)
      ..strokeWidth = 1.2
      ..style = PaintingStyle.stroke;
    final rowHeight = (height - 24) / stallCount;
    for (var i = 0; i < stallCount; i++) {
      final top = 12 + i * rowHeight;
      final bottom = top + rowHeight;
      canvas.drawRect(
        Rect.fromLTRB(181, top + 2, 283, bottom - 2),
        Paint()..color = const Color(0x38FFFFFF),
      );
      // A short open door and its swing arc make each cubicle legible.
      final frame = Path()
        ..moveTo(180, top)
        ..lineTo(180, top + 8)
        ..moveTo(180, top + 37)
        ..lineTo(180, bottom)
        ..lineTo(285, bottom);
      canvas.drawPath(frame, partition);
      canvas.drawPath(frame, edge);
      canvas.drawLine(Offset(180, top + 8), Offset(201, top + 8), door);
      canvas.drawLine(Offset(180, top + 37), Offset(201, top + 8), door);
      canvas.drawArc(
        Rect.fromCircle(center: Offset(180, top + 8), radius: 29),
        0,
        math.pi / 2,
        false,
        door..color = const Color(0xFFB7BBBE),
      );
      door.color = const Color(0xFF8B9094);
    }
    canvas.drawLine(Offset(26, entrance + 32), Offset(82, entrance + 32), door);
    canvas.drawArc(
      Rect.fromCircle(center: Offset(26, entrance + 32), radius: 56),
      -math.pi / 2,
      math.pi / 2,
      false,
      door,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_RoomPainter oldDelegate) =>
      stallCount != oldDelegate.stallCount;
}

class _ToiletPainter extends CustomPainter {
  const _ToiletPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final pen = Paint()
      ..color = Colors.white
      ..strokeWidth = 1.7
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(5, 2, 11, 11),
        const Radius.circular(2),
      ),
      pen,
    );
    canvas.drawLine(const Offset(8, 6), const Offset(10, 6), pen);
    canvas.drawPath(
      Path()
        ..moveTo(5, 13)
        ..lineTo(22, 13)
        ..quadraticBezierTo(21, 19, 16, 19)
        ..lineTo(16, 22)
        ..lineTo(19, 22)
        ..lineTo(19, 24)
        ..lineTo(7, 24)
        ..lineTo(7, 22)
        ..lineTo(10, 22)
        ..lineTo(10, 19)
        ..quadraticBezierTo(5, 18, 5, 13),
      pen,
    );
  }

  @override
  bool shouldRepaint(_ToiletPainter oldDelegate) => false;
}
