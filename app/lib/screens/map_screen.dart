import 'package:flutter/material.dart';

import '../models/restroom.dart';
import '../models/restroom_map_group.dart';
import '../services/location_service.dart';
import '../state/app_controller.dart';
import '../utils/formatters.dart';
import '../widgets/location_map.dart';
import '../widgets/map_restroom_sheet.dart';

class MapScreen extends StatefulWidget {
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
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  final _search = TextEditingController();
  final _searchFocus = FocusNode();
  bool _searching = false;
  bool _locating = false;
  UserLocation? _cameraTarget;

  void _closeSearch() {
    _searchFocus.unfocus();
    setState(() => _searching = false);
  }

  Future<void> _showRestrooms([String? groupId]) async {
    _closeSearch();
    final id = await showMapRestrooms(
      context,
      controller: widget.controller,
      groupId: groupId,
    );
    if (mounted && id != null) widget.onOpenDetail(id);
  }

  Future<void> _locate() async {
    if (_locating) return;
    _closeSearch();
    setState(() => _locating = true);
    try {
      final location = await widget.controller.locationService.currentGps(
        widget.controller.location,
      );
      if (!mounted) return;
      setState(() => _cameraTarget = location);
      await widget.controller.setLocation(location);
    } on LocationFailure catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error.message),
          action: SnackBarAction(
            label: '위치 설정',
            onPressed: widget.onChangeLocation,
          ),
        ),
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('현재 위치를 가져오지 못했어요. 잠시 후 다시 시도해 주세요.')),
        );
      }
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  List<Restroom> get _results {
    final query = _search.text.trim().toLowerCase();
    return widget.controller.restrooms.where((room) {
      final gender = room.gender == 'male'
          ? '남자'
          : room.gender == 'female'
          ? '여자'
          : '공용';
      return '${room.name} ${room.building} ${floorLabel(room.floor)} $gender'
          .toLowerCase()
          .contains(query);
    }).toList();
  }

  @override
  void dispose() {
    _search.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final insets = MediaQuery.paddingOf(context);
    final groups = RestroomMapGroup.fromRestrooms(controller.restrooms);
    final results = _results;
    final notice = controller.listError != null
        ? '화장실 정보를 불러오지 못했어요'
        : controller.loading
        ? '화장실 정보를 확인하고 있어요'
        : controller.restrooms.isEmpty
        ? '아직 등록된 화장실이 없어요'
        : null;
    return Stack(
      fit: StackFit.expand,
      children: [
        LocationMap(
          groups: groups,
          location: controller.location,
          cameraTarget: _cameraTarget,
          isLive: controller.isRealtime && !controller.hasSimulatedData,
          onSelectGroup: _showRestrooms,
          onShowRestrooms: _showRestrooms,
          onMapTapped: _closeSearch,
          contentPadding: EdgeInsets.fromLTRB(
            12,
            insets.top + 88,
            12,
            insets.bottom + 10,
          ),
        ),
        Positioned(
          top: insets.top + 16,
          left: 30,
          right: 30,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Material(
                color: Colors.white,
                elevation: 4,
                shadowColor: const Color(0x24000000),
                borderRadius: BorderRadius.circular(32),
                child: TextField(
                  key: const ValueKey('map-search'),
                  controller: _search,
                  focusNode: _searchFocus,
                  onTap: () => setState(() => _searching = true),
                  onChanged: (_) => setState(() => _searching = true),
                  onSubmitted: (_) => _searchFocus.unfocus(),
                  textInputAction: TextInputAction.search,
                  style: const TextStyle(
                    fontSize: 16,
                    color: Color(0xFF303030),
                  ),
                  decoration: InputDecoration(
                    hintText: '화장실을 검색해보세요',
                    hintStyle: const TextStyle(
                      color: Color(0xFF929292),
                      fontSize: 16,
                    ),
                    prefixIcon: const Padding(
                      padding: EdgeInsets.only(left: 10),
                      child: Icon(
                        Icons.search,
                        color: Color(0xFF808080),
                        size: 26,
                      ),
                    ),
                    suffixIcon: _searching
                        ? IconButton(
                            tooltip: '검색 닫기',
                            onPressed: () {
                              _search.clear();
                              _closeSearch();
                            },
                            icon: const Icon(Icons.close, size: 20),
                          )
                        : null,
                    contentPadding: const EdgeInsets.symmetric(
                      vertical: 16,
                      horizontal: 12,
                    ),
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                  ),
                ),
              ),
              if (_searching) ...[
                const SizedBox(height: 10),
                Material(
                  color: Colors.white,
                  elevation: 3,
                  borderRadius: BorderRadius.circular(20),
                  clipBehavior: Clip.antiAlias,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxHeight: MediaQuery.sizeOf(context).height * 0.32,
                    ),
                    child: ListView(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      shrinkWrap: true,
                      children: [
                        if (results.isEmpty)
                          const Padding(
                            padding: EdgeInsets.all(18),
                            child: Text('검색 결과가 없어요. 건물이나 층 이름으로 찾아보세요.'),
                          ),
                        for (final room in results)
                          ListTile(
                            title: Text(room.name),
                            subtitle: Text(room.availabilityLabel),
                            leading: const Icon(Icons.wc_outlined),
                            onTap: () {
                              _closeSearch();
                              widget.onOpenDetail(room.id);
                            },
                          ),
                      ],
                    ),
                  ),
                ),
              ] else if (notice != null) ...[
                const SizedBox(height: 10),
                Material(
                  color: Colors.white.withValues(alpha: 0.95),
                  borderRadius: BorderRadius.circular(14),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            notice,
                            style: const TextStyle(fontSize: 12),
                          ),
                        ),
                        if (controller.listError != null)
                          IconButton(
                            tooltip: '화장실 정보 다시 불러오기',
                            onPressed: controller.refresh,
                            icon: const Icon(Icons.refresh, size: 20),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        Positioned(
          bottom: insets.bottom + 42,
          left: 24,
          child: FloatingActionButton.small(
            heroTag: 'map-floors',
            tooltip: '층별 화장실',
            backgroundColor: Colors.white,
            foregroundColor: Colors.black,
            shape: const CircleBorder(),
            onPressed: _showRestrooms,
            child: const Icon(Icons.layers_outlined),
          ),
        ),
        Positioned(
          bottom: insets.bottom + 24,
          right: 24,
          child: FloatingActionButton.small(
            heroTag: 'map-location',
            tooltip: '현재 위치로 이동',
            backgroundColor: Colors.white,
            foregroundColor: Colors.black,
            shape: const CircleBorder(),
            onPressed: _locating ? null : _locate,
            child: _locating
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.near_me, size: 24),
          ),
        ),
      ],
    );
  }
}
