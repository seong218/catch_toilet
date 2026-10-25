import 'dart:async';

import 'package:flutter/material.dart';

import '../state/app_controller.dart';
import '../widgets/message_card.dart';
import '../widgets/restroom_detail_summary.dart';
import '../widgets/restroom_floor_plan.dart';

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
      return Scaffold(
        backgroundColor: const Color(0xFFF2F7FF),
        body: SafeArea(
          bottom: false,
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: RefreshIndicator(
                onRefresh: () => controller.loadDetail(widget.restroomId),
                child: SingleChildScrollView(
                  key: PageStorageKey('restroom-detail-${widget.restroomId}'),
                  physics: const AlwaysScrollableScrollPhysics(),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const SizedBox(height: 12),
                      Stack(
                        children: [
                          Container(
                            margin: const EdgeInsets.symmetric(horizontal: 14),
                            padding: const EdgeInsets.fromLTRB(22, 12, 22, 18),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(24),
                            ),
                            child: restroom != null
                                ? Column(
                                    children: [
                                      RestroomFloorPlan(
                                        stalls: restroom.stalls ?? const [],
                                      ),
                                      if (restroom.totalStalls > 0) ...[
                                        const SizedBox(height: 12),
                                        const RestroomPlanLegend(),
                                      ],
                                    ],
                                  )
                                : SizedBox(
                                    height: 380,
                                    child: Center(
                                      child: error != null
                                          ? MessageCard(
                                              message: error,
                                              onRetry: () =>
                                                  controller.loadDetail(
                                                    widget.restroomId,
                                                  ),
                                            )
                                          : const CircularProgressIndicator(
                                              semanticsLabel: '약도를 불러오는 중',
                                            ),
                                    ),
                                  ),
                          ),
                          Positioned(
                            top: 12,
                            left: 24,
                            child: Material(
                              color: Colors.white,
                              elevation: 2,
                              shadowColor: const Color(0x33000000),
                              shape: const CircleBorder(),
                              child: BackButton(color: Colors.black),
                            ),
                          ),
                        ],
                      ),
                      if (restroom != null)
                        Container(
                          padding: EdgeInsets.fromLTRB(
                            24,
                            24,
                            24,
                            24 + MediaQuery.paddingOf(context).bottom,
                          ),
                          decoration: const BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.vertical(
                              top: Radius.circular(32),
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Color(0x14000000),
                                blurRadius: 12,
                                offset: Offset(0, -3),
                              ),
                            ],
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              RestroomDetailSummary(restroom: restroom),
                              const SizedBox(height: 18),
                              const Text(
                                '칸 정보 기준 약도예요. 실제 배치와 다를 수 있어요.',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: Color(0xFF8C929A),
                                  fontSize: 11,
                                ),
                              ),
                              if (loading) ...[
                                const SizedBox(height: 14),
                                const LinearProgressIndicator(
                                  semanticsLabel: '상세 정보 업데이트 중',
                                ),
                              ],
                              if (error != null) ...[
                                const SizedBox(height: 14),
                                const Text(
                                  '업데이트하지 못했어요. 마지막으로 확인한 정보예요.',
                                  style: TextStyle(
                                    color: Color(0xFF797979),
                                    fontSize: 12,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                MessageCard(
                                  message: error,
                                  onRetry: () =>
                                      controller.loadDetail(widget.restroomId),
                                ),
                              ],
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    },
  );
}
