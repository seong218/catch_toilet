import 'package:flutter/material.dart';

import '../models/restroom.dart';
import '../utils/formatters.dart';

/// A compact list entry that opens the restroom's live floor plan by ID.
class RestroomListCard extends StatelessWidget {
  const RestroomListCard({
    super.key,
    required this.restroom,
    required this.onTap,
  });

  final Restroom restroom;
  final VoidCallback onTap;

  bool get _crowded =>
      restroom.totalStalls > 0 &&
      restroom.unknownStalls == 0 &&
      restroom.availableStalls / restroom.totalStalls <= 0.2;

  bool get _spacious =>
      restroom.totalStalls > 0 &&
      restroom.availableStalls / restroom.totalStalls >= 0.7;

  Color get _statusColor {
    if (restroom.totalStalls == 0 || restroom.unknownStalls > 0) {
      return const Color(0xFF8291A5);
    }
    if (_crowded) return const Color(0xFFFF5C62);
    // Presentation only: these colors never affect Backend recommendations.
    return _spacious ? const Color(0xFF08BE7D) : const Color(0xFFFFB451);
  }

  String get _badgeLabel {
    if (restroom.totalStalls == 0) return '미등록';
    if (restroom.unknownStalls > 0) return '미확인';
    if (_crowded) return '혼잡';
    return _spacious ? '여유' : '보통';
  }

  String get _statusLabel {
    final total = restroom.totalStalls;
    if (total == 0) return '등록된 칸 없음';
    if (restroom.unknownStalls == total) return '전체 $total칸 · 상태 미확인';
    if (_crowded) {
      return '$total칸 중 ${total - restroom.availableStalls}칸 사용 중';
    }
    return '$total칸 중 ${restroom.availableStalls}칸 사용 가능';
  }

  @override
  Widget build(BuildContext context) {
    final gender = switch (restroom.gender) {
      'male' => '남자',
      'female' => '여자',
      _ => '공용',
    };
    final suffix = ' $gender 화장실';
    final name = restroom.name.endsWith(suffix)
        ? restroom.name.substring(0, restroom.name.length - suffix.length)
        : restroom.name;
    final color = _statusColor;
    final compact = MediaQuery.sizeOf(context).width < 360;
    final badgeColor = switch (_badgeLabel) {
      '여유' => const Color(0xFF298D69),
      '보통' => const Color(0xFFD89135),
      _ => color,
    };
    return Semantics(
      button: true,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          boxShadow: const [
            BoxShadow(
              color: Color(0x120E2340),
              blurRadius: 10,
              offset: Offset(0, 3),
            ),
          ],
        ),
        child: Material(
          color: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 100),
              child: Padding(
                padding: EdgeInsets.fromLTRB(compact ? 16 : 28, 20, 18, 20),
                child: Row(
                  children: [
                    ExcludeSemantics(
                      child: Container(
                        width: compact ? 40 : 48,
                        height: compact ? 40 : 48,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: RadialGradient(
                            colors: [
                              color,
                              color.withValues(alpha: 0.8),
                              color.withValues(alpha: 0.18),
                            ],
                            stops: const [0.25, 0.55, 1],
                          ),
                        ),
                        child: const Center(
                          child: CustomPaint(
                            size: Size(28, 28),
                            painter: _ToiletIconPainter(),
                          ),
                        ),
                      ),
                    ),
                    SizedBox(width: compact ? 12 : 20),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Text.rich(
                                  TextSpan(
                                    text: name,
                                    children: [
                                      TextSpan(
                                        text: ' ($gender)',
                                        style: const TextStyle(
                                          color: Color(0xFF797979),
                                        ),
                                      ),
                                    ],
                                  ),
                                  style: const TextStyle(
                                    color: Color(0xFF101010),
                                    fontSize: 17,
                                    fontWeight: FontWeight.w700,
                                    height: 1.4,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 3,
                                ),
                                decoration: BoxDecoration(
                                  color: color.withValues(alpha: 0.3),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Text(
                                  _badgeLabel,
                                  style: TextStyle(
                                    color: badgeColor,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    height: 1.5,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              Expanded(
                                child: Wrap(
                                  spacing: 9,
                                  runSpacing: 4,
                                  children: [
                                    Text(
                                      restroom.distance == null
                                          ? '거리 미확인'
                                          : '직선 ${distanceLabel(restroom.distance)}',
                                      style: const TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                        color: Color(0xFF797979),
                                      ),
                                    ),
                                    Text(
                                      _statusLabel,
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                        color: color,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 4),
                              const Icon(
                                Icons.chevron_right_rounded,
                                size: 22,
                                color: Color(0xFF797979),
                              ),
                            ],
                          ),
                          if (restroom.unknownStalls > 0 &&
                              restroom.unknownStalls < restroom.totalStalls)
                            Text(
                              '${restroom.unknownStalls}칸은 상태 미확인',
                              style: const TextStyle(
                                fontSize: 12,
                                color: Color(0xFF68778A),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ToiletIconPainter extends CustomPainter {
  const _ToiletIconPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final pen = Paint()
      ..color = Colors.white
      ..strokeWidth = 1.8
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(6, 3, 12, 12),
        const Radius.circular(2),
      ),
      pen,
    );
    canvas.drawLine(const Offset(9, 7), const Offset(11, 7), pen);
    canvas.drawPath(
      Path()
        ..moveTo(6, 15)
        ..lineTo(23, 15)
        ..quadraticBezierTo(22, 21, 17, 21)
        ..lineTo(17, 24)
        ..lineTo(20, 24)
        ..lineTo(20, 26)
        ..lineTo(8, 26)
        ..lineTo(8, 24)
        ..lineTo(11, 24)
        ..lineTo(11, 21)
        ..quadraticBezierTo(6, 20, 6, 15),
      pen,
    );
  }

  @override
  bool shouldRepaint(_ToiletIconPainter oldDelegate) => false;
}
