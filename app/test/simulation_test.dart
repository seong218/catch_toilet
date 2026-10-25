import 'dart:async';
import 'package:catch_toilet/models/restroom.dart';
import 'package:catch_toilet/models/stall_update.dart';
import 'package:catch_toilet/models/recommendation.dart';
import 'package:catch_toilet/repositories/mock_restroom_repository.dart';
import 'package:catch_toilet/repositories/restroom_repository.dart';
import 'package:catch_toilet/services/location_service.dart';
import 'package:catch_toilet/state/app_controller.dart';
import 'package:catch_toilet/screens/home_screen.dart';
import 'package:catch_toilet/widgets/restroom_floor_plan.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _room() => {
  'id': 1,
  'name': '본관 1층 남자 화장실',
  'building': '본관',
  'floor': 1,
  'x': 0,
  'y': 0,
  'distance': 0,
  'gender': 'male',
  'total_stalls': 1,
  'available_stalls': 1,
  'available_bidet_stalls': 1,
  'unknown_stalls': 0,
  'simulated_stalls': 0,
  'stalls': [
    {
      'id': 1,
      'stall_number': 1,
      'occupied': false,
      'has_bidet': true,
      'is_accessible': false,
      'is_simulated': false,
    },
  ],
};

StallUpdate _event({required bool simulated, bool? occupied = false}) =>
    StallUpdate.fromJson({
      'restroom_id': 1,
      'stall_id': 1,
      'occupied': occupied,
      'total_stalls': 1,
      'available_stalls': occupied == false ? 1 : 0,
      'available_bidet_stalls': occupied == false ? 1 : 0,
      'unknown_stalls': occupied == null ? 1 : 0,
      'simulated_stalls': simulated ? 1 : 0,
      'is_simulated': simulated,
    });

void main() {
  test(
    'simulation and reset events preserve facilities and restore unknown state',
    () {
      final initial = Restroom.fromJson(_room());
      final simulated = initial.apply(_event(simulated: true));
      expect(simulated.stalls!.single.isSimulated, isTrue);
      expect(simulated.simulatedStalls, 1);
      expect(simulated.withDistance(20).simulatedStalls, 1);
      final reset = simulated.apply(_event(simulated: false, occupied: null));
      expect(reset.stalls!.single.occupied, isNull);
      expect(reset.stalls!.single.hasBidet, isTrue);
      expect(reset.simulatedStalls, 0);
      expect(reset.unknownStalls, 1);
    },
  );

  test('simulation counts must match detail flags', () {
    final data = _room()..['simulated_stalls'] = 1;
    expect(() => Restroom.fromJson(data), throwsFormatException);
  });

  testWidgets(
    'source-only events update the floor plan without a test notice',
    (tester) async {
      final repository = _Repository();
      final controller = AppController(repository);
      addTearDown(controller.dispose);
      await controller.start();
      await controller.openDetail(1);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AnimatedBuilder(
              animation: controller,
              builder: (_, _) =>
                  HomeScreen(controller: controller, onOpenDetail: (_) {}),
            ),
          ),
        ),
      );
      expect(find.textContaining('테스트 데이터 포함'), findsNothing);
      repository.emit(_event(simulated: true));
      await tester.pump();
      expect(controller.isRealtime, isTrue);
      expect(controller.hasSimulatedData, isTrue);
      expect(controller.details[1]!.stalls!.single.isSimulated, isTrue);
      expect(find.textContaining('테스트 데이터 포함'), findsNothing);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RestroomFloorPlan(stalls: controller.details[1]!.stalls!),
          ),
        ),
      );
      expect(
        find.bySemanticsLabel('1번 칸, 사용 가능, 비데 있음, 테스트 상태'),
        findsOneWidget,
      );
      repository.emit(_event(simulated: false));
      expect(controller.hasSimulatedData, isFalse);
      expect(controller.details[1]!.stalls!.single.isSimulated, isFalse);
      expect(repository.detailReads, 1);
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();
    },
  );
}

class _Repository extends MockRestroomRepository {
  Restroom room = Restroom.fromJson(_room());
  final events = StreamController<StallUpdate>.broadcast(sync: true);
  int detailReads = 0;
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
  }) async => [room];
  @override
  Future<Restroom> getDetail(int id, UserLocation location) async {
    detailReads++;
    return room;
  }

  @override
  Future<Recommendation> getRecommendation(
    UserLocation location, {
    required bool bidetRequired,
    String? gender,
  }) async => Recommendation(restroom: room, statisticsUsed: false);
  void emit(StallUpdate event) {
    room = room.apply(event);
    events.add(event);
  }

  @override
  void dispose() {
    unawaited(events.close());
  }
}
