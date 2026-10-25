import 'package:catch_toilet/app.dart';
import 'package:catch_toilet/models/recommendation.dart';
import 'package:catch_toilet/repositories/mock_restroom_repository.dart';
import 'package:catch_toilet/widgets/bidet_toggle.dart';
import 'package:catch_toilet/widgets/recommended_restroom_card.dart';
import 'package:catch_toilet/widgets/restroom_floor_plan.dart';
import 'package:catch_toilet/widgets/restroom_list_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('welcome, lifecycle, tabs and restroom detail', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repository = _TrackingMockRepository();
    await tester.pumpWidget(CatchToiletApp(repository: repository));
    await tester.pumpAndSettle();
    expect(find.text('시작하기'), findsOneWidget);
    expect(find.text('CATCH TOILET'), findsOneWidget);
    expect(find.text('화장실의 빈칸을 실시간으로 확인하다.'), findsOneWidget);
    expect(find.text('한국디지털미디어고등학교'), findsNothing);
    expect(find.byType(FilledButton), findsOneWidget);
    expect(find.byType(AppBar), findsNothing);
    expect(find.byType(NavigationBar), findsNothing);
    expect(repository.connections, 0);
    expect(repository.healthChecks, 0);

    for (final state in [
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
      AppLifecycleState.hidden,
      AppLifecycleState.inactive,
      AppLifecycleState.resumed,
    ]) {
      tester.binding.handleAppLifecycleStateChanged(state);
    }
    await tester.pumpAndSettle();
    expect(find.text('시작하기'), findsOneWidget);
    expect(repository.connections, 0);
    expect(repository.healthChecks, 0);

    await tester.tap(find.text('시작하기'));
    await tester.tap(find.text('시작하기'));
    await tester.pumpAndSettle();
    expect(repository.connections, 1);
    expect(repository.healthChecks, 1);
    expect(find.text('시작하기'), findsNothing);
    for (final state in [
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
      AppLifecycleState.hidden,
      AppLifecycleState.inactive,
      AppLifecycleState.resumed,
    ]) {
      tester.binding.handleAppLifecycleStateChanged(state);
    }
    await tester.pumpAndSettle();
    expect(repository.connections, 2);
    expect(repository.healthChecks, 2);
    expect(find.byKey(const ValueKey('map-search')), findsOneWidget);
    expect(
      tester
          .widgetList<NavigationDestination>(find.byType(NavigationDestination))
          .map((destination) => destination.label),
      ['지도', '목록', '정보', '추천'],
    );
    await tester.tap(find.widgetWithText(NavigationDestination, '목록'));
    await tester.pumpAndSettle();
    expect(find.text('화장실 목록'), findsOneWidget);
    expect(find.text('데모 · 실제 이용 정보가 아닙니다'), findsNothing);
    expect(find.byType(RestroomListCard), findsWidgets);
    expect(find.text('지금 추천하는 화장실'), findsNothing);
    expect(find.byType(RecommendedRestroomCard), findsNothing);
    expect(find.byType(BidetToggle), findsNothing);
    await tester.ensureVisible(find.byKey(const ValueKey('restroom-2')));
    await tester.tap(find.byKey(const ValueKey('restroom-2')));
    await tester.pumpAndSettle();
    expect(find.byType(RestroomFloorPlan), findsOneWidget);
    expect(find.text('전체 칸 수'), findsOneWidget);
    expect(find.text('1번 칸'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    await tester.tap(find.text('지도'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('map-search')), findsOneWidget);
    await tester.tap(find.widgetWithText(NavigationDestination, '정보'));
    await tester.pumpAndSettle();
    expect(find.text('변비가\n고민이신가요?'), findsOneWidget);
    await tester.tap(find.widgetWithText(NavigationDestination, '추천'));
    await tester.pumpAndSettle();
    expect(find.text('Backend 연결'), findsNothing);
    expect(find.text('연결 정보'), findsNothing);
    expect(find.text('화장실 추천 받기'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('request-recommendation')),
      findsOneWidget,
    );
    await tester.tap(find.widgetWithText(NavigationDestination, '목록'));
    await tester.pumpAndSettle();
    expect(find.byType(RestroomListCard), findsWidgets);
    expect(find.byType(RecommendedRestroomCard), findsNothing);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(
      CatchToiletApp(key: UniqueKey(), repository: MockRestroomRepository()),
    );
    await tester.pumpAndSettle();
    expect(find.text('시작하기'), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
  });

  testWidgets('narrow screen and large text remain scrollable', (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    tester.platformDispatcher.textScaleFactorTestValue = 1.6;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpWidget(
      CatchToiletApp(repository: MockRestroomRepository()),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('시작하기'), findsOneWidget);
    await tester.ensureVisible(find.text('시작하기'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('시작하기'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.tap(find.widgetWithText(NavigationDestination, '목록'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('restroom-3')),
      180,
      scrollable: _listScroll,
    );
    expect(find.byType(BidetToggle), findsNothing);
    expect(find.byType(RecommendedRestroomCard), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('지도'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    for (final label in ['정보', '추천']) {
      await tester.tap(find.widgetWithText(NavigationDestination, label));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('statistics text follows the explicit flag', (tester) async {
    Widget card(bool used) => MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: RecommendedRestroomCard(
            recommendation: Recommendation(
              restroom: MockRestroomRepository.fixtures[1],
              statisticsUsed: used,
              historicalAvailabilityRate: 0.82,
            ),
            onTap: () {},
          ),
        ),
      ),
    );
    await tester.pumpWidget(card(false));
    expect(find.text('평소 이 시간대에 빈칸이 자주 있어요'), findsNothing);
    await tester.pumpWidget(card(true));
    expect(find.text('평소 이 시간대에 빈칸이 자주 있어요'), findsOneWidget);
    expect(find.textContaining('82%'), findsNothing);
  });

  testWidgets('location uses GPS without floor or XY input', (tester) async {
    await tester.pumpWidget(
      CatchToiletApp(repository: MockRestroomRepository()),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('시작하기'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(NavigationDestination, '추천'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('현재 GPS 위치로 추천 · 위치 변경'),
      180,
      scrollable: find.descendant(
        of: find.byKey(const PageStorageKey('recommendation')),
        matching: find.byType(Scrollable),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('현재 GPS 위치로 추천 · 위치 변경'));
    await tester.pumpAndSettle();
    expect(find.text('GPS로 현재 위치 가져오기'), findsOneWidget);
    expect(find.byType(TextFormField), findsNothing);
    expect(find.text('현재 층'), findsNothing);
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, '적용'))
          .onPressed,
      isNull,
    );
    await tester.tap(find.text('본관 기준 위치 사용'));
    await tester.pump();
    await tester.tap(find.text('적용'));
    await tester.pumpAndSettle();
    expect(find.text('GPS로 현재 위치 가져오기'), findsNothing);
    expect(find.text('디미고 본관 기준 · 위치 변경'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

Finder get _listScroll => find
    .descendant(
      of: find.byKey(const PageStorageKey('restroom-list')),
      matching: find.byType(Scrollable),
    )
    .first;

class _TrackingMockRepository extends MockRestroomRepository {
  int connections = 0;
  int healthChecks = 0;

  @override
  Future<void> connect() async {
    connections++;
    await super.connect();
  }

  @override
  Future<void> checkHealth() async {
    healthChecks++;
    await super.checkHealth();
  }
}
