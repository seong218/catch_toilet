"""All artificial observations are confined to disposable PostgreSQL schemas."""

import asyncio
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timedelta, timezone
from threading import Barrier
import unittest
from unittest.mock import AsyncMock, Mock, patch

from sqlalchemy import func, select
from sqlalchemy.exc import OperationalError

from app.models import Restroom, RestroomSnapshot, Sensor, SensorEvent, Stall, StatisticsTracking
from app.services.statistics import get_restroom_statistics, get_usage_statistics
from app.services.statistics_collection import capture_restroom_snapshots, collect_regular_statistics, _collect_once
from app.simulation_state import replace_overrides
import test_sensors_api as sensor_tests


class StatisticsCollectionTests(sensor_tests.SensorAPIFixture):
    def setUp(self):
        super().setUp()
        self.now = datetime(2026, 10, 26, 3, 0, tzinfo=timezone.utc)  # Monday noon Seoul.
        self.settings.stat_sensor_max_age_seconds = 300
        self.settings.min_stat_sample_count = 2
        for module in ("statistics", "statistics_collection"):
            self.enterContext(patch(f"app.services.{module}.get_settings", return_value=self.settings))
        with self.sessions.begin() as db:
            tracking = db.get(StatisticsTracking, 1)
            tracking.enabled = True
            tracking.started_at = datetime(2020, 1, 1, tzinfo=timezone.utc)

    def observe(self, occupied=False, *, seen=None):
        with self.sessions.begin() as db:
            sensor = db.get(Sensor, self.sensor_id)
            sensor.last_seen_at = self.now if seen is None else seen
            sensor.last_sequence = 1
            sensor.last_occupied = occupied
            db.get(Stall, self.stall_id).occupied = occupied

    def capture(self, now=None):
        with self.sessions.begin() as db:
            return capture_restroom_snapshots(db, now=self.now if now is None else now)

    def test_regular_unchanged_samples_deduplicate_same_minute_and_survive_state_changes(self):
        self.observe()
        self.assertEqual(self.capture(), 1)
        self.assertEqual(self.capture(self.now + timedelta(seconds=45)), 0)
        self.assertEqual(self.capture(self.now + timedelta(minutes=1)), 1)
        self.observe(True)
        with self.sessions() as db:
            rows = db.scalars(select(RestroomSnapshot).order_by(RestroomSnapshot.captured_at)).all()
            self.assertEqual([r.available_stalls for r in rows], [1, 1])
            self.assertTrue(all(r.bidet_sample_valid and not r.is_test_data for r in rows))
            self.assertEqual(db.scalar(select(func.count()).select_from(SensorEvent)), 0)
            history = get_restroom_statistics(db, self.room_id, now=self.now + timedelta(minutes=2))
            self.assertEqual(history.sample_count, 2)
            self.assertEqual(history.historical_availability_rate, 1)

    def test_real_api_report_starts_collection_without_occupancy_change(self):
        self.assertEqual(self.capture(), 0)  # Seed values are not live reports.
        self.post(False)
        with self.sessions.begin() as db:
            self.assertEqual(capture_restroom_snapshots(db), 1)
            self.assertEqual(db.scalar(select(func.count()).select_from(SensorEvent)), 0)

    def test_stale_future_unknown_inactive_and_unreported_states_are_not_samples(self):
        cases = [
            (Sensor, self.sensor_id, "last_seen_at", self.now - timedelta(seconds=301)),
            (Sensor, self.sensor_id, "last_seen_at", self.now + timedelta(seconds=1)),
            (Sensor, self.sensor_id, "last_seen_at", None),
            (Sensor, self.sensor_id, "last_sequence", 0),
            (Sensor, self.sensor_id, "active", False),
            (Sensor, self.sensor_id, "last_occupied", True),
            (Stall, self.stall_id, "occupied", None),
            (Restroom, self.room_id, "is_active", False),
        ]
        for model, key, field, value in cases:
            with self.subTest(field=field, value=value):
                self.observe()
                with self.sessions.begin() as db:
                    original = getattr(db.get(model, key), field)
                    setattr(db.get(model, key), field, value)
                self.assertEqual(self.capture(), 0)
                with self.sessions.begin() as db:
                    setattr(db.get(model, key), field, original)
        self.observe(seen=self.now - timedelta(seconds=300))
        self.assertEqual(self.capture(), 1)  # Freshness boundary is inclusive.

    def test_every_stall_needs_fresh_observation_and_multiple_sensors_do_not_multiply(self):
        self.observe()
        with self.sessions.begin() as db:
            db.add(Sensor(restroom_id=self.room_id, stall_id=self.stall_id,
                          device_id="extra", sensor_type="SW-520D", last_sequence=2,
                          last_occupied=False, last_seen_at=self.now))
        self.assertEqual(self.capture(), 1)
        with self.sessions.begin() as db:
            self.assertEqual(db.scalar(select(RestroomSnapshot.total_stalls)), 1)
            db.add(Stall(restroom_id=self.room_id, stall_number=2, occupied=None, has_bidet=False))
        self.assertEqual(self.capture(self.now + timedelta(minutes=1)), 0)

    def test_simulation_overlay_never_changes_real_history(self):
        self.observe(False)
        replace_overrides({self.stall_id: True})
        self.addCleanup(replace_overrides, {})
        self.assertEqual(self.capture(), 1)
        with self.sessions() as db:
            self.assertEqual(db.scalar(select(RestroomSnapshot.available_stalls)), 1)

    def test_unknown_bidet_is_excluded_only_from_bidet_history_and_report(self):
        self.observe()
        with self.sessions.begin() as db:
            db.get(Stall, self.stall_id).has_bidet = None
        self.capture()
        self.capture(self.now + timedelta(minutes=1))
        with self.sessions() as db:
            history = get_restroom_statistics(db, self.room_id, now=self.now + timedelta(minutes=2))
            self.assertEqual(history.historical_availability_rate, 1)
            self.assertEqual(history.bidet_sample_count, 0)
            self.assertIsNone(history.historical_bidet_availability_rate)
        with self.sessions.begin() as db:
            db.get(Stall, self.stall_id).has_bidet = True
        self.capture(self.now + timedelta(minutes=2))
        self.capture(self.now + timedelta(minutes=3))
        with self.sessions() as db:
            history = get_restroom_statistics(db, self.room_id, now=self.now + timedelta(minutes=4))
            self.assertEqual((history.sample_count, history.bidet_sample_count), (4, 2))
            self.assertEqual(history.historical_bidet_availability_rate, 1)
            rows = get_usage_statistics(db, now=self.now + timedelta(minutes=4))
            self.assertEqual(len(rows), 1)
            self.assertEqual((rows[0]["iso_weekday"], rows[0]["hour"]), (1, 12))
            self.assertEqual(rows[0]["average_available_stalls"], 1)
            self.assertEqual(rows[0]["average_occupied_stalls"], 0)

    def test_parallel_collectors_and_rollback_do_not_duplicate_samples(self):
        self.observe()
        with self.sessions() as db:
            self.assertEqual(capture_restroom_snapshots(db, now=self.now), 1)
            db.rollback()
        barrier = Barrier(2)

        def collect(_):
            barrier.wait(timeout=5)
            return self.capture()

        with ThreadPoolExecutor(max_workers=2) as pool:
            self.assertEqual(sorted(pool.map(collect, range(2))), [0, 1])

    def test_place_buckets_keep_counts_and_rates_separate(self):
        self.observe(False)
        with self.sessions.begin() as db:
            room = Restroom(name="다른 화장실", building="별관", floor=2, x=10, y=10)
            db.add(room)
            for number in (1, 2):
                stall = Stall(restroom=room, stall_number=number, occupied=True, has_bidet=False)
                db.add_all([stall, Sensor(
                    restroom=room, stall=stall, device_id=f"report-{number}", sensor_type="SW-520D",
                    last_sequence=1, last_occupied=True, last_seen_at=self.now,
                )])
            db.flush()
            other_id = room.id
        self.assertEqual(self.capture(), 2)
        self.observe(True)
        self.assertEqual(self.capture(self.now + timedelta(minutes=1)), 2)
        with self.sessions() as db:
            reference = self.now + timedelta(minutes=2)
            rows = {row["restroom_id"]: row for row in get_usage_statistics(db, now=reference)}
            self.assertEqual(set(rows), {self.room_id, other_id})
            first, other = rows[self.room_id], rows[other_id]
            self.assertEqual(first["sample_count"], 2)
            self.assertEqual(first["historical_availability_rate"], 0.5)
            self.assertEqual(first["historical_bidet_availability_rate"], 0.5)
            self.assertEqual(first["average_available_stalls"], 0.5)
            self.assertEqual(other["historical_availability_rate"], 0)
            self.assertEqual(other["average_occupied_stalls"], 2)
            self.assertEqual(other["building"], "별관")
            self.assertEqual(get_usage_statistics(db, restroom_id=other_id, now=reference), [other])

    def test_missing_minutes_are_not_backfilled_and_report_excludes_test_data(self):
        self.observe()
        self.capture()
        later = self.now + timedelta(days=1)
        self.assertEqual(self.capture(later), 0)
        self.observe(True, seen=later)
        self.assertEqual(self.capture(later), 1)
        with self.sessions.begin() as db:
            db.add(RestroomSnapshot(restroom_id=self.room_id, total_stalls=1,
                                   available_stalls=1, available_bidet_stalls=1,
                                   captured_at=later + timedelta(minutes=1), is_test_data=True))
        with self.sessions() as db:
            rows = get_usage_statistics(db, now=later + timedelta(minutes=2))
            self.assertEqual([(r["iso_weekday"], r["hour"], r["sample_count"]) for r in rows],
                             [(1, 12, 1), (2, 12, 1)])
            self.assertTrue(all(r["historical_availability_rate"] is None for r in rows))
            self.assertEqual(get_usage_statistics(db, restroom_id=2147483647, now=later), [])


class StatisticsSchedulerTests(unittest.IsolatedAsyncioTestCase):
    async def test_scheduler_collects_and_is_cancellable(self):
        with patch("app.services.statistics_collection.run_in_threadpool", new_callable=AsyncMock) as run:
            with patch("app.services.statistics_collection.asyncio.sleep", new_callable=AsyncMock,
                       side_effect=asyncio.CancelledError) as sleep:
                with self.assertRaises(asyncio.CancelledError):
                    await collect_regular_statistics()
        run.assert_awaited_once_with(_collect_once)
        self.assertGreater(sleep.call_args.args[0], 0)
        self.assertLessEqual(sleep.call_args.args[0], 60)

    def test_database_failure_is_logged_without_raising(self):
        sessions = Mock()
        sessions.begin.side_effect = OperationalError("private SQL", {}, Exception("secret"))
        with patch("app.services.statistics_collection.SessionLocal", sessions):
            with self.assertLogs("app.services.statistics_collection", level="WARNING") as logs:
                _collect_once()
        self.assertNotIn("private SQL", " ".join(logs.output))
        self.assertNotIn("secret", " ".join(logs.output))
