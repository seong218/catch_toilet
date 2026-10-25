import 'dart:async';

import 'package:catchy_toilet/config/app_theme.dart';
import 'package:catchy_toilet/models/recommendation.dart';
import 'package:catchy_toilet/models/restroom.dart';
import 'package:catchy_toilet/models/stall_update.dart';
import 'package:catchy_toilet/repositories/mock_restroom_repository.dart';
import 'package:catchy_toilet/repositories/restroom_repository.dart';
import 'package:catchy_toilet/screens/recommendation_screen.dart';
import 'package:catchy_toilet/services/location_service.dart';
import 'package:catchy_toilet/state/app_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

final _requestButton = find.byKey(const ValueKey('request-recommendation'));
final _bidetToggle = find.byKey(const ValueKey('recommendation-bidet'));

void main() {
  Future<AppController> openScreen(
    WidgetTester tester,
    _RecommendationRepository repository, {
    ValueChanged<int>? onDetail,
    LocationService? locationService,
    Size size = const Size(402, 874),
  }) async {
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final controller = AppController(
      repository,
      locationService:
          locationService ?? LocationService(gpsReader: (_) async => _gps),
      eventDelay: const Duration(milliseconds: 10),
    );
    addTearDown(controller.dispose);
    await controller.start();
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: RecommendationScreen(
            controller: controller,
            onOpenDetail: onDetail ?? (_) {},
            onChangeLocation: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return controller;
  }

  testWidgets(
    'gender, bidet and location reach the server; detail uses returned ID',
    (tester) async {
      final repository = _RecommendationRepository();
      int? opened;
      final controller = await openScreen(
        tester,
        repository,
        onDetail: (id) => opened = id,
      );
      expect(find.text('지금 추천하는 화장실'), findsNothing);
      expect(find.text('조건을 선택하고\n추천 받기를 눌러 주세요.'), findsOneWidget);

      await tester.tap(find.text('여자'));
      await tester.pumpAndSettle();
      await tester.tap(_bidetToggle);
      await tester.pumpAndSettle();
      expect(repository.requests, isEmpty);
      repository.result = _result(1);
      final pending = Completer<Recommendation>();
      repository.pending = pending;
      await tester.tap(_requestButton);
      await tester.pump();
      expect(repository.requests.last.gender, 'female');
      expect(repository.requests.last.bidet, isTrue);
      expect(
        repository.requests.last.location.latitude,
        controller.location.latitude,
      );
      expect(
        repository.requests.last.location.longitude,
        controller.location.longitude,
      );
      expect(find.text('추천 화장실을 찾고 있어요'), findsOneWidget);
      expect(tester.widget<FilledButton>(_requestButton).onPressed, isNull);
      pending.complete(repository.result);
      await tester.pumpAndSettle();
      expect(find.text('본관 2층'), findsOneWidget);
      expect(find.text('빈칸 2 / 5'), findsOneWidget);
      expect(find.text('빈 비데 1칸'), findsOneWidget);
      expect(find.text('현재 빈칸과 거리로 추천했어요.'), findsOneWidget);
      await tester.ensureVisible(find.text('칸별 상태 보기'));
      await tester.tap(find.text('칸별 상태 보기'));
      expect(opened, 2);
    },
  );

  for (final scenario in [
    (
      detail: 'No available bidet stalls',
      code: 404,
      message: '현재 사용 가능하다고 확인된 비데 칸이 없어요.',
    ),
    (
      detail: 'Live availability unavailable',
      code: 404,
      message: '아직 센서 상태가 확인되지 않았어요. 목록 탭에서 시설 정보를 확인하세요.',
    ),
    (detail: 'Database unavailable', code: 503, message: '서버에 연결할 수 없습니다.'),
  ]) {
    testWidgets(
      '${scenario.detail} is explained and retry preserves preferences',
      (tester) async {
        final repository = _RecommendationRepository();
        final controller = await openScreen(tester, repository);
        await tester.tap(_bidetToggle);
        await tester.pumpAndSettle();
        repository.failure = RepositoryException(
          '서버에 연결할 수 없습니다.',
          statusCode: scenario.code,
          detail: scenario.detail,
        );
        await tester.tap(_requestButton);
        await tester.pumpAndSettle();
        expect(find.text(scenario.message), findsOneWidget);
        expect(find.text('지금 추천하는 화장실'), findsNothing);
        expect(controller.bidetRequired, isTrue);
        expect(tester.widget<SwitchListTile>(_bidetToggle).value, isTrue);
        repository.failure = null;
        repository.result = _result(1);
        await tester.ensureVisible(find.text('다시 확인'));
        await tester.tap(find.text('다시 확인'));
        await tester.pumpAndSettle();
        expect(find.text('본관 2층'), findsOneWidget);
        expect(repository.requests.last.bidet, isTrue);
      },
    );
  }

  testWidgets(
    'statistics use the relevant metric and all-full fallback stays explicit',
    (tester) async {
      final repository = _RecommendationRepository();
      final controller = await openScreen(tester, repository);
      await tester.tap(_bidetToggle);
      await tester.pumpAndSettle();
      repository.result = Recommendation(
        restroom: MockRestroomRepository.fixtures[1],
        statisticsUsed: true,
        historicalAvailabilityRate: 0.82,
        historicalBidetAvailabilityRate: 0.65,
      );
      await tester.tap(_requestButton);
      await tester.pumpAndSettle();
      expect(find.textContaining('비데 빈칸 존재 비율 65%'), findsOneWidget);
      expect(find.textContaining('82%'), findsNothing);

      repository.result = Recommendation(
        restroom: MockRestroomRepository.fixtures[1],
        statisticsUsed: false,
        historicalAvailabilityRate: 0.82,
        historicalBidetAvailabilityRate: 0.65,
      );
      await controller.refreshRecommendation();
      await tester.pumpAndSettle();
      expect(find.textContaining('빈칸 존재 비율'), findsNothing);
      expect(find.text('현재 빈칸과 거리로 추천했어요.'), findsOneWidget);

      final full = MockRestroomRepository.fixtures.first.apply(
        const StallUpdate(
          restroomId: 1,
          stallId: 2,
          occupied: true,
          totalStalls: 3,
          availableStalls: 0,
          availableBidetStalls: 0,
        ),
      );
      repository.result = Recommendation(restroom: full, statisticsUsed: false);
      await controller.refreshRecommendation();
      await tester.pumpAndSettle();
      expect(find.text('빈칸 0 / 3'), findsOneWidget);
      expect(find.text('현재 모두 사용 중이에요.\n가장 가까운 화장실을 안내해요.'), findsOneWidget);
      expect(controller.bidetRequired, isTrue);
    },
  );

  testWidgets(
    'sensor events replace the displayed recommendation without reloading the list',
    (tester) async {
      final repository = _RecommendationRepository();
      await openScreen(tester, repository);
      await tester.tap(_requestButton);
      await tester.pumpAndSettle();
      expect(find.text('본관 1층'), findsOneWidget);
      final listRequests = repository.listRequests;
      final requests = repository.requests.length;
      repository.result = _result(1);
      repository.events.add(
        const StallUpdate(
          restroomId: 1,
          stallId: 2,
          occupied: true,
          totalStalls: 3,
          availableStalls: 0,
          availableBidetStalls: 0,
        ),
      );
      await tester.pump();
      expect(find.text('본관 1층'), findsNothing);
      expect(find.text('추천 화장실을 찾고 있어요'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 20));
      await tester.pumpAndSettle();
      expect(find.text('본관 2층'), findsOneWidget);
      expect(repository.requests.length, requests + 1);
      expect(repository.listRequests, listRequests);
    },
  );

  testWidgets(
    'narrow screen with large text can request and reach result and location',
    (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 1.6;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final repository = _RecommendationRepository();
      await openScreen(tester, repository, size: const Size(320, 640));
      await tester.ensureVisible(_requestButton);
      await tester.tap(_requestButton);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('칸별 상태 보기'));
      await tester.pumpAndSettle();
      expect(find.text('본관 1층'), findsOneWidget);
      await tester.ensureVisible(find.text('현재 GPS 위치 · 위치 변경'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'GPS is awaited before recommending and duplicate taps are blocked',
    (tester) async {
      final gps = Completer<UserLocation>();
      var gpsReads = 0;
      final repository = _RecommendationRepository();
      await openScreen(
        tester,
        repository,
        locationService: LocationService(
          gpsReader: (_) {
            gpsReads++;
            return gps.future;
          },
        ),
      );
      expect(find.text('현재 GPS 위치로 추천 · 위치 변경'), findsOneWidget);
      expect(repository.requests, isEmpty);
      await tester.tap(_requestButton);
      await tester.pump();
      expect(find.text('GPS로 현재 위치를 확인하고 있어요'), findsOneWidget);
      expect(tester.widget<FilledButton>(_requestButton).onPressed, isNull);
      await tester.tap(_requestButton);
      expect(gpsReads, 1);
      expect(repository.requests, isEmpty);
      gps.complete(_gps);
      await tester.pumpAndSettle();
      expect(repository.requests.single.location, same(_gps));
      expect(find.text('현재 GPS 위치 · 위치 변경'), findsOneWidget);
    },
  );

  testWidgets('GPS error offers settings and retry without campus fallback', (
    tester,
  ) async {
    var denied = true;
    final repository = _RecommendationRepository();
    await openScreen(
      tester,
      repository,
      locationService: LocationService(
        gpsReader: (_) async {
          if (denied) {
            throw const LocationFailure(
              '설정에서 위치 접근을 허용해 주세요.',
              openSettings: true,
            );
          }
          return _gps;
        },
      ),
    );
    await tester.tap(_requestButton);
    await tester.pumpAndSettle();
    expect(find.text('설정에서 위치 접근을 허용해 주세요.'), findsOneWidget);
    expect(find.text('기기 설정 열기'), findsOneWidget);
    expect(find.text('지금 추천하는 화장실'), findsNothing);
    expect(repository.requests, isEmpty);
    denied = false;
    await tester.ensureVisible(find.text('GPS 다시 확인'));
    await tester.tap(find.text('GPS 다시 확인'));
    await tester.pumpAndSettle();
    expect(repository.requests.single.location, same(_gps));
    expect(find.text('본관 1층'), findsOneWidget);
  });
}

const _gps = UserLocation(
  label: '현재 GPS 위치',
  latitude: 37.35,
  longitude: 126.84,
  isGps: true,
);

Recommendation _result(int index) => Recommendation(
  restroom: MockRestroomRepository.fixtures[index],
  statisticsUsed: false,
);

class _RecommendationRepository extends MockRestroomRepository {
  final events = StreamController<StallUpdate>.broadcast(sync: true);
  final requests = <({String? gender, bool bidet, UserLocation location})>[];
  Recommendation result = _result(0);
  RepositoryException? failure;
  Completer<Recommendation>? pending;
  int listRequests = 0;

  @override
  Stream<StallUpdate> get updates => events.stream;

  @override
  Future<List<Restroom>> getRestrooms(
    UserLocation location, {
    String? gender,
  }) async {
    listRequests++;
    return MockRestroomRepository.fixtures;
  }

  @override
  Future<Recommendation> getRecommendation(
    UserLocation location, {
    required bool bidetRequired,
    String? gender,
  }) async {
    requests.add((gender: gender, bidet: bidetRequired, location: location));
    if (failure != null) throw failure!;
    final held = pending;
    pending = null;
    return held == null ? result : await held.future;
  }

  @override
  void dispose() {
    unawaited(events.close());
    super.dispose();
  }
}
