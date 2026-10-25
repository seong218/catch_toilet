import 'package:catch_toilet/app.dart';
import 'package:catch_toilet/data/health_articles.dart';
import 'package:catch_toilet/repositories/mock_restroom_repository.dart';
import 'package:catch_toilet/screens/info_screen.dart';
import 'package:catch_toilet/widgets/health_article_body.dart';
import 'package:catch_toilet/widgets/health_article_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> openInfo(WidgetTester tester) async {
  await tester.pumpWidget(
    CatchToiletApp(repository: MockRestroomRepository()),
  );
  await tester.pumpAndSettle();
  await tester.ensureVisible(find.text('시작하기'));
  await tester.tap(find.text('시작하기'));
  await tester.pumpAndSettle();
  await tester.tap(find.widgetWithText(NavigationDestination, '정보'));
  await tester.pumpAndSettle();
}

Future<void> selectTopic(WidgetTester tester, String label) async {
  final chip = find.widgetWithText(ChoiceChip, label);
  await tester.ensureVisible(chip);
  await tester.pumpAndSettle();
  await tester.tap(chip);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('covers replace only the center and keep the existing bars', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(402, 874));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await openInfo(tester);
    final appBar = tester.element(find.byType(AppBar));
    final navigationBar = tester.element(find.byType(NavigationBar));
    final appBarRect = tester.getRect(find.byType(AppBar));
    final navigationBarRect = tester.getRect(find.byType(NavigationBar));
    final route = ModalRoute.of(tester.element(find.byType(InfoScreen)));
    for (final article in healthArticles) {
      final card = find.byKey(ValueKey(article.id));
      await tester.ensureVisible(card);
      await tester.pumpAndSettle();
      if (article == healthArticles.first) {
        final openArticle = tester.widget<HealthArticleCard>(card).onTap;
        openArticle();
        openArticle();
      } else {
        await tester.tap(card);
      }
      await tester.pumpAndSettle();
      expect(find.byType(HealthArticleBody), findsOneWidget);
      expect(find.text(article.title), findsOneWidget);
      expect(find.text(article.sections.first.body), findsOneWidget);
      expect(tester.element(find.byType(AppBar)), same(appBar));
      expect(tester.element(find.byType(NavigationBar)), same(navigationBar));
      expect(tester.getRect(find.byType(AppBar)), appBarRect);
      expect(tester.getRect(find.byType(NavigationBar)), navigationBarRect);
      expect(
        ModalRoute.of(tester.element(find.byType(InfoScreen))),
        same(route),
      );
      expect(
        Navigator.of(tester.element(find.byType(InfoScreen))).canPop(),
        isFalse,
      );
      expect(
        tester
            .widget<ChoiceChip>(
              find.widgetWithText(ChoiceChip, article.category.label),
            )
            .selected,
        isTrue,
      );
      await tester.tap(find.byTooltip('정보 목록으로 돌아가기'));
      await tester.pumpAndSettle();
      expect(find.byType(HealthArticleBody), findsNothing);
      expect(find.byType(HealthArticleCard), findsNWidgets(4));
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'topic tabs open and switch text, reset scroll and return via all',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(402, 874));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await openInfo(tester);
      await selectTopic(tester, '변비');
      final articleScroll = find.descendant(
        of: find.byKey(const ValueKey('health-article-scroll')),
        matching: find.byType(Scrollable),
      );
      await tester.scrollUntilVisible(
        find.text('[출처] 대한민국 정책브리핑(www.korea.kr)'),
        500,
        scrollable: articleScroll,
      );
      expect(
        tester.state<ScrollableState>(articleScroll).position.pixels,
        greaterThan(0),
      );
      for (final article in healthArticles.skip(1)) {
        await selectTopic(tester, article.category.label);
        expect(find.text(article.title), findsOneWidget);
        expect(
          find.text(article.sections.first.body).hitTestable(),
          findsOneWidget,
        );
        expect(tester.state<ScrollableState>(articleScroll).position.pixels, 0);
        expect(
          find.text(healthArticles.first.sections.first.body),
          findsNothing,
        );
      }
      await selectTopic(tester, '전체');
      expect(find.byType(HealthArticleBody), findsNothing);
      expect(find.byType(HealthArticleCard), findsNWidgets(4));
      expect(
        tester
            .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, '전체'))
            .selected,
        isTrue,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'bottom tabs preserve the reader and system back returns to the grid',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(402, 874));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await openInfo(tester);
      await selectTopic(tester, '변비');
      final articleScroll = find.descendant(
        of: find.byKey(const ValueKey('health-article-scroll')),
        matching: find.byType(Scrollable),
      );
      await tester.scrollUntilVisible(
        find.text('[출처] 대한민국 정책브리핑(www.korea.kr)'),
        500,
        scrollable: articleScroll,
      );
      final offset = tester
          .state<ScrollableState>(articleScroll)
          .position
          .pixels;
      await tester.tap(find.widgetWithText(NavigationDestination, '추천'));
      await tester.pumpAndSettle();
      expect(find.text('화장실 추천 받기'), findsOneWidget);
      await tester.tap(find.widgetWithText(NavigationDestination, '정보'));
      await tester.pumpAndSettle();
      expect(find.text('변비가 고민이신가요?'), findsOneWidget);
      expect(
        tester.state<ScrollableState>(articleScroll).position.pixels,
        offset,
      );
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(HealthArticleBody), findsNothing);
      expect(find.byType(HealthArticleCard), findsNWidgets(4));
      await tester.tap(find.byTooltip('이전 탭으로 돌아가기'));
      await tester.pumpAndSettle();
      expect(find.text('화장실 추천 받기'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'narrow screen and large text can read every article to its end',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(320, 640));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      tester.platformDispatcher.textScaleFactorTestValue = 1.6;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await openInfo(tester);
      for (final article in healthArticles) {
        await selectTopic(tester, article.category.label);
        final ending = find.text(article.source ?? article.sections.last.body);
        await tester.ensureVisible(ending);
        await tester.pumpAndSettle();
        expect(ending, findsOneWidget);
        expect(tester.takeException(), isNull);
      }
      await selectTopic(tester, '전체');
      expect(find.byType(NavigationBar), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
