import 'package:flutter/material.dart';

import '../models/restroom_map_group.dart';
import '../state/app_controller.dart';
import 'restroom_list_card.dart';

Future<int?> showMapRestrooms(
  BuildContext context, {
  required AppController controller,
  String? groupId,
}) => showModalBottomSheet<int>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  showDragHandle: true,
  backgroundColor: Colors.white,
  builder: (context) => DraggableScrollableSheet(
    expand: false,
    initialChildSize: 0.55,
    minChildSize: 0.3,
    maxChildSize: 0.9,
    builder: (context, scrollController) => AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final groups = RestroomMapGroup.fromRestrooms(controller.restrooms);
        final selected = groups
            .where((group) => group.id == groupId)
            .firstOrNull;
        final rooms = groupId == null
            ? [...controller.restrooms]
            : [...?selected?.restrooms];
        rooms.sort((a, b) {
          final building = a.building.compareTo(b.building);
          if (building != 0) return building;
          final floor = a.floor.compareTo(b.floor);
          return floor != 0 ? floor : a.id.compareTo(b.id);
        });
        return ListView(
          controller: scrollController,
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
          children: [
            Text(
              selected == null ? '층별 화장실' : '${selected.title} 화장실',
              style: const TextStyle(fontSize: 23, fontWeight: FontWeight.w700),
            ),
            if (selected != null && rooms.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(selected.statusLabel(isLive: controller.isRealtime)),
            ],
            if (rooms.any(
              (room) => room.locationSource == 'school_reference',
            )) ...[
              const SizedBox(height: 12),
              const Text(
                '마커는 건물 위치를 안내해요. 화장실은 목록의 층을 확인해 주세요.',
                style: TextStyle(fontSize: 13, color: Color(0xFF6F7774)),
              ),
            ],
            const SizedBox(height: 18),
            if (controller.loading) const LinearProgressIndicator(),
            if (controller.listError != null) ...[
              Text(controller.listError!),
              TextButton(
                onPressed: controller.refresh,
                child: const Text('다시 시도'),
              ),
            ],
            if (!controller.loading &&
                controller.listError == null &&
                rooms.isEmpty)
              Text(
                selected == null
                    ? '표시할 화장실이 없어요.'
                    : '${selected.title} 화장실 정보를 준비 중이에요.',
              ),
            for (final room in rooms) ...[
              RestroomListCard(
                restroom: room,
                onTap: () => Navigator.of(context).pop(room.id),
              ),
              const SizedBox(height: 12),
            ],
            const SizedBox(height: 12),
            const Text(
              '건물 위치 © OpenStreetMap 기여자 · ODbL\n'
              'openstreetmap.org/copyright',
              style: TextStyle(fontSize: 11, color: Color(0xFF6F7774)),
            ),
          ],
        );
      },
    ),
  ),
);
