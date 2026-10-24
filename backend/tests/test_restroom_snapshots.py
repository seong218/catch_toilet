"""Historical observations in disposable PostgreSQL schemas; no live collection."""

from datetime import datetime, timedelta, timezone
import unittest

from sqlalchemy import delete, extract, func, insert, literal_column, select
from sqlalchemy.exc import IntegrityError

from app.models import Restroom, RestroomSnapshot, SensorEvent, Stall
import test_restrooms_api as restroom_tests


class RestroomSnapshotTests(restroom_tests.RestroomAPIFixture):
    def room(self, *, x=0):
        room = Restroom(name="스냅샷 테스트", building="테스트", floor=1, x=x, y=0)
        self.db.add(Stall(restroom=room, stall_number=1, occupied=False, has_bidet=True))
        self.db.flush()
        return room

    def sample(self, room, captured_at, *, total=1, available=1, bidet=1, is_test_data=True):
        sample = RestroomSnapshot(
            restroom=room, total_stalls=total, available_stalls=available,
            available_bidet_stalls=bidet, captured_at=captured_at, is_test_data=is_test_data,
        )
        self.db.add(sample)
        self.db.flush()
        return sample

    def assert_rejected(self, values, sqlstate):
        with self.assertRaises(IntegrityError) as caught:
            with self.db.begin_nested():
                self.db.execute(insert(RestroomSnapshot).values(**values))
        self.assertEqual(caught.exception.orig.sqlstate, sqlstate)

    def test_timezone_round_trip_and_relationship(self):
        room = self.room()
        captured = datetime(2026, 10, 19, 0, 30, tzinfo=timezone(timedelta(hours=9)))
        sample = self.sample(room, captured)
        self.db.expire_all()
        self.assertEqual(sample.captured_at, datetime(2026, 10, 18, 15, 30, tzinfo=timezone.utc))
        self.assertIsNotNone(sample.captured_at.utcoffset())
        self.assertEqual((sample.total_stalls, sample.available_stalls, sample.available_bidet_stalls), (1, 1, 1))
        self.assertIs(sample.is_test_data, True)
        self.assertIs(sample.restroom, room)
        self.assertEqual(room.snapshots, [sample])

    def test_counts_foreign_keys_and_required_observation_fields(self):
        room = self.room()
        values = dict(
            restroom_id=room.id, total_stalls=2, available_stalls=1,
            available_bidet_stalls=1, captured_at=datetime(2026, 10, 19, tzinfo=timezone.utc),
            is_test_data=True,
        )
        for changes in (
            {"id": 0}, {"total_stalls": -1}, {"available_stalls": -1},
            {"available_stalls": 3}, {"available_bidet_stalls": -1},
            {"available_bidet_stalls": 2},
            {"captured_at": literal_column("'infinity'::timestamptz")},
            {"captured_at": literal_column("'-infinity'::timestamptz")},
        ):
            with self.subTest(changes=changes):
                self.assert_rejected(values | changes, "23514")
        self.assert_rejected(values | {"restroom_id": 2147483647}, "23503")
        for name in ("restroom_id", "total_stalls", "available_stalls", "available_bidet_stalls", "captured_at", "is_test_data"):
            self.assert_rejected(values | {name: None}, "23502")
        for missing in ("captured_at", "is_test_data"):
            self.assert_rejected({key: value for key, value in values.items() if key != missing}, "23502")
        # No stalls is a valid observation, distinct from a missing observation.
        self.sample(room, values["captured_at"], total=0, available=0, bidet=0)

    def test_naive_observation_time_is_rejected_by_orm(self):
        with self.assertRaisesRegex(ValueError, "timezone-aware"):
            RestroomSnapshot(captured_at=datetime(2026, 10, 19))

    def test_same_instant_cannot_be_counted_twice(self):
        room = self.room()
        captured = datetime(2026, 10, 18, 15, 30, tzinfo=timezone.utc)
        self.sample(room, captured)
        # Different offsets and provenance still represent the same room/time.
        self.assert_rejected(dict(
            restroom_id=room.id, total_stalls=1, available_stalls=1, available_bidet_stalls=1,
            captured_at=captured.astimezone(timezone(timedelta(hours=9))), is_test_data=False,
        ), "23505")
        self.sample(self.room(x=10), captured)  # Other rooms can share a capture instant.

    def test_unchanged_state_can_be_sampled_without_sensor_events(self):
        room = self.room()
        first = datetime(2026, 10, 19, tzinfo=timezone.utc)
        self.sample(room, first)
        self.sample(room, first + timedelta(minutes=1))
        self.assertEqual(self.db.scalar(select(func.count()).select_from(RestroomSnapshot)), 2)
        self.assertEqual(self.db.scalar(select(func.count()).select_from(SensorEvent)), 0)

    def test_historical_counts_survive_later_stall_and_bidet_changes(self):
        room = self.room()
        sample = self.sample(room, datetime(2026, 10, 19, tzinfo=timezone.utc))
        room.stalls[0].occupied = True
        room.stalls[0].has_bidet = False
        self.db.add(Stall(restroom=room, stall_number=2, occupied=True, has_bidet=False))
        self.db.flush()
        self.db.expire_all()
        self.assertEqual((sample.total_stalls, sample.available_stalls, sample.available_bidet_stalls), (1, 1, 1))
        detail = self.get_json(f"/api/restrooms/{room.id}")
        self.assertEqual((detail["total_stalls"], detail["available_stalls"], detail["available_bidet_stalls"]), (2, 0, 0))

    def test_snapshot_history_prevents_parent_deletion(self):
        room = self.room()
        sample = self.sample(room, datetime(2026, 10, 19, tzinfo=timezone.utc))
        self.db.execute(delete(Stall).where(Stall.restroom_id == room.id))
        self.assertEqual(room.snapshots, [sample])
        for use_orm in (False, True):
            with self.assertRaises(IntegrityError) as caught:
                with self.db.begin_nested():
                    if use_orm:
                        self.db.delete(room)
                        self.db.flush()
                    else:
                        self.db.execute(delete(Restroom).where(Restroom.id == room.id))
            self.assertEqual(caught.exception.orig.diag.constraint_name, "fk_restroom_snapshots_restroom")

    def test_same_seoul_weekday_and_hour_can_select_independent_availability_counts(self):
        # Artificial fixtures ONLY in this rolled-back schema. The False flags
        # exercise filtering of future real observations, not actual measurements.
        room = self.room()
        monday_midnight_seoul = datetime(2026, 10, 18, 15, 30, tzinfo=timezone.utc)
        for week, available, bidet in ((0, 0, 0), (1, 1, 0), (2, 1, 1)):
            self.sample(room, monday_midnight_seoul + timedelta(weeks=week),
                        available=available, bidet=bidet, is_test_data=False)
        self.sample(room, monday_midnight_seoul + timedelta(minutes=1), is_test_data=True)
        self.sample(room, monday_midnight_seoul + timedelta(hours=1), is_test_data=False)
        self.sample(room, monday_midnight_seoul + timedelta(days=1), is_test_data=False)
        self.sample(self.room(x=10), monday_midnight_seoul, is_test_data=False)

        local_time = func.timezone("Asia/Seoul", RestroomSnapshot.captured_at)
        counts = self.db.execute(select(
            func.count(RestroomSnapshot.id),
            func.count(RestroomSnapshot.id).filter(RestroomSnapshot.available_stalls > 0),
            func.count(RestroomSnapshot.id).filter(RestroomSnapshot.available_bidet_stalls > 0),
        ).where(
            RestroomSnapshot.restroom_id == room.id,
            RestroomSnapshot.is_test_data.is_(False),
            RestroomSnapshot.captured_at >= monday_midnight_seoul - timedelta(minutes=30),
            RestroomSnapshot.captured_at < monday_midnight_seoul + timedelta(weeks=3),
            extract("isodow", local_time) == 1,
            extract("hour", local_time) == 0,
        )).one()
        self.assertEqual(tuple(counts), (3, 2, 1))
        self.assertEqual(self.db.scalar(select(func.count()).select_from(SensorEvent)), 0)

    def test_insufficient_snapshots_keep_distance_recommendation(self):
        near, far = self.room(x=10), self.room(x=50)
        path = "/api/restrooms/recommend?x=0&y=0&bidet_required=true"
        before = self.get_json(path)
        self.assertEqual(before["id"], near.id)
        for week in range(3):
            captured = datetime(2026, 10, 5, tzinfo=timezone.utc) + timedelta(weeks=week)
            self.sample(near, captured, available=0, bidet=0, is_test_data=False)
            self.sample(far, captured, is_test_data=False)
        self.assertEqual(self.get_json(path), before)
        self.assertIs(before["statistics_used"], False)
        self.assertIsNone(before["historical_availability_rate"])
        self.assertIsNone(before["historical_bidet_availability_rate"])


if __name__ == "__main__":
    unittest.main()
