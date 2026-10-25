import 'package:flutter/material.dart';

import '../state/app_controller.dart';
import '../widgets/message_card.dart';
import '../widgets/restroom_list_card.dart';
import '../widgets/restroom_list_filters.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    required this.controller,
    required this.onOpenDetail,
  });
  final AppController controller;
  final ValueChanged<int> onOpenDetail;

  static const backgroundColor = Color(0xFFF2F7FF);

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool _bidetOnly = false;

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final restrooms = controller.restrooms.where((room) {
      if (_bidetOnly && room.availableBidetStalls == 0) return false;
      if (controller.accessibleOnly) {
        return room.availableStalls > 0 &&
            room.accessibleStalls > 0 &&
            controller.hasAvailableAccessibleStall(
              room.id,
              bidetRequired: _bidetOnly,
            );
      }
      return true;
    }).toList();
    return ColoredBox(
      color: HomeScreen.backgroundColor,
      child: Column(
        children: [
          RestroomListFilters(
            gender: controller.gender,
            accessibleOnly: controller.accessibleOnly,
            bidetOnly: _bidetOnly,
            onGenderChanged: controller.setGender,
            onAccessibleChanged: controller.setAccessibleOnly,
            onBidetChanged: (value) => setState(() => _bidetOnly = value),
          ),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final inset = constraints.maxWidth < 360 ? 20.0 : 28.0;
                return RefreshIndicator(
                  onRefresh: controller.refresh,
                  child: ListView(
                    key: const PageStorageKey('restroom-list'),
                    padding: EdgeInsets.fromLTRB(inset, 12, inset, 32),
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: [
                      if (controller.loading ||
                          controller.accessibleFilterLoading) ...[
                        LinearProgressIndicator(
                          semanticsLabel: controller.accessibleOnly
                              ? '장애인 칸 빈자리 확인 중'
                              : '화장실 목록 불러오는 중',
                        ),
                        const SizedBox(height: 16),
                      ],
                      if (controller.listError != null) ...[
                        MessageCard(
                          message: controller.listError!,
                          icon: Icons.cloud_off_outlined,
                          onRetry: controller.refresh,
                        ),
                        const SizedBox(height: 16),
                      ],
                      if (!controller.loading &&
                          !controller.accessibleFilterLoading &&
                          controller.listError == null &&
                          restrooms.isEmpty)
                        MessageCard(
                          message: controller.restrooms.isEmpty
                              ? '아직 등록된 화장실이 없어요.'
                              : '선택한 조건에 맞는 빈칸이 확인된 화장실이 없어요.\n필터를 해제해 다른 화장실을 확인하세요.',
                        ),
                      for (final restroom in restrooms) ...[
                        RestroomListCard(
                          key: ValueKey('restroom-${restroom.id}'),
                          restroom: restroom,
                          onTap: () => widget.onOpenDetail(restroom.id),
                        ),
                        const SizedBox(height: 16),
                      ],
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
