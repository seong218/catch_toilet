import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../state/app_controller.dart';
import '../utils/formatters.dart';

class RecommendationResult extends StatefulWidget {
  const RecommendationResult({
    super.key,
    required this.controller,
    required this.hasRequested,
    required this.onOpenDetail,
    required this.onRetry,
  });

  final AppController controller;
  final bool hasRequested;
  final ValueChanged<int> onOpenDetail;
  final VoidCallback onRetry;

  @override
  State<RecommendationResult> createState() => _RecommendationResultState();
}

class _RecommendationResultState extends State<RecommendationResult> {
  static const _blue = Color(0xFF2563FF);
  Widget? _lastResult;

  @override
  void didUpdateWidget(RecommendationResult oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.controller != oldWidget.controller) _lastResult = null;
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final awaitingResponse =
        widget.hasRequested &&
        (controller.recommendationLocating ||
            (controller.recommendationLoading &&
                !controller.hasRecommendationResponse));
    if (!awaitingResponse || _lastResult == null) {
      _lastResult = Container(
        constraints: const BoxConstraints(minHeight: 280),
        padding: const EdgeInsets.all(24),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(30),
        ),
        child: DefaultTextStyle(
          style: const TextStyle(
            color: Colors.black,
            fontSize: 14,
            height: 1.4,
          ),
          child: !widget.hasRequested || awaitingResponse
              ? const Text(
                  '조건을 선택하고\n추천 받기를 눌러 주세요.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Color(0xFF9099AA)),
                )
              : _content(),
        ),
      );
    }
    return IgnorePointer(
      ignoring: awaitingResponse,
      child: _lastResult ?? const SizedBox.shrink(),
    );
  }

  Widget _content() {
    final controller = widget.controller;
    final locationError = controller.recommendationLocationError;
    if (locationError != null) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.location_off_outlined,
            color: Color(0xFF8B98B0),
            size: 32,
          ),
          const SizedBox(height: 16),
          Text(locationError.message, textAlign: TextAlign.center),
          const SizedBox(height: 12),
          TextButton(onPressed: widget.onRetry, child: const Text('GPS 다시 확인')),
          if (locationError.openSettings)
            TextButton(
              onPressed: Geolocator.openAppSettings,
              child: const Text('기기 설정 열기'),
            ),
        ],
      );
    }
    final message =
        controller.recommendationError ?? controller.recommendationEmpty;
    if (message != null || controller.recommendation == null) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            controller.recommendationError != null
                ? Icons.cloud_off_outlined
                : Icons.info_outline_rounded,
            color: const Color(0xFF8B98B0),
            size: 32,
          ),
          const SizedBox(height: 16),
          Text(message ?? '추천할 화장실을 다시 확인해 주세요.', textAlign: TextAlign.center),
          const SizedBox(height: 12),
          TextButton(onPressed: widget.onRetry, child: const Text('다시 확인')),
        ],
      );
    }

    final recommendation = controller.recommendation!;
    final room = recommendation.restroom;
    final full = room.availableStalls == 0 && room.unknownStalls == 0;
    final pending =
        controller.recommendationLoading &&
        (controller.bidetRequired != controller.recommendationBidetRequired ||
            room.availableStalls == 0 ||
            (controller.bidetRequired && room.availableBidetStalls == 0));
    final rate = controller.recommendationBidetRequired
        ? recommendation.historicalBidetAvailabilityRate
        : recommendation.historicalAvailabilityRate;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          '지금 추천하는 화장실',
          style: TextStyle(color: _blue, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 10),
        Text(
          room.name,
          style: const TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w700,
            height: 1.25,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          '${room.building} · ${floorLabel(room.floor)}',
          style: const TextStyle(color: Color(0xFF777777)),
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 16,
          runSpacing: 8,
          children: [
            Text(
              '빈칸 ${room.availableStalls} / ${room.totalStalls}',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: full ? const Color(0xFFD84A4A) : _blue,
              ),
            ),
            Text('빈 비데 ${room.availableBidetStalls}칸'),
          ],
        ),
        const SizedBox(height: 8),
        Text('직선거리 ${distanceLabel(room.distance)}'),
        if (room.unknownStalls > 0)
          Text('아직 상태가 확인되지 않은 칸 ${room.unknownStalls}개'),
        const SizedBox(height: 12),
        Text(
          controller.recommendationWasFull
              ? '현재 모두 사용 중이에요.\n가장 가까운 화장실을 안내해요.'
              : recommendation.statisticsUsed
              ? '가까운 후보 중 과거 이용 통계를 반영했어요.'
              : '현재 빈칸과 거리로 추천했어요.',
        ),
        if (!controller.recommendationWasFull &&
            recommendation.statisticsUsed &&
            rate != null) ...[
          const SizedBox(height: 4),
          Text(
            '같은 요일·시간대 ${controller.recommendationBidetRequired ? '비데 ' : ''}빈칸 존재 비율 ${(rate * 100).round()}%',
            style: const TextStyle(color: Color(0xFF777777), fontSize: 12),
          ),
        ],
        const SizedBox(height: 12),
        TextButton.icon(
          onPressed: pending ? null : () => widget.onOpenDetail(room.id),
          icon: const Icon(Icons.arrow_forward_rounded, size: 20),
          label: const Text('칸별 상태 보기'),
          style: TextButton.styleFrom(foregroundColor: _blue),
        ),
      ],
    );
  }
}
