import 'package:flutter/material.dart';
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
      Text('더보기', style: Theme.of(context).textTheme.headlineLarge),
      const SizedBox(height: 24),
      Text('이용할 화장실', style: Theme.of(context).textTheme.titleLarge),
      const SizedBox(height: 12),
      SegmentedButton<String>(
        segments: const [
          ButtonSegment(
            value: 'male',
            label: Text('남자 화장실'),
            icon: Icon(Icons.man),
          ),
          ButtonSegment(
            value: 'female',
            label: Text('여자 화장실'),
            icon: Icon(Icons.woman),
          ),
        ],
        selected: {controller.gender},
        onSelectionChanged: (value) => controller.setGender(value.single),
      ),
      const SizedBox(height: 24),
      Text('내 위치', style: Theme.of(context).textTheme.titleLarge),
      const SizedBox(height: 12),
      Card(
        child: ListTile(
          contentPadding: const EdgeInsets.all(16),
          leading: const Icon(Icons.my_location_rounded),
          title: Text(controller.location.label),
          subtitle: Text(
            controller.location.isGps
                ? 'GPS로 확인한 위치'
                : 'GPS를 사용하면 내 위치에서 거리를 계산해요.',
          ),
          trailing: const Icon(Icons.chevron_right),
          onTap: onChangeLocation,
        ),
      ),
      const SizedBox(height: 16),
      const Text('현재 위치 가져오기를 누르면 위치 권한을 요청합니다. 위치는 주변 화장실의 거리를 계산할 때만 사용합니다.'),
      if (controller.isMock) ...[
        const SizedBox(height: 12),
        const Text('데모 화면의 사용 상태는 실제 센서 정보가 아닙니다.'),
      ],
    ],
  );
}
