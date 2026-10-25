"""Tracking controls use disposable PostgreSQL schemas, never the shared DB."""

from concurrent.futures import ThreadPoolExecutor
from contextlib import redirect_stdout
from datetime import timedelta
from io import StringIO
import json
from threading import Barrier
from unittest.mock import Mock, patch

from sqlalchemy import func, select, text
from sqlalchemy.exc import OperationalError

from app import statistics_tracking as cli
from app.models import RestroomSnapshot
from app.services.statistics_collection import capture_restroom_snapshots
from app.services.statistics_tracking import get_tracking_state, set_tracking
import test_sensors_api as sensor_tests


class StatisticsTrackingTests(sensor_tests.SensorAPIFixture):
    def setUp(self):
        super().setUp()
        self.tracking_settings = self.settings.model_copy(update={"enable_statistics_collection": True})
        self.enterContext(patch("app.services.statistics_tracking.get_settings",
                                return_value=self.tracking_settings))

    def change(self, enabled):
        with self.sessions.begin() as db:
            return set_tracking(db, enabled=enabled)

    def capture(self, now=None):
        with self.sessions.begin() as db:
            return capture_restroom_snapshots(db, now=now)

    def test_defaults_to_stopped_even_with_fresh_reports(self):
        self.post(False)
        self.assertEqual(self.capture(), 0)
        with self.sessions() as db:
            state = get_tracking_state(db)
            self.assertFalse(state.enabled)
            self.assertIsNone(state.started_at)
            self.assertIsNone(state.stopped_at)
            self.assertEqual(db.scalar(select(func.count()).select_from(RestroomSnapshot)), 0)

    def test_start_persists_and_repeated_commands_preserve_transition_times(self):
        started = self.change(True)
        self.assertTrue(started.enabled)
        self.assertIsNotNone(started.started_at)
        self.assertIsNone(started.stopped_at)
        self.assertEqual(self.change(True).started_at, started.started_at)
        with self.sessions() as db:  # A new process/session sees the same state.
            self.assertEqual(get_tracking_state(db).started_at, started.started_at)
        stopped = self.change(False)
        self.assertFalse(stopped.enabled)
        self.assertGreaterEqual(stopped.stopped_at, started.started_at)
        self.assertEqual(self.change(False).stopped_at, stopped.stopped_at)

    def test_collects_only_new_reports_after_start_and_keeps_history_on_stop(self):
        self.post(False)
        started = self.change(True)
        next_minute = started.started_at.replace(second=0, microsecond=0) + timedelta(minutes=1)
        # Existing fresh observations still predate the explicit start.
        self.assertEqual(self.capture(next_minute), 0)
        self.post(False)
        self.assertEqual(self.capture(started.started_at), 0)
        self.assertEqual(self.capture(next_minute), 1)
        self.change(False)
        self.assertEqual(self.capture(next_minute + timedelta(minutes=1)), 0)
        with self.sessions() as db:
            rows = db.scalars(select(RestroomSnapshot)).all()
            self.assertEqual(len(rows), 1)
            self.assertGreaterEqual(rows[0].captured_at, started.started_at)
        restarted = self.change(True)
        self.assertGreater(restarted.started_at, started.started_at)
        self.assertIsNone(restarted.stopped_at)
        self.assertEqual(self.capture(next_minute + timedelta(minutes=1)), 0)
        self.post(False)
        self.assertEqual(self.capture(next_minute + timedelta(minutes=1)), 1)

    def test_uncommitted_start_does_not_enable_tracking(self):
        with self.sessions() as db:
            set_tracking(db, enabled=True)
            db.rollback()
        with self.sessions() as db:
            self.assertFalse(get_tracking_state(db).enabled)

    def test_concurrent_starts_share_one_start_time(self):
        barrier = Barrier(2)

        def start(_):
            barrier.wait(timeout=5)
            return self.change(True).started_at

        with ThreadPoolExecutor(max_workers=2) as pool:
            times = list(pool.map(start, range(2)))
        self.assertEqual(times[0], times[1])

    def test_stop_waits_for_inflight_sample_transaction(self):
        started = self.change(True)
        self.post(False)
        next_minute = started.started_at.replace(second=0, microsecond=0) + timedelta(minutes=1)

        def try_stop():
            with self.sessions.begin() as db:
                db.execute(text("SET LOCAL lock_timeout = '100ms'"))
                set_tracking(db, enabled=False)

        with self.sessions.begin() as db:
            self.assertEqual(capture_restroom_snapshots(db, now=next_minute), 1)
            with ThreadPoolExecutor(max_workers=1) as pool:
                with self.assertRaises(OperationalError):
                    pool.submit(try_stop).result(timeout=5)
        # Once the preceding sample commits, stop succeeds and gates later ticks.
        self.assertFalse(self.change(False).enabled)
        self.assertEqual(self.capture(next_minute + timedelta(minutes=1)), 0)

    def test_disabled_collector_rejects_start_without_changing_state(self):
        self.tracking_settings.enable_statistics_collection = False
        with self.assertRaisesRegex(ValueError, "ENABLE_STATISTICS_COLLECTION"):
            self.change(True)
        self.assertFalse(self.change(False).enabled)

    def test_cli_controls_and_reads_persistent_state(self):
        self.enterContext(patch.object(cli, "SessionLocal", self.sessions))
        self.enterContext(patch.object(cli, "engine", Mock()))
        self.enterContext(patch.object(cli, "get_settings", return_value=self.tracking_settings))
        results = []
        for action in ("status", "start", "status", "stop", "status"):
            output = StringIO()
            with patch("sys.argv", ["statistics_tracking", action]), redirect_stdout(output):
                cli.main()
            results.append(json.loads(output.getvalue()))
        self.assertEqual([result["tracking"] for result in results], [False, True, True, False, False])
        self.assertEqual(results[1]["started_at"], results[2]["started_at"])
        self.assertIsNotNone(results[3]["stopped_at"])

    def test_cli_database_error_does_not_claim_success_or_expose_parameters(self):
        sessions = Mock()
        sessions.begin.side_effect = OperationalError("private SQL", {}, Exception("secret"))
        output = StringIO()
        with patch.object(cli, "SessionLocal", sessions), patch.object(cli, "engine", Mock()):
            with patch("sys.argv", ["statistics_tracking", "start"]), redirect_stdout(output):
                with self.assertRaises(SystemExit) as error:
                    cli.main()
        self.assertEqual(output.getvalue(), "")
        self.assertNotIn("private SQL", str(error.exception))
        self.assertNotIn("secret", str(error.exception))
