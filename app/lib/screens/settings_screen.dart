import 'package:flutter/material.dart';

import '../config/app_config.dart';
import '../repositories/restroom_repository.dart';
import '../state/app_controller.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({
    super.key,
    required this.controller,
    required this.onChangeLocation,
  });
  final AppController controller;
  final VoidCallback onChangeLocation;

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
    children: [
      Text('설정', style: Theme.of(context).textTheme.headlineLarge),
      const SizedBox(height: 24),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.wc_rounded, size: 40),
              const SizedBox(height: 16),
              Text(
                AppConfig.appName,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 4),
              const Text('지금 필요한 빈칸을, 더 빠르게.'),
              const SizedBox(height: 16),
              const Text('버전 ${AppConfig.appVersion}'),
            ],
          ),
        ),
      ),
      const SizedBox(height: 24),
      Text('연결 정보', style: Theme.of(context).textTheme.titleLarge),
      const SizedBox(height: 12),
      Card(
        child: Column(
          children: [
            ListTile(
              leading: const Icon(Icons.cloud_outlined),
              title: const Text('Backend 연결'),
              subtitle: Text(
                controller.isMock
                    ? '데모 모드 · 서버에 연결하지 않음'
                    : controller.backendOnline
                    ? '연결됨'
                    : '연결할 수 없음',
              ),
            ),
            const Divider(height: 1, indent: 16, endIndent: 16),
            ListTile(
              leading: const Icon(Icons.sync_rounded),
              title: const Text('WebSocket 연결'),
              subtitle: Text(switch (controller.realtimeStatus) {
                RealtimeStatus.demo => '데모 모드 · 서버에 연결하지 않음',
                RealtimeStatus.connecting => '연결 중',
                RealtimeStatus.connected =>
                  controller.isRealtime ? '연결됨' : '연결됨 · 상태 동기화 중',
                RealtimeStatus.disconnected => '연결 끊김 · 자동으로 다시 연결합니다',
              }),
            ),
          ],
        ),
      ),
      const SizedBox(height: 24),
      Text('기준 위치', style: Theme.of(context).textTheme.titleLarge),
      const SizedBox(height: 12),
      Card(
        child: ListTile(
          contentPadding: const EdgeInsets.all(16),
          leading: const Icon(Icons.my_location_rounded),
          title: Text(controller.location.label),
          subtitle: Text(
            'X ${controller.location.x} m · Y ${controller.location.y} m',
          ),
          trailing: const Icon(Icons.edit_outlined),
          onTap: onChangeLocation,
        ),
      ),
      const SizedBox(height: 20),
      const Text('기준 위치는 직접 설정할 수 있어요. GPS 위치와 위치 권한은 사용하지 않습니다.'),
      if (controller.isMock) ...[
        const SizedBox(height: 12),
        const Text('데모의 화장실과 추천은 화면 확인을 위한 예시이며, 실제 센서나 과거 이용 통계가 아닙니다.'),
      ],
    ],
  );
}
