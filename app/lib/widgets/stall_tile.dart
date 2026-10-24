import 'package:flutter/material.dart';

import '../models/stall.dart';

class StallTile extends StatelessWidget {
  const StallTile({super.key, required this.stall});
  final Stall stall;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(18),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: stall.occupied
                  ? const Color(0xFFF1EDE7)
                  : const Color(0xFFDDEFE2),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(
              stall.occupied
                  ? Icons.lock_outline_rounded
                  : Icons.check_circle_outline_rounded,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${stall.stallNumber}번 칸',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 2),
                Text(stall.occupied ? '사용 중' : '사용 가능'),
                if (stall.hasBidet) const Text('비데 있음'),
              ],
            ),
          ),
          if (stall.hasBidet)
            const Tooltip(
              message: '비데 있음',
              child: Icon(Icons.water_drop_outlined),
            ),
        ],
      ),
    ),
  );
}
