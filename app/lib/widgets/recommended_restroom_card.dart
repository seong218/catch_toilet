import 'package:flutter/material.dart';

import '../config/app_theme.dart';
import '../models/recommendation.dart';
import '../utils/formatters.dart';

class RecommendedRestroomCard extends StatelessWidget {
  const RecommendedRestroomCard({
    super.key,
    required this.recommendation,
    required this.onTap,
  });
  final Recommendation recommendation;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final restroom = recommendation.restroom;
    return Card(
      color: AppTheme.ink,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: DefaultTextStyle(
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              height: 1.5,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(
                      Icons.near_me_outlined,
                      color: Color(0xFFCDF58B),
                      size: 20,
                    ),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '지금 추천하는 화장실',
                        style: TextStyle(color: Color(0xFFCDF58B)),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                Text(
                  restroom.name,
                  style: const TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w700,
                    height: 1.25,
                  ),
                ),
                const SizedBox(height: 6),
                Text('${restroom.building} · ${floorLabel(restroom.floor)}'),
                const SizedBox(height: 24),
                Wrap(
                  spacing: 10,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      '${restroom.availableStalls}',
                      style: const TextStyle(
                        fontSize: 56,
                        fontWeight: FontWeight.w800,
                        height: 1.1,
                      ),
                    ),
                    Text('/ ${restroom.totalStalls}칸 사용 가능'),
                  ],
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 20,
                  runSpacing: 8,
                  children: [
                    Text('↗ ${distanceLabel(restroom.distance)}'),
                    Text('비데 빈칸 ${restroom.availableBidetStalls}개'),
                  ],
                ),
                if (restroom.availableStalls == 0) ...[
                  const SizedBox(height: 16),
                  const Text(
                    '지금은 모든 칸이 사용 중이에요.\n가장 가까운 화장실을 안내해 드려요.',
                    style: TextStyle(color: Color(0xFFFFDEA8)),
                  ),
                ],
                if (recommendation.statisticsUsed &&
                    restroom.availableStalls > 0) ...[
                  const SizedBox(height: 16),
                  const Text(
                    '평소 이 시간대에 빈칸이 자주 있어요',
                    style: TextStyle(color: Color(0xFFCDF58B)),
                  ),
                ],
                const SizedBox(height: 24),
                const Divider(color: Color(0xFF496A60), height: 1),
                const SizedBox(height: 18),
                const Row(
                  children: [
                    Expanded(child: Text('칸별 상태 보기')),
                    Icon(
                      Icons.arrow_forward_rounded,
                      color: Colors.white,
                      size: 20,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
