import 'package:flutter/material.dart';

class RecommendationTabIcon extends StatelessWidget {
  const RecommendationTabIcon({super.key});

  @override
  Widget build(BuildContext context) => Transform.flip(
    // 7_.png places the large sparkle to the right of the two small ones.
    flipX: true,
    child: const Icon(Icons.auto_awesome_outlined),
  );
}
