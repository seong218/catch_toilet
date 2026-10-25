"""Defensive regression checks in isolated PostgreSQL schemas only."""

from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timedelta, timezone
import json
from math import isfinite
from unittest.mock import patch

from fastapi import WebSocketDisconnect
from sqlalchemy import select

from app.main import app
from app.models import Sensor, SensorEvent, Stall
from app.services.location import InvalidDistanceError, distance_to
from app.services.retention import purge_sensor_events
import test_restrooms_api as restroom_tests
import test_sensors_api as sensor_tests


class SafeCoordinatesTests(restroom_tests.RestroomAPIFixture):
    def test_extreme_finite_coordinates_are_422_on_all_read_routes(self):
        rooms = self.seed()
        room_id = next(iter(rooms.values()))
        for path in ("/api/restrooms", f"/api/restrooms/{room_id}", "/api/restrooms/recommend"):
            for value in (1.7976931348623157e308, -1.7976931348623157e308, 1000001):
                response = self.client.get(path, params={"x": value, "y": value})
                self.assertEqual(response.status_code, 422)
                self.assertNotIn("input", response.json()["detail"][0])
            response = self.client.get(path, params={"x": 1000000, "y": -1000000})
            self.assertEqual(response.status_code, 200)
            result = response.json()
            for room in result if isinstance(result, list) else [result]:
                self.assertTrue(isfinite(room["distance"]))

    def test_distance_calculation_rejects_nonfinite_result(self):
        with self.assertRaises(InvalidDistanceError):
            distance_to((-1.7976931348623157e308, 0), 1.7976931348623157e308, 0)


class SensorIntegrityTests(sensor_tests.SensorAPIFixture):
    def send(self, occupied, *, device="test-sensor", **legacy_fields):
        return self.client.post("/api/sensors/stall", json={
            "device_id": device, "occupied": occupied, **legacy_fields,
        }, headers=self.auth_headers(device))

    def test_legacy_sequence_is_ignored_and_stored_value_is_preserved(self):
        with self.sessions.begin() as db:
            db.get(Sensor, self.sensor_id).last_sequence = 40
        self.assertEqual(self.send(False).json(), {"success": True, "changed": False})
        self.assertEqual(self.send(True, sequence=30).json(), {"success": True, "changed": True})
        self.assertEqual(self.send(False, sequence=29).json(), {"success": True, "changed": True})
        for value in (None, True, "unused", 0, -1, 9223372036854775808):
            self.assertEqual(self.send(False, sequence=value).json(), {"success": True, "changed": False})
        self.assertEqual(len(self.snapshot()[2]), 2)
        with self.sessions() as db:
            sensor = db.get(Sensor, self.sensor_id)
            self.assertEqual(sensor.last_sequence, 40)
            self.assertFalse(sensor.last_occupied)
            self.assertIsNotNone(sensor.last_seen_at)

    def test_concurrent_identical_state_commits_once_without_sequence(self):
        with ThreadPoolExecutor(max_workers=2) as pool:
            results = list(pool.map(lambda _: self.send(True), range(2)))
        self.assertEqual([result.status_code for result in results], [200, 200])
        self.assertEqual(sorted(result.json()["changed"] for result in results), [False, True])
        self.assertEqual(len(self.snapshot()[2]), 1)

    def test_rate_limit_does_not_refresh_observation_or_write_or_broadcast(self):
        self.settings.sensor_rate_burst = 1
        self.settings.sensor_rate_per_second = 0.1
        self.assertEqual(self.send(False).status_code, 200)
        before = self.snapshot()
        with self.sessions() as db:
            seen_before = db.get(Sensor, self.sensor_id).last_seen_at
        with patch.object(app.state.connection_manager, "broadcast") as broadcast:
            response = self.send(True)
            self.assertEqual(response.status_code, 429)
            self.assertGreaterEqual(int(response.headers["retry-after"]), 1)
            broadcast.assert_not_called()
        self.assertEqual(self.snapshot(), before)
        with self.sessions() as db:
            self.assertEqual(db.get(Sensor, self.sensor_id).last_seen_at, seen_before)

    def test_global_limit_applies_across_device_keys(self):
        self.settings.sensor_global_burst = 1
        self.settings.sensor_global_rate_per_second = 0.1
        self.assertEqual(self.send(False).status_code, 200)
        # This configured but unregistered ID must be throttled before DB lookup.
        self.assertEqual(self.send(True, device="other-sensor").status_code, 429)

    def test_minimum_state_interval_rejects_flip_without_refreshing_observation(self):
        self.settings.sensor_min_state_interval_seconds = 10
        self.assertEqual(self.send(True).status_code, 200)
        before = self.snapshot()
        with self.sessions() as db:
            seen_before = db.get(Sensor, self.sensor_id).last_seen_at
        self.assertEqual(self.send(False).status_code, 429)
        self.assertEqual(self.snapshot(), before)
        with self.sessions.begin() as db:
            sensor = db.get(Sensor, self.sensor_id)
            self.assertEqual(sensor.last_seen_at, seen_before)
            db.get(Stall, self.stall_id).updated_at -= timedelta(seconds=11)
        self.assertEqual(self.send(False).status_code, 200)

    def test_special_json_and_invalid_identifiers_return_safe_422_without_writes(self):
        before = self.snapshot()
        for occupied in (float("nan"), float("inf"), float("-inf"), "\ud800"):
            payload = json.dumps({"device_id": "test-sensor", "occupied": occupied})
            response = self.client.post("/api/sensors/stall", content=payload, headers={"Content-Type": "application/json"})
            self.assertEqual(response.status_code, 422)
            self.assertTrue(all(set(error) == {"loc", "msg", "type"} for error in response.json()["detail"]))
        for device in ("\u0000", "\ud800", " test-sensor ", "a" * 129):
            response = self.client.post("/api/sensors/stall", content=json.dumps({
                "device_id": device, "occupied": True,
            }), headers={"Content-Type": "application/json"})
            self.assertEqual(response.status_code, 422)
        self.assertEqual(self.snapshot(), before)

    def test_retention_is_bounded_and_keeps_recent_and_boundary_events(self):
        cutoff = datetime.now(timezone.utc) - timedelta(days=90)
        with self.sessions.begin() as db:
            for when in (cutoff - timedelta(days=1), cutoff - timedelta(days=2), cutoff, cutoff + timedelta(days=1)):
                db.add(SensorEvent(sensor_id=self.sensor_id, event_type="occupancy_changed", value=False, created_at=when))
        with self.sessions.begin() as db:
            self.assertEqual(purge_sensor_events(db, before=cutoff, batch_size=1), 1)
        with self.sessions.begin() as db:
            self.assertEqual(purge_sensor_events(db, before=cutoff, batch_size=1), 1)
            self.assertEqual(purge_sensor_events(db, before=cutoff), 0)
            self.assertEqual(len(list(db.scalars(select(SensorEvent)))), 2)

    def test_websocket_origin_policy_allows_native_and_known_browser_only(self):
        for origin in ("https://unlisted.example", "null", "http://localhost:8080.unlisted.example"):
            with self.assertRaises(WebSocketDisconnect) as error:
                with self.client.websocket_connect("/ws", headers={"Origin": origin}):
                    self.fail("Untrusted origin accepted")
            self.assertEqual(error.exception.code, 1008)
        for headers in ({}, {"Origin": "http://localhost:8080"}):
            with self.client.websocket_connect("/ws", headers=headers):
                self.assertEqual(app.state.connection_manager.connection_count, 1)
