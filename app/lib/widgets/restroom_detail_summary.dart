import 'package:flutter/material.dart';

import '../models/restroom.dart';
import '../utils/formatters.dart';
import 'restroom_floor_plan.dart';

class RestroomDetailSummary extends StatelessWidget {
  const RestroomDetailSummary({super.key, required this.restroom});
  final Restroom restroom;

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
    final occupied =
        restroom.totalStalls -
        restroom.availableStalls -
        restroom.unknownStalls;
    final status = restroom.totalStalls == 0
        ? '등록된 칸 없음'
        : restroom.unknownStalls == restroom.totalStalls
        ? '전체 ${restroom.totalStalls}칸 · 상태 미확인'
        : '${restroom.totalStalls}칸 중 $occupied칸 사용 중';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text.rich(
                TextSpan(
                  text: name,
                  children: [
                    TextSpan(
                      text: ' ($gender)',
                      style: const TextStyle(
                        color: Color(0xFF797979),
                        fontSize: 20,
                      ),
                    ),
                  ],
                ),
                style: const TextStyle(
                  color: Color(0xFF101010),
                  fontSize: 25,
                  fontWeight: FontWeight.w700,
                  height: 1.35,
                ),
              ),
              const SizedBox(height: 5),
              Wrap(
                spacing: 16,
                runSpacing: 4,
                children: [
                  Text(
                    restroom.distance == null
                        ? '거리 미확인'
                        : '직선 ${distanceLabel(restroom.distance)}',
                    style: const TextStyle(
                      color: Color(0xFF797979),
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    status,
                    style: TextStyle(
                      color: restroom.unknownStalls == restroom.totalStalls
                          ? RestroomFloorPlan.unknownColor
                          : occupied > 0
                          ? RestroomFloorPlan.occupiedColor
                          : RestroomFloorPlan.availableColor,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 26),
        _Metrics(
          values: [
            (label: '전체 칸 수', value: '${restroom.totalStalls}칸'),
            (
              label: '사용 중',
              value:
                  restroom.totalStalls > 0 &&
                      restroom.unknownStalls == restroom.totalStalls
                  ? '미확인'
                  : '$occupied칸',
            ),
            (
              label: '비데',
              value: restroom.bidetStalls == null
                  ? '미확인'
                  : '${restroom.bidetStalls}개',
            ),
          ],
        ),
        const SizedBox(height: 10),
        _Metrics(
          values: [
            (label: '사용 가능', value: '${restroom.availableStalls}칸'),
            (label: '상태 미확인', value: '${restroom.unknownStalls}칸'),
          ],
        ),
        if (restroom.accessibleStalls > 0) ...[
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.accessible_rounded,
                size: 18,
                color: Color(0xFF797979),
              ),
              const SizedBox(width: 5),
              Flexible(
                child: Text(
                  '장애인 이용 가능 ${restroom.accessibleStalls}칸 포함',
                  style: const TextStyle(
                    color: Color(0xFF797979),
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

class _Metrics extends StatelessWidget {
  const _Metrics({required this.values});
  final List<({String label, String value})> values;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(vertical: 18),
    decoration: BoxDecoration(
      border: Border.all(color: const Color(0xFFD1D1D1)),
      borderRadius: BorderRadius.circular(20),
    ),
    child: IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < values.length; i++) ...[
            if (i > 0)
              const VerticalDivider(
                color: Color(0xFFBDBDBD),
                width: 1,
                thickness: 1,
                indent: 2,
                endIndent: 2,
              ),
            Expanded(
              child: Semantics(
                label: '${values[i].label} ${values[i].value}',
                excludeSemantics: true,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: Column(
                    children: [
                      Text(
                        values[i].label,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Color(0xFF797979),
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 9),
                      Text(
                        values[i].value,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Color(0xFF797979),
                          fontSize: 23,
                          fontWeight: FontWeight.w700,
                          height: 1.25,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    ),
  );
}
