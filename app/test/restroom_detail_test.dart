import 'dart:async';

import 'package:catchy_toilet/config/app_theme.dart';
import 'package:catchy_toilet/models/recommendation.dart';
import 'package:catchy_toilet/models/restroom.dart';
import 'package:catchy_toilet/models/stall_update.dart';
import 'package:catchy_toilet/repositories/mock_restroom_repository.dart';
import 'package:catchy_toilet/repositories/restroom_repository.dart';
import 'package:catchy_toilet/screens/restroom_detail_screen.dart';
import 'package:catchy_toilet/services/location_service.dart';
import 'package:catchy_toilet/state/app_controller.dart';
import 'package:catchy_toilet/widgets/restroom_floor_plan.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<AppController> openDetail(
    WidgetTester tester,
    _DetailRepository repository, {
    int id = 11,
    Size size = const Size(402, 874),
  }) async {
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final controller = AppController(repository);
    addTearDown(controller.dispose);
    await controller.start();
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: RestroomDetailScreen(controller: controller, restroomId: id),
      ),
    );
    await tester.pump();
    return controller;
  }

  testWidgets('selected floor supplies actual stall and bidet inventory', (
    tester,
  ) async {
    final repository = _DetailRepository();
    await openDetail(tester, repository);
    await tester.pumpAndSettle();
    expect(repository.detailRequests, [11]);
    final plan = tester.widget<RestroomFloorPlan>(
      find.byType(RestroomFloorPlan),
    );
    expect(plan.stalls.length, 4);
    expect(find.text('전체 4칸 · 상태 미확인'), findsOneWidget);
    expect(find.bySemanticsLabel('전체 칸 수 4칸'), findsOneWidget);
    expect(find.bySemanticsLabel('비데 3개'), findsOneWidget);
    expect(find.bySemanticsLabel('사용 중 미확인'), findsOneWidget);
    expect(
      find.bySemanticsLabel('1번 칸, 상태 미확인, 비데 없음, 장애인 이용 가능 칸'),
      findsOneWidget,
    );
    expect(find.byIcon(Icons.accessible_rounded), findsNWidgets(2));
    expect(find.textContaining('도보'), findsNothing);
    expect(find.text('총 인원'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'live event updates marker and totals without another detail GET',
    (tester) async {
      final repository = _DetailRepository();
      final controller = await openDetail(tester, repository);
      await tester.pumpAndSettle();
      const occupied = StallUpdate(
        restroomId: 11,
        stallId: 112,
        occupied: true,
        totalStalls: 4,
        availableStalls: 0,
        availableBidetStalls: 0,
        unknownStalls: 3,
      );
      repository.events.add(occupied);
      await tester.pumpAndSettle();
      expect(find.bySemanticsLabel('2번 칸, 사용 중, 비데 있음'), findsOneWidget);
      expect(find.bySemanticsLabel('사용 중 1칸'), findsOneWidget);
      expect(find.bySemanticsLabel('상태 미확인 3칸'), findsOneWidget);
      repository.events.add(occupied);
      await tester.pumpAndSettle();
      expect(find.bySemanticsLabel('사용 중 1칸'), findsOneWidget);
      repository.events.add(
        const StallUpdate(
          restroomId: 11,
          stallId: 112,
          occupied: false,
          totalStalls: 4,
          availableStalls: 1,
          availableBidetStalls: 1,
          unknownStalls: 3,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.bySemanticsLabel('2번 칸, 사용 가능, 비데 있음'), findsOneWidget);
      expect(find.bySemanticsLabel('사용 가능 1칸'), findsOneWidget);
      expect(find.bySemanticsLabel('비데 3개'), findsOneWidget);
      expect(repository.detailRequests, [11]);
      expect(controller.details[11]!.availableBidetStalls, 1);
      // Let the existing recommendation debounce finish before test disposal.
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('female floor, unknown bidets and large text stay scrollable', (
    tester,
  ) async {
    tester.platformDispatcher.textScaleFactorTestValue = 1.6;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final repository = _DetailRepository();
    await openDetail(tester, repository, id: 22, size: const Size(320, 640));
    await tester.pumpAndSettle();
    expect(repository.detailRequests, [22]);
    final plan = tester.widget<RestroomFloorPlan>(
      find.byType(RestroomFloorPlan),
    );
    expect(plan.stalls.length, 6);
    expect(find.text('12번 칸'), findsOneWidget);
    expect(find.text('1번 칸'), findsNothing);
    await tester.ensureVisible(find.text('12번 칸'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(find.text('전체 칸 수'));
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel('비데 미확인'), findsOneWidget);
    expect(find.bySemanticsLabel('전체 칸 수 6칸'), findsOneWidget);
    expect(find.text('거리 미확인'), findsOneWidget);
    expect(find.byIcon(Icons.accessible_rounded), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('initial loading and failure can recover through retry', (
    tester,
  ) async {
    final repository = _DetailRepository()..pending = Completer<Restroom>();
    await openDetail(tester, repository);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.byType(BackButton), findsOneWidget);
    expect(find.byType(RestroomFloorPlan), findsNothing);
    repository.pending!.completeError(
      const RepositoryException('연결을 확인해 주세요.'),
    );
    await tester.pumpAndSettle();
    expect(find.text('연결을 확인해 주세요.'), findsOneWidget);
    repository.pending = null;
    await tester.tap(find.text('다시 시도'));
    await tester.pumpAndSettle();
    expect(find.byType(RestroomFloorPlan), findsOneWidget);
    expect(repository.detailRequests, [11, 11]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('empty inventory and stale refresh are explained', (
    tester,
  ) async {
    final repository = _DetailRepository();
    final controller = await openDetail(tester, repository, id: 33);
    await tester.pumpAndSettle();
    expect(find.text('아직 등록된 칸이 없어요.'), findsOneWidget);
    expect(find.bySemanticsLabel('전체 칸 수 0칸'), findsOneWidget);
    repository.pending = Completer<Restroom>();
    final refresh = controller.loadDetail(33);
    await tester.pump();
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    repository.pending!.completeError(const RepositoryException('갱신 실패'));
    await refresh;
    await tester.pumpAndSettle();
    expect(find.text('갱신 실패'), findsOneWidget);
    expect(find.textContaining('마지막으로 확인한 정보'), findsOneWidget);
    expect(find.text('아직 등록된 칸이 없어요.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

class _DetailRepository extends MockRestroomRepository {
  final events = StreamController<StallUpdate>.broadcast();
  final detailRequests = <int>[];
  Completer<Restroom>? pending;
  final rooms = [_room(11, count: 4), _room(22, count: 6), _room(33, count: 0)];

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
  }) async => rooms;
  @override
  Future<Restroom> getDetail(int id, UserLocation location) async {
    detailRequests.add(id);
    return pending != null
        ? pending!.future
        : rooms.singleWhere((room) => room.id == id);
  }

  @override
  Future<Recommendation> getRecommendation(
    UserLocation location, {
    required bool bidetRequired,
    String? gender,
  }) async => Recommendation(restroom: rooms.first, statisticsUsed: false);
  @override
  void dispose() => unawaited(events.close());
}

// Test-only inventory exercises nullable API fields and non-index stall numbers.
Restroom _room(int id, {required int count}) => Restroom.fromJson({
  'id': id,
  'name': id == 22 ? '본관 2층 여자 화장실' : '본관 1층 남자 화장실',
  'building': '본관',
  'floor': id == 22 ? 2 : 1,
  'x': 0,
  'y': 0,
  'gender': id == 22 ? 'female' : 'male',
  'distance': id == 22 ? null : 30,
  'total_stalls': count,
  'available_stalls': 0,
  'available_bidet_stalls': 0,
  'unknown_stalls': count,
  'bidet_stalls': id == 22 ? null : (count > 0 ? 3 : 0),
  'accessible_stalls': id == 11 ? 1 : 0,
  'stalls': [
    for (var i = 1; i <= count; i++)
      {
        'id': id * 10 + i,
        'stall_number': id == 22 ? i * 2 : i,
        'occupied': null,
        'has_bidet': id == 22 ? null : i > 1,
        'is_accessible': id == 11 && i == 1,
      },
  ],
}, requireStalls: true);
