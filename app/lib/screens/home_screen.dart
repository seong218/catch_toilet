import 'package:flutter/material.dart';

import '../state/app_controller.dart';
import '../widgets/bidet_toggle.dart';
import '../widgets/connection_status.dart';
import '../widgets/message_card.dart';
import '../widgets/recommended_restroom_card.dart';
import '../widgets/restroom_card.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({
    super.key,
    required this.controller,
    required this.onOpenDetail,
    required this.onChangeLocation,
  });
  final AppController controller;
  final ValueChanged<int> onOpenDetail;
  final VoidCallback onChangeLocation;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return RefreshIndicator(
      onRefresh: controller.refresh,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('현재 기준 위치', style: text.bodySmall),
                    const SizedBox(height: 4),
                    Text(controller.location.label, style: text.titleLarge),
                  ],
                ),
              ),
              IconButton(
                onPressed: onChangeLocation,
                tooltip: '기준 위치 변경',
                icon: const Icon(Icons.my_location_rounded),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Text('지금, 어디로 갈까요?', style: text.headlineLarge),
          const SizedBox(height: 8),
          const Text('빈칸부터 확인하고 편하게 이동하세요.'),
          const SizedBox(height: 20),
          ConnectionStatus(controller: controller),
          const SizedBox(height: 20),
          if (controller.recommendationLoading &&
              controller.recommendation == null)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(36),
                child: Column(
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 16),
                    Text('추천 화장실을 확인하고 있어요'),
                  ],
                ),
              ),
            ),
          if (controller.recommendationLoading &&
              controller.recommendation != null)
            const Padding(
              padding: EdgeInsets.only(bottom: 8),
              child: LinearProgressIndicator(semanticsLabel: '추천 업데이트 중'),
            ),
          if (controller.recommendation != null)
            RecommendedRestroomCard(
              recommendation: controller.recommendation!,
              onTap: () => onOpenDetail(controller.recommendation!.restroom.id),
            ),
          if (!controller.recommendationLoading &&
              controller.recommendationError != null)
            MessageCard(
              message: controller.recommendationError!,
              icon: Icons.cloud_off_outlined,
              onRetry: controller.refreshRecommendation,
            ),
          if (!controller.recommendationLoading &&
              controller.recommendationEmpty != null)
            MessageCard(message: controller.recommendationEmpty!),
          const SizedBox(height: 16),
          BidetToggle(
            value: controller.bidetRequired,
            onChanged: controller.setBidetRequired,
          ),
          const SizedBox(height: 28),
          Row(
            children: [
              Expanded(child: Text('주변 화장실', style: text.titleLarge)),
              Text('${controller.restrooms.length}곳', style: text.bodyMedium),
            ],
          ),
          const SizedBox(height: 14),
          if (controller.loading) ...[
            const LinearProgressIndicator(semanticsLabel: '화장실 목록 불러오는 중'),
            const SizedBox(height: 16),
          ],
          if (controller.listError != null) ...[
            MessageCard(
              message: controller.listError!,
              icon: Icons.cloud_off_outlined,
              onRetry: controller.refresh,
            ),
            const SizedBox(height: 12),
          ],
          if (!controller.loading &&
              controller.listError == null &&
              controller.restrooms.isEmpty)
            const MessageCard(message: '아직 등록된 화장실이 없어요.'),
          for (final restroom in controller.restrooms) ...[
            RestroomCard(
              key: ValueKey('restroom-${restroom.id}'),
              restroom: restroom,
              onTap: () => onOpenDetail(restroom.id),
            ),
            const SizedBox(height: 12),
          ],
        ],
      ),
    );
  }
}
