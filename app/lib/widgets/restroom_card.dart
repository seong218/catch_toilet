import 'package:flutter/material.dart';

import '../models/restroom.dart';
import '../utils/formatters.dart';

class RestroomCard extends StatelessWidget {
  const RestroomCard({super.key, required this.restroom, required this.onTap});
  final Restroom restroom;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Card(
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        restroom.name,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${restroom.building} · ${floorLabel(restroom.floor)}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                const Icon(Icons.chevron_right_rounded),
              ],
            ),
            const SizedBox(height: 20),
            Wrap(
              spacing: 16,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  restroom.availableStalls == 0
                      ? '현재 빈칸 없음'
                      : '빈칸 ${restroom.availableStalls} / ${restroom.totalStalls}',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                Text(distanceLabel(restroom.distance)),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              '비데 빈칸 ${restroom.availableBidetStalls}개 · 전체 ${restroom.totalStalls}칸',
            ),
          ],
        ),
      ),
    ),
  );
}
