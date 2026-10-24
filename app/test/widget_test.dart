import 'package:catchy_toilet/app.dart';
import 'package:catchy_toilet/models/recommendation.dart';
import 'package:catchy_toilet/repositories/mock_restroom_repository.dart';
import 'package:catchy_toilet/widgets/bidet_toggle.dart';
import 'package:catchy_toilet/widgets/recommended_restroom_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('home, bidet toggle, detail and navigation', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      CatchyToiletApp(repository: MockRestroomRepository()),
    );
    await tester.pumpAndSettle();
    expect(find.text('지금, 어디로 갈까요?'), findsOneWidget);
    expect(find.text('데모 · 실제 이용 정보가 아닙니다'), findsOneWidget);
    final initialCard = tester.widget<RecommendedRestroomCard>(
      find.byType(RecommendedRestroomCard),
    );
    expect(initialCard.recommendation.restroom.id, 1);

    await tester.scrollUntilVisible(
      find.byType(BidetToggle),
      180,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.byType(SwitchListTile));
    await tester.pumpAndSettle();
    final bidetCard = tester.widget<RecommendedRestroomCard>(
      find.byType(RecommendedRestroomCard),
    );
    expect(bidetCard.recommendation.restroom.id, 2);

    tester
        .state<ScrollableState>(find.byType(Scrollable).first)
        .position
        .jumpTo(0);
    await tester.pumpAndSettle();
    await tester.tap(find.byType(RecommendedRestroomCard));
    await tester.pumpAndSettle();
    expect(find.text('화장실 상세'), findsOneWidget);
    expect(find.text('칸 현황'), findsOneWidget);
    expect(find.text('1번 칸'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    await tester.tap(find.text('지도'));
    await tester.pumpAndSettle();
    expect(find.text('주변을 한눈에'), findsOneWidget);
    await tester.tap(find.text('설정'));
    await tester.pumpAndSettle();
    expect(find.text('Backend 연결'), findsOneWidget);
    expect(find.text('데모 모드 · 서버에 연결하지 않음'), findsNWidgets(2));
    expect(tester.takeException(), isNull);
  });

  testWidgets('narrow screen and large text remain scrollable', (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    tester.platformDispatcher.textScaleFactorTestValue = 1.6;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpWidget(
      CatchyToiletApp(repository: MockRestroomRepository()),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.scrollUntilVisible(
      find.byType(BidetToggle),
      180,
      scrollable: find.byType(Scrollable).first,
    );
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('지도'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
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

  testWidgets('location form rejects invalid coordinates', (tester) async {
    await tester.pumpWidget(
      CatchyToiletApp(repository: MockRestroomRepository()),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('기준 위치 변경'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextFormField, 'X 좌표 (m)'),
      'NaN',
    );
    await tester.tap(find.text('적용'));
    await tester.pumpAndSettle();
    expect(find.text('유한한 숫자를 입력해 주세요.'), findsOneWidget);
    await tester.enterText(
      find.widgetWithText(TextFormField, 'X 좌표 (m)'),
      '30',
    );
    await tester.tap(find.text('적용'));
    await tester.pumpAndSettle();
    expect(find.text('기준 위치 설정'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
