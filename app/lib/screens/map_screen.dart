import 'package:flutter/material.dart';

import '../state/app_controller.dart';
import '../widgets/connection_status.dart';
import '../widgets/location_map.dart';
import '../widgets/message_card.dart';
import '../widgets/restroom_card.dart';

class MapScreen extends StatelessWidget {
  const MapScreen({
    super.key,
    required this.controller,
    required this.onOpenDetail,
    required this.onChangeLocation,
  });
  final AppController controller;
  final ValueChanged<int> onOpenDetail;
  final VoidCallback onChangeLocation;

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
    children: [
      Text('주변을 한눈에', style: Theme.of(context).textTheme.headlineLarge),
      const SizedBox(height: 8),
      const Text('번호를 누르면 칸별 상태를 볼 수 있어요.'),
      const SizedBox(height: 20),
      ConnectionStatus(controller: controller),
      const SizedBox(height: 16),
      LocationMap(
        restrooms: controller.restrooms,
        location: controller.location,
        onOpenDetail: onOpenDetail,
      ),
      const SizedBox(height: 12),
      const Text('좌표를 이용한 안내도입니다. 실제 보행 경로와 층간 이동은 포함하지 않아요.'),
      const SizedBox(height: 16),
      Card(
        child: ListTile(
          contentPadding: const EdgeInsets.all(16),
          leading: const Icon(Icons.my_location_rounded),
          title: Text(controller.location.label),
          subtitle: const Text('현재 기준 위치'),
          trailing: const Icon(Icons.edit_location_alt_outlined),
          onTap: onChangeLocation,
        ),
      ),
      const SizedBox(height: 24),
      if (controller.loading) const LinearProgressIndicator(),
      if (controller.listError != null)
        MessageCard(
          message: controller.listError!,
          onRetry: controller.refresh,
        ),
      if (!controller.loading &&
          controller.listError == null &&
          controller.restrooms.isEmpty)
        const MessageCard(message: '아직 지도에 표시할 화장실이 없어요.'),
      for (var i = 0; i < controller.restrooms.length; i++) ...[
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            '위치 ${i + 1}',
            style: Theme.of(context).textTheme.labelLarge,
          ),
        ),
        RestroomCard(
          restroom: controller.restrooms[i],
          onTap: () => onOpenDetail(controller.restrooms[i].id),
        ),
        const SizedBox(height: 16),
      ],
    ],
  );
}
