"""Synthetic historical observations in rolled-back PostgreSQL schemas only.

False provenance flags exercise the production query in isolated test storage;
no generated observations are written to the application's development tables.
"""

from datetime import datetime, timedelta, timezone
import os
import unittest
from unittest.mock import Mock, patch
from zoneinfo import ZoneInfo

from pydantic import ValidationError
from sqlalchemy import event, select
from sqlalchemy.exc import OperationalError
from sqlalchemy.orm import Session

from app.config import Settings, get_settings
from app.models import Restroom, RestroomSnapshot, Stall
from app.services.statistics import get_restroom_statistics, get_restrooms_statistics
import test_restrooms_api as restroom_tests


class StatisticsTests(restroom_tests.RestroomAPIFixture):
    def setUp(self):
        super().setUp()
        self.now = datetime(2026, 10, 26, 3, 30, tzinfo=timezone.utc)  # Monday 12:30 Seoul.
        self.settings = get_settings().model_copy(update={
            "min_stat_sample_count": 3, "stat_lookback_days": 56,
        })
        self.enterContext(patch("app.services.statistics.get_settings", return_value=self.settings))
        self.room = self.make_room(10)

    def make_room(self, x):
        room = Restroom(name="통계 테스트", building="테스트", floor=1, x=x, y=0)
        self.db.add(Stall(restroom=room, stall_number=1, occupied=False, has_bidet=True))
        self.db.flush()
        return room

    def sample(self, captured_at, *, available=1, bidet=1, total=8, test_data=False, room=None):
        self.db.add(RestroomSnapshot(
            restroom_id=(self.room if room is None else room).id,
            total_stalls=total, available_stalls=available, available_bidet_stalls=bidet,
            captured_at=captured_at, is_test_data=test_data,
        ))
        self.db.flush()

    def four_samples(self, states=((0, 0), (1, 0), (5, 1), (0, 0)), *, room=None):
        start = (self.now - timedelta(weeks=1)).replace(minute=0)
        for index, (available, bidet) in enumerate(states):
            self.sample(start + timedelta(minutes=index * 10), available=available, bidet=bidet, room=room)

    def statistics(self, **kwargs):
        return get_restroom_statistics(self.db, self.room.id, now=self.now, **kwargs)

    def test_rates_count_observed_availability_not_stalls_or_events(self):
        self.four_samples()
        result = self.statistics()
        self.assertEqual(result.sample_count, 4)
        self.assertEqual(result.historical_availability_rate, 0.5)
        self.assertEqual(result.historical_bidet_availability_rate, 0.25)
        self.assertTrue(result.is_usable)

    def test_minimum_sample_threshold_is_inclusive_and_configurable(self):
        self.four_samples()
        self.settings.min_stat_sample_count = 5
        insufficient = self.statistics()
        self.assertEqual(insufficient.sample_count, 4)
        self.assertFalse(insufficient.is_usable)
        self.assertIsNone(insufficient.historical_availability_rate)
        self.assertIsNone(insufficient.historical_bidet_availability_rate)
        self.settings.min_stat_sample_count = 4
        self.assertTrue(self.statistics().is_usable)
        self.settings.min_stat_sample_count = 1
        self.assertEqual(self.statistics().historical_availability_rate, 0.5)

    def test_no_observations_and_unknown_restroom_return_unavailable(self):
        for room_id in (self.room.id, 2147483647):
            result = get_restroom_statistics(self.db, room_id, now=self.now)
            self.assertEqual(result.sample_count, 0)
            self.assertIsNone(result.historical_availability_rate)
            self.assertIsNone(result.historical_bidet_availability_rate)
            self.assertFalse(result.is_usable)

    def test_measured_zero_and_one_are_usable_and_bidet_is_independent(self):
        for available, bidet, expected in ((0, 0, (0.0, 0.0)), (1, 0, (1.0, 0.0)), (1, 1, (1.0, 1.0))):
            with self.subTest(available=available, bidet=bidet):
                room = self.make_room(30)
                self.four_samples(((available, bidet),) * 4, room=room)
                result = get_restroom_statistics(self.db, room.id, now=self.now)
                self.assertEqual(result.sample_count, 4)
                self.assertEqual((result.historical_availability_rate, result.historical_bidet_availability_rate), expected)
                self.assertTrue(result.is_usable)

    def test_test_data_and_other_restrooms_are_excluded(self):
        self.four_samples()
        self.four_samples(((1, 1),) * 4, room=self.make_room(50))
        for minute in range(40, 50):
            self.sample((self.now - timedelta(weeks=1)).replace(minute=minute), test_data=True)
        result = self.statistics()
        self.assertEqual(result.sample_count, 4)
        self.assertEqual((result.historical_availability_rate, result.historical_bidet_availability_rate), (0.5, 0.25))

    def test_only_test_data_never_passes_minimum(self):
        self.settings.min_stat_sample_count = 1
        self.sample(self.now - timedelta(weeks=1), test_data=True)
        result = self.statistics()
        self.assertEqual(result.sample_count, 0)
        self.assertFalse(result.is_usable)

    def test_seoul_weekday_and_hour_boundaries_use_local_time(self):
        reference = datetime(2026, 10, 25, 15, 30, tzinfo=timezone.utc)  # Seoul Monday 00:30.
        start = (reference - timedelta(weeks=1)).replace(minute=0)
        self.sample(start, available=1, bidet=0)  # Monday 00:00, inclusive.
        self.sample(start + timedelta(hours=1, microseconds=-1), available=0, bidet=0)
        # Wrong local weekday/hour; the last one is Monday in UTC but 09:00 Seoul.
        for captured in (start - timedelta(microseconds=1), start + timedelta(hours=1),
                         start + timedelta(days=1), start + timedelta(hours=9)):
            self.sample(captured)
        self.settings.min_stat_sample_count = 2
        result = get_restroom_statistics(self.db, self.room.id, now=reference)
        self.assertEqual(result.sample_count, 2)
        self.assertEqual((result.historical_availability_rate, result.historical_bidet_availability_rate), (0.5, 0.0))
        self.assertEqual(get_restroom_statistics(
            self.db, self.room.id, now=reference.astimezone(ZoneInfo("Asia/Seoul")),
        ), result)

    def test_window_start_is_inclusive_and_present_future_and_old_data_are_excluded(self):
        self.settings.stat_lookback_days = 14
        self.settings.min_stat_sample_count = 1
        start = self.now - timedelta(days=14)
        for captured in (start, start + timedelta(minutes=1), self.now - timedelta(microseconds=1)):
            self.sample(captured)
        for captured in (start - timedelta(microseconds=1), self.now,
                         self.now + timedelta(microseconds=1), self.now + timedelta(weeks=1),
                         self.now - timedelta(weeks=3)):
            self.sample(captured, available=0, bidet=0)
        result = self.statistics()
        self.assertEqual(result.sample_count, 3)
        self.assertEqual((result.historical_availability_rate, result.historical_bidet_availability_rate), (1.0, 1.0))
        self.settings.stat_lookback_days = 7
        self.assertEqual(self.statistics().sample_count, 1)

    def test_default_clock_uses_server_time(self):
        self.four_samples()

        class FrozenDateTime(datetime):
            @classmethod
            def now(cls, tz=None):
                return cls(2026, 10, 26, 3, 30, tzinfo=timezone.utc).astimezone(tz)

        with patch("app.services.statistics.datetime", FrozenDateTime):
            result = get_restroom_statistics(self.db, self.room.id)
        self.assertEqual((result.sample_count, result.historical_availability_rate), (4, 0.5))

    def test_invalid_reference_time_and_restroom_id_are_rejected(self):
        for reference in (datetime(2026, 10, 26), "2026-10-26"):
            with self.assertRaisesRegex(ValueError, "timezone-aware"):
                get_restroom_statistics(self.db, self.room.id, now=reference)
        for room_id in (0, -1, True, 1.5, "1"):
            with self.assertRaisesRegex(ValueError, "positive integer"):
                get_restroom_statistics(self.db, room_id, now=self.now)

    def test_one_read_only_snapshot_query_without_cache_or_history_reconstruction(self):
        self.four_samples()
        before = self.db.execute(select(RestroomSnapshot.__table__).order_by(RestroomSnapshot.id)).all()
        statements = []

        def record_sql(connection, cursor, statement, parameters, context, executemany):
            statements.append(statement)

        event.listen(self.connection, "before_cursor_execute", record_sql)
        try:
            first = self.statistics()
        finally:
            event.remove(self.connection, "before_cursor_execute", record_sql)
        self.assertEqual(len(statements), 1)
        self.assertTrue(statements[0].startswith("SELECT"))
        self.assertNotIn("sensor_events", statements[0])
        self.assertEqual(self.db.execute(select(RestroomSnapshot.__table__).order_by(RestroomSnapshot.id)).all(), before)
        self.sample((self.now - timedelta(weeks=1)).replace(minute=40))
        second = self.statistics()
        self.assertEqual((first.sample_count, second.sample_count), (4, 5))
        self.assertEqual((second.historical_availability_rate, second.historical_bidet_availability_rate), (0.6, 0.4))

    def test_database_failure_is_not_reported_as_zero_samples(self):
        failed_db = Mock(spec=Session)
        failed_db.execute.side_effect = OperationalError("SELECT", {}, Exception("test database failure"))
        with self.assertRaises(OperationalError):
            get_restroom_statistics(failed_db, self.room.id, now=self.now)

    def test_usable_statistics_do_not_override_far_distance(self):
        path = "/api/restrooms/recommend?x=0&y=0&bidet_required=true"
        before = self.get_json(path)
        other = self.make_room(50)
        self.four_samples(((0, 0),) * 4)
        self.four_samples(((1, 1),) * 4, room=other)
        self.assertTrue(self.statistics().is_usable)
        self.assertEqual(get_restroom_statistics(self.db, other.id, now=self.now).historical_availability_rate, 1.0)
        with patch("app.services.recommendation.get_restrooms_statistics", side_effect=
                   lambda db, ids: get_restrooms_statistics(db, ids, now=self.now)):
            after = self.get_json(path)
        self.assertEqual(after["id"], before["id"])
        self.assertIs(after["statistics_used"], False)
        self.assertEqual(after["historical_availability_rate"], 0.0)
        self.assertEqual(after["historical_bidet_availability_rate"], 0.0)

    def test_batch_matches_single_results_with_one_query_and_missing_rooms(self):
        self.four_samples()
        other = self.make_room(50)
        self.four_samples(((1, 1),) * 4, room=other)
        statements = []

        def record_sql(connection, cursor, statement, parameters, context, executemany):
            statements.append(statement)

        event.listen(self.connection, "before_cursor_execute", record_sql)
        try:
            result = get_restrooms_statistics(
                self.db, [self.room.id, other.id, self.room.id, 2147483647], now=self.now,
            )
        finally:
            event.remove(self.connection, "before_cursor_execute", record_sql)
        self.assertEqual(len(statements), 1)
        self.assertEqual(set(result), {self.room.id, other.id, 2147483647})
        for room_id, history in result.items():
            self.assertEqual(history, get_restroom_statistics(self.db, room_id, now=self.now))
        self.assertEqual(result[2147483647].sample_count, 0)
        self.assertFalse(result[2147483647].is_usable)

    def test_empty_batch_does_not_query_database(self):
        db = Mock(spec=Session)
        self.assertEqual(get_restrooms_statistics(db, [], now=self.now), {})
        db.execute.assert_not_called()


class StatisticsSettingsTests(unittest.TestCase):
    def test_defaults_and_environment_overrides(self):
        self.assertEqual(Settings.model_fields["min_stat_sample_count"].default, 30)
        self.assertEqual(Settings.model_fields["stat_lookback_days"].default, 56)
        with patch.dict(os.environ, {"MIN_STAT_SAMPLE_COUNT": "5", "STAT_LOOKBACK_DAYS": "14"}):
            settings = Settings()
        self.assertEqual((settings.min_stat_sample_count, settings.stat_lookback_days), (5, 14))

    def test_invalid_statistics_settings_are_rejected(self):
        values = get_settings().model_dump()
        for key, invalid in (("min_stat_sample_count", 0), ("min_stat_sample_count", -1),
                             ("stat_lookback_days", 0), ("stat_lookback_days", 3651),
                             ("min_stat_sample_count", "invalid"), ("stat_lookback_days", 1.5)):
            with self.subTest(key=key, invalid=invalid):
                with self.assertRaises(ValidationError):
                    Settings(_env_file=None, **(values | {key: invalid}))


if __name__ == "__main__":
    unittest.main()
