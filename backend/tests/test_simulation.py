"""Simulation is authenticated, ephemeral, and shares the normal read pipeline."""
from secrets import token_urlsafe
from unittest.mock import patch
import unittest

from pydantic import SecretStr
from sqlalchemy import select

from app.main import app
from app.models import Restroom, Sensor, SensorEvent, Stall
from app.seed import seed_dimigo_data
from app.simulate import Client, SimulationError, parse_pattern, random_states
from app.simulation_state import current_overrides
import test_sensors_api as sensor_tests


class SimulationAPITests(sensor_tests.SensorAPIFixture):
    def setUp(self):
        super().setUp()
        self.key = token_urlsafe(32)
        self.settings = self.settings.model_copy(update={
            "enable_simulation": True, "simulation_api_key": SecretStr(self.key),
        })
        self.enterContext(patch("app.simulation_state.get_settings", lambda: self.settings))
        self.headers = {"Authorization": f"Bearer {self.key}"}

    def change(self, states, status=200):
        response = self.client.post("/api/simulation/stalls", json={"states": states}, headers=self.headers)
        self.assertEqual(response.status_code, status, response.text)
        return response.json()

    def reset(self, ids=None):
        response = self.client.post("/api/simulation/reset", json={"stall_ids": ids}, headers=self.headers)
        self.assertEqual(response.status_code, 200, response.text)
        return response.json()

    def detail(self):
        response = self.client.get(f"/api/restrooms/{self.room_id}")
        self.assertEqual(response.status_code, 200)
        return response.json()

    def test_disabled_missing_key_and_wrong_credentials(self):
        body = {"states": [{"stall_id": self.stall_id, "occupied": True}]}
        self.assertEqual(self.client.post("/api/simulation/stalls", json=body).status_code, 401)
        self.settings = self.settings.model_copy(update={"enable_simulation": False})
        self.assertEqual(self.client.post("/api/simulation/stalls", json=body, headers=self.headers).status_code, 404)
        self.settings = self.settings.model_copy(update={"enable_simulation": True, "simulation_api_key": SecretStr("")})
        self.assertEqual(self.client.post("/api/simulation/stalls", json=body, headers=self.headers).status_code, 503)
        self.assertEqual(current_overrides(), {})

    def test_override_reset_and_real_sensor_updates_are_separate(self):
        before = self.snapshot()
        with self.client.websocket_connect("/ws") as ws:
            self.change([{"stall_id": self.stall_id, "occupied": False}])
            event = ws.receive_json()
            self.assertTrue(event["is_simulated"])
            self.assertEqual(event["simulated_stalls"], 1)
            self.assertEqual(self.snapshot(), before)
            self.assertEqual(self.change([{"stall_id": self.stall_id, "occupied": False}])["changed"], 0)
            # Actual sensor storage keeps advancing behind the temporary state.
            self.post(True)
            observed = ws.receive_json()
            self.assertFalse(observed["occupied"])
            self.assertTrue(observed["is_simulated"])
            self.assertTrue(self.snapshot()[0])
            self.assertEqual(len(self.snapshot()[2]), 1)
            self.reset()
            restored = ws.receive_json()
            self.assertTrue(restored["occupied"])
            self.assertFalse(restored["is_simulated"])
            self.assertEqual(restored["simulated_stalls"], 0)
        self.assertTrue(self.detail()["stalls"][0]["occupied"])
        with self.sessions() as db:
            self.assertEqual(db.get(Sensor, self.sensor_id).last_sequence, 1)

    def test_unknown_override_and_reset_to_unknown_reach_websocket(self):
        with self.sessions.begin() as db:
            db.get(Stall, self.stall_id).occupied = None
        before = self.snapshot()
        with self.client.websocket_connect("/ws") as ws:
            self.change([{"stall_id": self.stall_id, "occupied": False}])
            ws.receive_json()
            self.change([{"stall_id": self.stall_id, "occupied": None}])
            self.assertIsNone(ws.receive_json()["occupied"])
            self.assertEqual(self.detail()["unknown_stalls"], 1)
            self.reset([self.stall_id])
            event = ws.receive_json()
            self.assertIsNone(event["occupied"])
            self.assertFalse(event["is_simulated"])
        self.assertEqual(self.snapshot(), before)

    def test_invalid_batch_is_atomic_and_values_are_strict(self):
        self.change([{"stall_id": self.stall_id, "occupied": True},
                     {"stall_id": 2147483647, "occupied": False}], 404)
        for states in (
            [{"stall_id": self.stall_id, "occupied": 1}],
            [{"stall_id": self.stall_id, "occupied": True}] * 2,
            [{"stall_id": n, "occupied": False} for n in range(1, 66)],
            [{"stall_id": True, "occupied": False}],
        ):
            self.change(states, 422)
        self.assertEqual(current_overrides(), {})
        self.assertFalse(self.detail()["stalls"][0]["occupied"])

    def test_all_39_campus_stalls_feed_list_detail_and_server_recommendation(self):
        with self.sessions.begin() as db:
            seed_dimigo_data(db)
            rows = list(db.execute(select(Stall.id, Stall.restroom_id).join(Restroom).where(Restroom.data_key.is_not(None))))
        self.assertEqual(len(rows), 39)
        with self.client.websocket_connect("/ws") as ws:
            self.change([{"stall_id": row.id, "occupied": True} for row in rows])
            for _ in rows:
                self.assertTrue(ws.receive_json()["is_simulated"])
            selected = rows[7]  # Main building male 1F, a bidet stall.
            self.change([{"stall_id": selected.id, "occupied": False}])
            ws.receive_json()
            result = self.client.get("/api/restrooms/recommend?x=0&y=0&gender=male&bidet_required=true")
            self.assertEqual(result.status_code, 200, result.text)
            self.assertEqual(result.json()["id"], selected.restroom_id)
            self.assertFalse(result.json()["statistics_used"])
            self.assertEqual(result.json()["available_bidet_stalls"], 1)
        rooms = self.client.get("/api/restrooms").json()
        self.assertEqual(sum(room["simulated_stalls"] for room in rooms), 39)
        with self.sessions() as db:
            self.assertEqual(db.scalars(select(SensorEvent)).all(), [])
            self.assertTrue(all(db.get(Stall, row.id).occupied is None for row in rows))
            self.assertTrue(all(sensor.last_sequence == 0 for sensor in db.scalars(select(Sensor))))

    def test_read_failure_leaves_previous_override_intact(self):
        from sqlalchemy.exc import OperationalError
        self.change([{"stall_id": self.stall_id, "occupied": True}])
        with patch("app.services.simulation.get_restroom", side_effect=OperationalError("read", {}, Exception())):
            self.change([{"stall_id": self.stall_id, "occupied": False}], 503)
        self.assertTrue(self.detail()["stalls"][0]["occupied"])


class SimulationCLITests(unittest.TestCase):
    def test_random_is_repeatable_and_extremes_are_valid(self):
        rooms = [{"stalls": [{"id": n} for n in range(1, 40)]}]
        self.assertEqual(random_states(rooms, 0.5, 42), random_states(rooms, 0.5, 42))
        self.assertTrue(all(not s["occupied"] for s in random_states(rooms, 0)))
        self.assertTrue(all(s["occupied"] for s in random_states(rooms, 1)))

    def test_pattern_uses_room_numbers_and_checks_length(self):
        stalls = [{"id": 31, "stall_number": 2}, {"id": 18, "stall_number": 1}]
        self.assertEqual(parse_pattern("?, 0", stalls), [
            {"stall_id": 18, "occupied": None}, {"stall_id": 31, "occupied": False},
        ])
        for value in ("1", "0,1,?", "true,0"):
            with self.assertRaises(SimulationError):
                parse_pattern(value, stalls)

    def test_credentials_require_local_http_or_https_destination(self):
        for url in ("http://example.com", "https://user:pass@example.com", "file:///tmp/a"):
            with self.assertRaises(SimulationError):
                Client(url)
