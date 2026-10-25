import 'dart:async';
import 'package:catchy_toilet/models/restroom.dart';
import 'package:catchy_toilet/models/restroom_map_group.dart';
import 'package:catchy_toilet/models/stall_update.dart';
import 'package:catchy_toilet/repositories/mock_restroom_repository.dart';
import 'package:catchy_toilet/repositories/restroom_repository.dart';
import 'package:catchy_toilet/screens/map_screen.dart';
import 'package:catchy_toilet/services/kakao_map_service.dart';
import 'package:catchy_toilet/services/location_service.dart';
import 'package:catchy_toilet/state/app_controller.dart';
import 'package:catchy_toilet/widgets/location_map.dart';
import 'package:catchy_toilet/widgets/kakao_map_markers.dart';
import 'package:catchy_toilet/widgets/restroom_list_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kakao_map_sdk/kakao_map_sdk.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'missing map key makes no SDK call; concurrent starts initialize once',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      final sdk = RecordingMapSdk();
      final missing = KakaoMapService(nativeAppKey: '', sdk: sdk);
      addTearDown(missing.dispose);
      await missing.initialize();
      expect(missing.availability, MapAvailability.unconfigured);
      expect(sdk.calls, 0);
      final configured = KakaoMapService(
        nativeAppKey: 'test-only-key',
        sdk: sdk,
      );
      addTearDown(configured.dispose);
      await Future.wait([configured.initialize(), configured.initialize()]);
      expect(configured.availability, MapAvailability.ready);
      expect(sdk.calls, 1);
    },
  );
  test(
    'SDK failure has no automatic retry and quota is distinct from network',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      final sdk = RecordingMapSdk()..fail = true;
      final service = KakaoMapService(nativeAppKey: 'test-only-key', sdk: sdk);
      addTearDown(service.dispose);
      await service.initialize();
      await service.initialize();
      expect(service.availability, MapAvailability.failed);
      expect(sdk.calls, 1);
      expect(
        KakaoMapService.classifyError(KakaoAuthError(429, null)),
        MapFailure.quota,
      );
      expect(
        KakaoMapService.classifyError(KakaoAuthError(401, null)),
        MapFailure.authentication,
      );
      expect(
        KakaoMapService.classifyError(KakaoAuthError(499, null)),
        MapFailure.connection,
      );
    },
  );
  testWidgets(
    'native marker updates reuse POIs; reference location is not GPS',
    (tester) async {
      const overlayChannel = MethodChannel('test/kakao/overlays');
      final calls = <MethodCall>[];
      var styleId = 0;
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(overlayChannel, (call) async {
        calls.add(call);
        if (call.method == 'addPoiStyle') return 'style-${styleId++}';
        if (call.method == 'addPoi') {
          return (call.arguments as Map)['poi']['id'];
        }
        return null;
      });
      addTearDown(
        () => messenger.setMockMethodCallHandler(overlayChannel, null),
      );
      final controller = KakaoMapControllerImplement(
        const MethodChannel('test/kakao/view'),
        overlayChannel: overlayChannel,
      );
      var active = true;
      final markers = KakaoMapMarkers(controller, isActive: () => active);
      String? selected;
      final reference = LocationService().current;
      Future<void> update(
        List<Restroom> rooms, {
        UserLocation? location,
        bool isLive = true,
      }) => markers.update(
        groups: RestroomMapGroup.fromRestrooms(rooms),
        isLive: isLive,
        location: location ?? reference,
        onSelectGroup: (id) => selected = id,
      );
      await tester.runAsync(() async {
        await update([room(1, unknown: 2), room(2, unknown: 2)]);
        expect(controller.labelLayer.poiCount, 5);
        final groupId = RestroomMapGroup.fromRestrooms([room(1)]).first.id;
        final marker = controller.labelLayer.getPoi(groupId)!;
        marker.onClick!();
        expect(selected, groupId);
        expect(marker.text, '본관');
        final unknownStyle = marker.style;
        await update([room(1, available: 1), room(2)]);
        expect(controller.labelLayer.getPoi(groupId), same(marker));
        expect(marker.text, '본관');
        expect(marker.style, isNot(same(unknownStyle)));
        await update([room(1, available: 1), room(2)], isLive: false);
        expect(marker.style, same(unknownStyle));
        expect(calls.where((call) => call.method == 'addPoi'), hasLength(5));
        await update(
          [room(1)],
          location: const UserLocation(
            label: 'GPS',
            latitude: 37.34,
            longitude: 126.83,
            isGps: true,
          ),
        );
        expect(
          controller.labelLayer.getPoi('current-gps-location')!.visible,
          isTrue,
        );
        final gps = controller.labelLayer.getPoi('current-gps-location')!;
        expect(gps.style.anchor, const KPoint(0.5, 0.5));
        expect(gps.style.icon!.width, 22);
        expect(gps.style.icon!.height, 22);
        await update([]);
        expect(controller.labelLayer.getPoi(groupId), same(marker));
        expect(
          controller.labelLayer.getPoi('current-gps-location')!.visible,
          isFalse,
        );
        await markers.update(
          groups: [],
          isLive: true,
          location: reference,
          onSelectGroup: (_) {},
        );
        expect(controller.labelLayer.getPoi(groupId), isNull);
        active = false;
        final before = calls.length;
        await update([room(1)]);
        expect(calls.length, before);
      });
    },
  );
  test(
    'five campus buildings group floors by name, independent of API GPS',
    () {
      final groups = RestroomMapGroup.fromRestrooms([
        room(2, floor: 2),
        room(1, floor: -1),
        room(3, latitude: null),
        room(4, latitude: 37.342),
        room(5, building: '신관', available: 1),
        room(6, building: '정보기술문화센터 (신관)'),
        room(7, building: '미등록 별관'),
      ]);
      expect(groups.map((group) => group.title), [
        '본관',
        '신관',
        '우정학사',
        '학봉관',
        '체육관',
      ]);
      expect(groups.map((group) => group.id).toSet(), hasLength(5));
      expect(
        groups.map((group) => (group.latitude, group.longitude)).toSet(),
        hasLength(5),
      );
      expect(groups.first.restrooms.map((room) => room.id), [1, 3, 4, 2]);
      expect(groups[1].restrooms.map((room) => room.id), [5, 6]);
      expect(groups.first.availableStalls, 0);
      expect(groups[1].availableStalls, 1);
      // The building display point must not overwrite the API location.
      expect(groups.first.restrooms.first.latitude, dimigoLatitude);
      expect(groups.first.restrooms[1].latitude, isNull);
      expect(groups.first.isSchoolReference, isTrue);
      expect(groups[2].restrooms, isEmpty);
      expect(groups[2].statusLabel(isLive: true), '화장실 정보 준비 중');
      expect(RestroomMapGroup.fromRestrooms([]), hasLength(5));
    },
  );
  test('unknown and disconnected states never become full or available', () {
    RestroomMapGroup group(Restroom room) =>
        RestroomMapGroup.fromRestrooms([room]).first;
    expect(group(room(1, unknown: 2)).statusLabel(isLive: true), '상태 미확인');
    expect(group(room(1)).statusLabel(isLive: true), '현재 만석');
    expect(
      group(room(1, available: 1, unknown: 1)).statusLabel(isLive: true),
      '빈칸 1칸 · 미확인 1칸',
    );
    expect(
      group(room(1, available: 2)).statusLabel(isLive: false),
      '최신 상태 확인 필요',
    );
  });
  testWidgets(
    'local search opens the matching ID without fetching or recreating map',
    (tester) async {
      final repo = MapRepository();
      final controller = AppController(repo);
      addTearDown(controller.dispose);
      int? opened;
      await mountMap(tester, controller, onOpen: (id) => opened = id);
      final state = tester.state(find.byType(LocationMap));
      final requests = repo.listRequests;
      expect(find.text('학교 지도를 준비 중이에요'), findsOneWidget);
      await tester.enterText(find.byKey(const ValueKey('map-search')), '2층');
      await tester.pumpAndSettle();
      expect(find.text('본관 2층 남자 화장실'), findsOneWidget);
      expect(find.text('본관 1층 남자 화장실'), findsNothing);
      await tester.tap(find.text('본관 2층 남자 화장실'));
      await tester.pumpAndSettle();
      expect(opened, 2);
      expect(repo.listRequests, requests);
      expect(tester.state(find.byType(LocationMap)), same(state));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'open floor sheet follows sensor updates and selects the original ID',
    (tester) async {
      final repo = MapRepository();
      final controller = AppController(repo);
      addTearDown(controller.dispose);
      int? opened;
      await mountMap(tester, controller, onOpen: (id) => opened = id);
      final mapState = tester.state(find.byType(LocationMap));
      final map = tester.widget<LocationMap>(find.byType(LocationMap));
      map.onSelectGroup(map.groups.first.id);
      await tester.pumpAndSettle();
      expect(find.byType(RestroomListCard), findsNWidgets(2));
      expect(find.text('전체 2칸 · 상태 미확인'), findsNWidgets(2));
      repo.events.add(
        const StallUpdate(
          restroomId: 1,
          stallId: 1,
          occupied: false,
          totalStalls: 2,
          availableStalls: 1,
          availableBidetStalls: 0,
          unknownStalls: 1,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('2칸 중 1칸 사용 가능'), findsOneWidget);
      await tester.tap(
        find.byWidgetPredicate(
          (widget) => widget is RestroomListCard && widget.restroom.id == 1,
        ),
      );
      await tester.pumpAndSettle();
      expect(opened, 1);
      expect(tester.state(find.byType(LocationMap)), same(mapState));
      expect(
        tester
            .widget<LocationMap>(find.byType(LocationMap))
            .groups
            .first
            .availableStalls,
        1,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets('an unregistered building opens its own empty sheet', (
    tester,
  ) async {
    final controller = AppController(MapRepository());
    addTearDown(controller.dispose);
    await mountMap(tester, controller);
    final map = tester.widget<LocationMap>(find.byType(LocationMap));
    expect(map.groups, hasLength(5));
    map.onSelectGroup(
      map.groups.singleWhere((group) => group.title == '체육관').id,
    );
    await tester.pumpAndSettle();
    expect(find.text('체육관 화장실'), findsOneWidget);
    expect(find.text('체육관 화장실 정보를 준비 중이에요.'), findsOneWidget);
    expect(find.byType(RestroomListCard), findsNothing);
    expect(find.text('현재 만석'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
    'GPS failure preserves reference; success updates camera and API location',
    (tester) async {
      var fail = true;
      final service = LocationService(
        gpsReader: (_) async {
          if (fail) throw const LocationFailure('위치 권한이 없어요.');
          return const UserLocation(
            label: '현재 GPS 위치',
            latitude: 37.34,
            longitude: 126.83,
            isGps: true,
            accuracy: 8,
          );
        },
      );
      final controller = AppController(
        MapRepository(),
        locationService: service,
      );
      addTearDown(controller.dispose);
      await mountMap(tester, controller);
      final original = controller.location;
      await tester.tap(find.byTooltip('현재 위치로 이동'));
      await tester.pumpAndSettle();
      expect(controller.location, same(original));
      expect(find.text('위치 권한이 없어요.'), findsOneWidget);
      ScaffoldMessenger.of(
        tester.element(find.byType(MapScreen)),
      ).hideCurrentSnackBar();
      await tester.pumpAndSettle();
      fail = false;
      await tester.tap(find.byTooltip('현재 위치로 이동'));
      await tester.pumpAndSettle();
      expect(controller.location.isGps, isTrue);
      expect(
        tester
            .widget<LocationMap>(find.byType(LocationMap))
            .cameraTarget
            ?.latitude,
        37.34,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}

class RecordingMapSdk implements KakaoMapSdk {
  int calls = 0;
  bool fail = false;
  @override
  Future<void> initialize(String appKey) async {
    calls++;
    if (fail) throw StateError('test SDK failure');
  }

  @override
  Future<bool> isInitialize() async => calls > 0 && !fail;
  @override
  Future<String?> hashKey() async => null;
}

Future<void> mountMap(
  WidgetTester tester,
  AppController controller, {
  ValueChanged<int>? onOpen,
}) async {
  await controller.start();
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: AnimatedBuilder(
          animation: controller,
          builder: (_, _) => MapScreen(
            controller: controller,
            onOpenDetail: onOpen ?? (_) {},
            onChangeLocation: () {},
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

class MapRepository extends MockRestroomRepository {
  final events = StreamController<StallUpdate>.broadcast();
  int listRequests = 0;
  @override
  bool get isMock => false;
  @override
  RealtimeStatus get realtimeStatus => RealtimeStatus.connected;
  @override
  Stream<StallUpdate> get updates => events.stream;
  @override
  Future<List<Restroom>> getRestrooms(
    UserLocation location, {
    String? gender,
  }) async {
    listRequests++;
    return [room(1, unknown: 2), room(2, floor: 2, unknown: 2)];
  }

  @override
  void dispose() {
    unawaited(events.close());
  }
}

Restroom room(
  int id, {
  int floor = 1,
  String building = '본관',
  int available = 0,
  int unknown = 0,
  double? latitude = dimigoLatitude,
}) => Restroom(
  id: id,
  name: '$building $floor층 남자 화장실',
  building: building,
  floor: floor,
  x: 0,
  y: 0,
  distance: 0,
  totalStalls: 2,
  availableStalls: available,
  availableBidetStalls: 0,
  unknownStalls: unknown,
  gender: 'male',
  latitude: latitude,
  longitude: latitude == null ? null : dimigoLongitude,
  locationSource: 'school_reference',
);
