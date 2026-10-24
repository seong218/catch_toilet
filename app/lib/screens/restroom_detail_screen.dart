import 'dart:async';

import 'package:flutter/material.dart';

import '../models/stall.dart';
import '../state/app_controller.dart';
import '../utils/formatters.dart';
import '../widgets/connection_status.dart';
import '../widgets/message_card.dart';
import '../widgets/stall_tile.dart';

class RestroomDetailScreen extends StatefulWidget {
  const RestroomDetailScreen({
    super.key,
    required this.controller,
    required this.restroomId,
  });
  final AppController controller;
  final int restroomId;

  @override
  State<RestroomDetailScreen> createState() => _RestroomDetailScreenState();
}

class _RestroomDetailScreenState extends State<RestroomDetailScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(widget.controller.openDetail(widget.restroomId));
    });
  }

  @override
  void dispose() {
    widget.controller.closeDetail(widget.restroomId);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.controller,
    builder: (context, _) {
      final controller = widget.controller;
      final restroom = controller.details[widget.restroomId];
      final error = controller.detailErrors[widget.restroomId];
      final loading = controller.loadingDetails.contains(widget.restroomId);
      final text = Theme.of(context).textTheme;
      return Scaffold(
        appBar: AppBar(title: const Text('화장실 상세')),
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: RefreshIndicator(
                onRefresh: () => controller.loadDetail(widget.restroomId),
                child: ListView(
                  padding: const EdgeInsets.all(20),
                  physics: const AlwaysScrollableScrollPhysics(),
                  children: [
                    ConnectionStatus(controller: controller),
                    const SizedBox(height: 24),
                    if (loading) ...[
                      const LinearProgressIndicator(
                        semanticsLabel: '상세 정보 불러오는 중',
                      ),
                      const SizedBox(height: 20),
                    ],
                    if (error != null) ...[
                      MessageCard(
                        message: error,
                        onRetry: () => controller.loadDetail(widget.restroomId),
                      ),
                      const SizedBox(height: 20),
                    ],
                    if (restroom != null) ...[
                      Text(restroom.name, style: text.headlineLarge),
                      const SizedBox(height: 8),
                      Text(
                        '${restroom.building} · ${floorLabel(restroom.floor)}',
                      ),
                      const SizedBox(height: 24),
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('현재 빈칸'),
                              const SizedBox(height: 8),
                              Text(
                                '${restroom.availableStalls} / ${restroom.totalStalls}',
                                style: text.headlineLarge,
                              ),
                              const SizedBox(height: 16),
                              Wrap(
                                spacing: 24,
                                runSpacing: 12,
                                children: [
                                  Text(
                                    '거리 ${distanceLabel(restroom.distance)}',
                                  ),
                                  Text(
                                    '비데 빈칸 ${restroom.availableBidetStalls}개',
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 28),
                      Text('칸 현황', style: text.titleLarge),
                      const SizedBox(height: 6),
                      const Text('사용 가능 여부와 비데를 함께 확인하세요.'),
                      const SizedBox(height: 16),
                      if (restroom.stalls?.isEmpty ?? true)
                        const MessageCard(message: '아직 등록된 칸이 없어요.'),
                      for (final stall in restroom.stalls ?? <Stall>[]) ...[
                        StallTile(stall: stall),
                        const SizedBox(height: 10),
                      ],
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    },
  );
}
