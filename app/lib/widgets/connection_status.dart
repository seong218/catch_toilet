import 'package:flutter/material.dart';

import '../repositories/restroom_repository.dart';
import '../state/app_controller.dart';

class ConnectionStatus extends StatelessWidget {
  const ConnectionStatus({super.key, required this.controller});
  final AppController controller;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
    decoration: BoxDecoration(
      color: const Color(0xFFEBEFE8),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.info_outline_rounded, size: 18),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            controller.isMock
                ? '데모 · 실제 이용 정보가 아닙니다'
                : controller.isRealtime
                ? '실시간 연결됨 · 센서 변경을 반영하고 있어요'
                : controller.realtimeStatus == RealtimeStatus.connected
                ? '최신 상태 확인 중 · 잠시 기다려 주세요'
                : '실시간 연결 끊김 · 마지막으로 확인한 정보예요',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
      ],
    ),
  );
}
