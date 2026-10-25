import 'dart:async';

import 'package:catch_toilet/app.dart';
import 'package:catch_toilet/models/restroom.dart';
import 'package:catch_toilet/models/recommendation.dart';
import 'package:catch_toilet/models/stall.dart';
import 'package:catch_toilet/models/stall_update.dart';
import 'package:catch_toilet/repositories/mock_restroom_repository.dart';
import 'package:catch_toilet/repositories/restroom_repository.dart';
import 'package:catch_toilet/services/location_service.dart';
import 'package:catch_toilet/screens/home_screen.dart';
import 'package:catch_toilet/widgets/restroom_floor_plan.dart';
import 'package:catch_toilet/widgets/restroom_list_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> openList(WidgetTester tester, _ListRepository repository) async {
    await tester.binding.setSurfaceSize(const Size(402, 874));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(CatchToiletApp(repository: repository));
    await tester.tap(find.text('시작하기'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(NavigationDestination, '목록'));
    await tester.pumpAndSettle();
  }

  Set<int> visibleIds(WidgetTester tester) => tester
      .widgetList<RestroomListCard>(find.byType(RestroomListCard))
      .map((card) => card.restroom.id)
      .toSet();

  testWidgets(
    'filters require free matching stalls, combine on one stall and persist',
    (tester) async {
      final repository = _ListRepository();
      await openList(tester, repository);
      expect(visibleIds(tester), {1, 2, 3});
      expect(find.text('혼잡'), findsOneWidget);
      expect(find.text('여유'), findsOneWidget);
      expect(find.text('보통'), findsOneWidget);
      await tester.tap(find.text('장애인'));
      await tester.pumpAndSettle();
      expect(visibleIds(tester), {2, 3});
      await tester.tap(find.text('비데'));
      await tester.pumpAndSettle();
      // Room 1 is full. Room 3 has separate free bidet and accessible stalls,
      // but no single free stall with both facilities.
      expect(visibleIds(tester), {2});
      await tester.tap(find.widgetWithText(NavigationDestination, '정보'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(NavigationDestination, '목록'));
      await tester.pumpAndSettle();
      expect(visibleIds(tester), {2});
      await tester.tap(find.text('장애인'));
      await tester.pumpAndSettle();
      expect(visibleIds(tester), {2, 3});
      await tester.tap(find.text('여자'));
      await tester.pumpAndSettle();
      expect(repository.requestedGenders.last, 'female');
      expect(visibleIds(tester), isEmpty);
      expect(find.textContaining('선택한 조건에 맞는 빈칸'), findsOneWidget);
      await tester.tap(find.text('비데'));
      await tester.pumpAndSettle();
      expect(visibleIds(tester), {4});
      expect(find.text('전체 5칸 · 상태 미확인'), findsOneWidget);
      expect(find.text('미확인'), findsOneWidget);
      expect(find.text('혼잡'), findsNothing);
      expect(find.textContaining('사용 중'), findsNothing);
      expect(find.text('거리 미확인'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'live updates change counts without reloading the list; tap keeps ID',
    (tester) async {
      final repository = _ListRepository();
      await openList(tester, repository);
      expect(find.text('5칸 중 5칸 사용 중'), findsOneWidget);
      expect(repository.listRequests, 1);
      repository.emit(
        const StallUpdate(
          restroomId: 1,
          stallId: 11,
          occupied: false,
          totalStalls: 5,
          availableStalls: 1,
          availableBidetStalls: 1,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('5칸 중 4칸 사용 중'), findsOneWidget);
      expect(find.text('5칸 중 5칸 사용 중'), findsNothing);
      expect(repository.listRequests, 1);
      await tester.tap(find.byKey(const ValueKey('restroom-2')));
      await tester.pumpAndSettle();
      expect(find.byType(RestroomFloorPlan), findsOneWidget);
      expect(
        tester
            .widget<RestroomFloorPlan>(find.byType(RestroomFloorPlan))
            .stalls
            .map((stall) => stall.id),
        repository.rooms[1].stalls!.map((stall) => stall.id),
      );
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(find.text('화장실 목록'), findsOneWidget);
      await tester.tap(find.byTooltip('지도로 돌아가기'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('map-search')), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('list error can retry and an empty response is explained', (
    tester,
  ) async {
    final repository = _ListRepository()..failList = true;
    await openList(tester, repository);
    expect(find.text('목록을 불러오지 못했어요.'), findsOneWidget);
    repository.failList = false;
    repository.emptyList = true;
    await tester.tap(find.text('다시 시도'));
    await tester.pumpAndSettle();
    expect(repository.listRequests, 2);
    expect(find.text('아직 등록된 화장실이 없어요.'), findsOneWidget);
    expect(find.byType(RestroomListCard), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'bidet filter follows live availability without detail requests',
    (tester) async {
      final repository = _ListRepository();
      await openList(tester, repository);
      await tester.tap(find.text('비데'));
      await tester.pumpAndSettle();
      expect(visibleIds(tester), {2, 3});
      repository.changeStall(2, 21, true);
      repository.changeStall(2, 22, true);
      await tester.pumpAndSettle();
      // Ordinary stalls remain free, but all bidet stalls are occupied.
      expect(repository.rooms[1].availableStalls, 2);
      expect(visibleIds(tester), {3});
      repository.changeStall(2, 21, false);
      await tester.pumpAndSettle();
      expect(visibleIds(tester), {2, 3});
      expect(repository.listRequests, 1);
      expect(repository.detailRequests, isEmpty);
    },
  );

  testWidgets('accessible filter tracks occupied and unknown stalls locally', (
    tester,
  ) async {
    final repository = _ListRepository();
    await openList(tester, repository);
    await tester.tap(find.text('장애인'));
    await tester.pumpAndSettle();
    expect(visibleIds(tester), {2, 3});
    final detailCount = repository.detailRequests.length;
    repository.changeStall(2, 21, true);
    await tester.pumpAndSettle();
    expect(visibleIds(tester), {3});
    repository.changeStall(2, 21, null);
    await tester.pumpAndSettle();
    expect(visibleIds(tester), {3});
    repository.changeStall(2, 21, false);
    await tester.pumpAndSettle();
    expect(visibleIds(tester), {2, 3});
    expect(repository.listRequests, 1);
    expect(repository.detailRequests.length, detailCount);
  });

  testWidgets('refresh reloads accessible state after missed events', (
    tester,
  ) async {
    final repository = _ListRepository();
    await openList(tester, repository);
    await tester.tap(find.text('장애인'));
    await tester.pumpAndSettle();
    expect(visibleIds(tester), {2, 3});
    repository.changeStall(2, 21, true, broadcast: false);
    repository.changeStall(2, 25, false, broadcast: false);
    // The total free count is unchanged, but the accessible stall is occupied.
    expect(repository.rooms[1].availableStalls, 4);
    await tester
        .widget<HomeScreen>(find.byType(HomeScreen))
        .controller
        .refresh();
    await tester.pumpAndSettle();
    expect(visibleIds(tester), {3});
    expect(repository.listRequests, 2);
  });

  testWidgets('accessible detail loading and failure are not empty results', (
    tester,
  ) async {
    final repository = _ListRepository();
    await openList(tester, repository);
    final held = Completer<Restroom>();
    repository.heldDetail = held;
    await tester.tap(find.text('장애인'));
    await tester.pump();
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(find.textContaining('선택한 조건에 맞는 빈칸'), findsNothing);
    held.completeError(const RepositoryException('상세 조회 실패'));
    await tester.pumpAndSettle();
    expect(find.textContaining('최신 상태를 확인하지 못했습니다'), findsOneWidget);
    expect(find.textContaining('선택한 조건에 맞는 빈칸'), findsNothing);
    expect(visibleIds(tester), {3});
    await tester.tap(find.text('다시 시도'));
    await tester.pumpAndSettle();
    expect(visibleIds(tester), {2, 3});
    expect(find.textContaining('최신 상태를 확인하지 못했습니다'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}

class _ListRepository extends MockRestroomRepository {
  final events = StreamController<StallUpdate>.broadcast();
  final requestedGenders = <String?>[];
  int listRequests = 0;
  bool failList = false;
  bool emptyList = false;
  final detailRequests = <int>[];
  Completer<Restroom>? heldDetail;
  final rooms = [
    _room(1, available: 0, bidets: 2, accessible: 1),
    _room(2, available: 4, bidets: 2, accessible: 1),
    _room(3, available: 3, bidets: 1, accessible: 1, separateFacilities: true),
    _room(
      4,
      available: 0,
      gender: 'female',
      unknown: 5,
      accessible: 1,
      distance: null,
    ),
  ];

  @override
  Stream<StallUpdate> get updates => events.stream;

  @override
  Future<List<Restroom>> getRestrooms(
    UserLocation location, {
    String? gender,
  }) async {
    listRequests++;
    requestedGenders.add(gender);
    if (failList) throw const RepositoryException('목록을 불러오지 못했어요.');
    if (emptyList) return [];
    return rooms.where((room) => room.gender == gender).map(_summary).toList();
  }

  @override
  Future<Restroom> getDetail(int id, UserLocation location) async {
    detailRequests.add(id);
    if (id == 2 && heldDetail != null) {
      final pending = heldDetail!;
      heldDetail = null;
      return pending.future;
    }
    return rooms.singleWhere((room) => room.id == id);
  }

  @override
  Future<Recommendation> getRecommendation(
    UserLocation location, {
    required bool bidetRequired,
    String? gender,
  }) async => Recommendation(restroom: rooms[1], statisticsUsed: false);

  void emit(StallUpdate event, {bool broadcast = true}) {
    final index = rooms.indexWhere((room) => room.id == event.restroomId);
    rooms[index] = rooms[index].apply(event);
    if (broadcast) events.add(event);
  }

  void changeStall(
    int roomId,
    int stallId,
    bool? occupied, {
    bool broadcast = true,
  }) {
    final room = rooms.singleWhere((room) => room.id == roomId);
    final stalls = room.stalls!
        .map(
          (stall) => stall.id == stallId ? stall.withOccupied(occupied) : stall,
        )
        .toList();
    emit(
      StallUpdate(
        restroomId: roomId,
        stallId: stallId,
        occupied: occupied,
        totalStalls: stalls.length,
        availableStalls: stalls.where((s) => s.occupied == false).length,
        availableBidetStalls: stalls
            .where((s) => s.occupied == false && s.hasBidet == true)
            .length,
        unknownStalls: stalls.where((s) => s.occupied == null).length,
      ),
      broadcast: broadcast,
    );
  }

  @override
  void dispose() {
    unawaited(events.close());
    super.dispose();
  }
}

Restroom _room(
  int id, {
  required int available,
  int? bidets,
  int accessible = 0,
  int unknown = 0,
  String gender = 'male',
  double? distance = 30,
  bool separateFacilities = false,
}) {
  final stalls = List.generate(
    5,
    (i) => Stall(
      id: id * 10 + i + 1,
      stallNumber: i + 1,
      occupied: i < unknown ? null : i >= unknown + available,
      hasBidet: bidets == null
          ? null
          : i >= (separateFacilities ? accessible : 0) &&
                i < (separateFacilities ? accessible : 0) + bidets,
      isAccessible: i < accessible,
    ),
  );
  return Restroom(
    id: id,
    name: '본관 $id층 ${gender == 'male' ? '남자' : '여자'} 화장실',
    building: '본관',
    floor: id,
    x: 0,
    y: 0,
    distance: distance,
    totalStalls: 5,
    availableStalls: available,
    availableBidetStalls: stalls
        .where((s) => s.occupied == false && s.hasBidet == true)
        .length,
    gender: gender,
    bidetStalls: bidets,
    accessibleStalls: accessible,
    unknownStalls: unknown,
    stalls: stalls,
  );
}

Restroom _summary(Restroom room) => Restroom(
  id: room.id,
  name: room.name,
  building: room.building,
  floor: room.floor,
  x: room.x,
  y: room.y,
  distance: room.distance,
  totalStalls: room.totalStalls,
  availableStalls: room.availableStalls,
  availableBidetStalls: room.availableBidetStalls,
  gender: room.gender,
  bidetStalls: room.bidetStalls,
  accessibleStalls: room.accessibleStalls,
  unknownStalls: room.unknownStalls,
);
