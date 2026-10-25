"""Sensor API tests with real commits and concurrent PostgreSQL connections.

Each test owns a temporary schema. Only that schema is dropped during cleanup;
the application's development data is never used or changed.
"""

from concurrent.futures import ThreadPoolExecutor
from collections import defaultdict
from itertools import count
from datetime import datetime, timezone
from pathlib import Path
from secrets import token_urlsafe
from threading import Barrier
import unittest
from unittest.mock import Mock, patch
from uuid import uuid4

from alembic import command
from alembic.config import Config
from fastapi.testclient import TestClient
from pydantic import SecretStr
from sqlalchemy import create_engine, event, select, text
from sqlalchemy.exc import OperationalError
from sqlalchemy.orm import Session, sessionmaker
from sqlalchemy.schema import CreateSchema, DropSchema

from app.config import get_settings
from app.db import engine, get_db
from app.main import app
from app.models import Restroom, Sensor, SensorEvent, Stall


class SensorAPIFixture(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.addClassCleanup(engine.dispose)

    def setUp(self):
        self.schema = f"test_sensors_{uuid4().hex}"
        with engine.begin() as connection:
            connection.execute(CreateSchema(self.schema))
        self.addCleanup(self.drop_schema)
        self.test_engine = create_engine(
            engine.url,
            connect_args={
                "connect_timeout": 5,
                "options": f"-c search_path={self.schema} -c statement_timeout=5000",
            },
        )
        self.addCleanup(self.test_engine.dispose)
        config = Config(str(Path(__file__).resolve().parents[1] / "alembic.ini"))
        with self.test_engine.begin() as connection:
            config.attributes["connection"] = connection
            command.upgrade(config, "head")
        self.sessions = sessionmaker(bind=self.test_engine, autoflush=False, expire_on_commit=False)

        def test_db():
            with self.sessions() as db:
                yield db

        app.dependency_overrides[get_db] = test_db
        self.addCleanup(app.dependency_overrides.clear)
        self.sensor_keys = {
            device: token_urlsafe(32) for device in (
                "test-sensor", "test-sensor-2", "other-sensor",
                "missing", "TEST-SENSOR",
            )
        }
        self.sequences = defaultdict(lambda: count(1))
        self.settings = get_settings().model_copy(update={
            "enable_statistics_collection": False,
            "sensor_rate_burst": 1000, "sensor_rate_per_second": 1000,
            "sensor_global_burst": 1000, "sensor_global_rate_per_second": 1000,
            "sensor_min_state_interval_seconds": 0,
            "sensor_api_keys": {device: SecretStr(key) for device, key in self.sensor_keys.items()},
        })
        app.dependency_overrides[get_settings] = lambda: self.settings
        self.enterContext(patch("app.main.get_settings", return_value=self.settings))
        # One lifespan/portal models one server event loop for HTTP + WebSocket.
        self.client = self.enterContext(TestClient(app))
        self.client.headers.update(self.auth_headers("test-sensor"))
        with self.sessions.begin() as db:
            room = Restroom(name="센서 API 테스트", building="테스트 건물", floor=1, x=0, y=0)
            stall = Stall(
                restroom=room, stall_number=1, occupied=False, has_bidet=True,
                updated_at=datetime(2020, 1, 1, tzinfo=timezone.utc),
            )
            sensor = Sensor(restroom=room, stall=stall, device_id="test-sensor", sensor_type="SW-520D")
            db.add_all([room, stall, sensor])
            db.flush()
            self.room_id, self.stall_id, self.sensor_id = room.id, stall.id, sensor.id

    def drop_schema(self):
        with engine.begin() as connection:
            connection.execute(DropSchema(self.schema, cascade=True))

    def snapshot(self):
        # A fresh connection/session observes only committed state.
        with self.sessions() as db:
            stall = db.get(Stall, self.stall_id)
            events = db.execute(select(SensorEvent.__table__).order_by(SensorEvent.id)).all()
            return (stall.occupied, stall.updated_at, events)

    def auth_headers(self, device_id):
        return {"Authorization": f"Bearer {self.sensor_keys[device_id]}"}

    def post(self, occupied, device_id="test-sensor", expected_status=200):
        response = self.client.post(
            "/api/sensors/stall", json={"device_id": device_id, "occupied": occupied, "sequence": next(self.sequences[device_id])},
            headers=self.auth_headers(device_id),
        )
        self.assertEqual(response.status_code, expected_status, response.text)
        self.assertEqual(response.headers["content-type"], "application/json")
        return response.json()


class SensorAPITests(SensorAPIFixture):
    def test_unchanged_heartbeat_refreshes_liveness_without_events_or_broadcast(self):
        before = self.snapshot()
        with patch.object(app.state.connection_manager, "broadcast") as broadcast:
            self.assertFalse(self.post(False)["changed"])
            with self.sessions() as db:
                first = db.get(Sensor, self.sensor_id).last_seen_at
            self.assertIsNotNone(first)
            # Exact retransmission is not a new observation.
            replay = self.client.post("/api/sensors/stall", json={
                "device_id": "test-sensor", "occupied": False, "sequence": 1,
            })
            self.assertEqual(replay.status_code, 200)
            with self.sessions() as db:
                self.assertEqual(db.get(Sensor, self.sensor_id).last_seen_at, first)
            self.assertFalse(self.post(False)["changed"])
            with self.sessions() as db:
                self.assertGreater(db.get(Sensor, self.sensor_id).last_seen_at, first)
            self.assertEqual(self.snapshot(), before)
            broadcast.assert_not_called()

    def test_authentication_failure_preserves_state_events_and_broadcast(self):
        before = self.snapshot()
        with patch.object(app.state.connection_manager, "broadcast") as broadcast:
            for headers in (
                {"Authorization": ""}, {"Authorization": f"Bearer {token_urlsafe(32)}"},
                self.auth_headers("other-sensor"),
            ):
                response = self.client.post(
                    "/api/sensors/stall", json={"device_id": "test-sensor", "occupied": True, "sequence": 1},
                    headers=headers,
                )
                self.assertEqual(response.status_code, 401)
                self.assertEqual(self.snapshot(), before)
            broadcast.assert_not_called()

    def test_false_true_true_false_commits_only_two_events(self):
        previous_timestamp = self.snapshot()[1]
        for occupied, changed, values in (
            (False, False, []), (True, True, [True]),
            (True, False, [True]), (False, True, [True, False]),
        ):
            with self.subTest(occupied=occupied, changed=changed, events=len(values)):
                self.assertEqual(self.post(occupied), {"success": True, "changed": changed})
                state, timestamp, events = self.snapshot()
                self.assertIs(state, occupied)
                self.assertEqual([row.value for row in events], values)
                self.assertTrue(all(row.sensor_id == self.sensor_id for row in events))
                self.assertTrue(all(row.event_type == "occupancy_changed" for row in events))
                if changed:
                    self.assertGreater(timestamp, previous_timestamp)
                    self.assertEqual(events[-1].created_at, timestamp)
                else:
                    self.assertEqual(timestamp, previous_timestamp)
                previous_timestamp = timestamp
                detail = self.client.get(f"/api/restrooms/{self.room_id}").json()
                self.assertIs(detail["stalls"][0]["occupied"], occupied)
                self.assertEqual(detail["available_stalls"], int(not occupied))
                self.assertEqual(detail["available_bidet_stalls"], int(not occupied))

    def test_unregistered_and_nonexact_device_ids_return_404(self):
        before = self.snapshot()
        for device_id in ("missing", "TEST-SENSOR"):
            self.assertEqual(self.post(True, device_id, 404), {"detail": "Sensor not found"})
        self.assertEqual(self.snapshot(), before)

    def test_inactive_sensor_returns_409_even_for_unchanged_state(self):
        with self.sessions.begin() as db:
            db.get(Sensor, self.sensor_id).active = False
        before = self.snapshot()
        for occupied in (False, True):
            self.assertEqual(self.post(occupied, expected_status=409), {"detail": "Sensor is inactive"})
        self.assertEqual(self.snapshot(), before)

    def test_missing_stall_mapping_returns_409(self):
        # Production constraints already forbid these records. Simulate legacy
        # corruption ONLY in the private test schema to verify the API guard.
        with self.test_engine.begin() as connection:
            connection.execute(text("ALTER TABLE sensors DROP CONSTRAINT fk_sensors_stall_restroom"))
            connection.execute(text("ALTER TABLE sensors ALTER COLUMN stall_id DROP NOT NULL"))
        before = self.snapshot()
        for stall_id in (None, 999999):
            with self.sessions.begin() as db:
                db.get(Sensor, self.sensor_id).stall_id = stall_id
            self.assertEqual(self.post(True, expected_status=409), {"detail": "Sensor mapping is invalid"})
            self.assertEqual(self.snapshot(), before)

    def test_mismatched_restroom_returns_409(self):
        with self.test_engine.begin() as connection:
            connection.execute(text("ALTER TABLE sensors DROP CONSTRAINT fk_sensors_stall_restroom"))
        with self.sessions.begin() as db:
            other = Restroom(name="다른 화장실", building="테스트", floor=2, x=0, y=0)
            db.add(other)
            db.flush()
            db.get(Sensor, self.sensor_id).restroom_id = other.id
        before = self.snapshot()
        self.assertEqual(self.post(True, expected_status=409), {"detail": "Sensor mapping is invalid"})
        self.assertEqual(self.snapshot(), before)

    def test_missing_restroom_returns_409(self):
        with self.test_engine.begin() as connection:
            connection.execute(text("ALTER TABLE sensors DROP CONSTRAINT fk_sensors_restroom"))
            connection.execute(text("ALTER TABLE stalls DROP CONSTRAINT fk_stalls_restroom"))
            connection.execute(text("DELETE FROM restrooms"))
        before = self.snapshot()
        self.assertEqual(self.post(True, expected_status=409), {"detail": "Sensor mapping is invalid"})
        self.assertEqual(self.snapshot(), before)

    def test_payload_validation_is_strict_and_does_not_write(self):
        payloads = [{}, {"device_id": "test-sensor"}, {"occupied": True}, [], None]
        payloads += [{"device_id": value, "occupied": True} for value in (None, "", " \t\n", 1, True, [])]
        payloads += [{"device_id": "test-sensor", "occupied": value} for value in (None, 0, 1, 0.0, 1.0, "true", "false", "yes", [], {})]
        before = self.snapshot()
        for payload in payloads:
            with self.subTest(payload=payload):
                if isinstance(payload, dict):
                    payload["sequence"] = 1
                response = self.client.post("/api/sensors/stall", json=payload)
                self.assertEqual(response.status_code, 422, response.text)
                self.assertIsInstance(response.json()["detail"], list)
        malformed = self.client.post(
            "/api/sensors/stall", content='{"device_id":', headers={"Content-Type": "application/json"}
        )
        self.assertEqual(malformed.status_code, 422)
        self.assertIsInstance(malformed.json()["detail"], list)
        self.assertEqual(self.snapshot(), before)

    def test_event_insert_failure_rolls_back_stall_update(self):
        before = self.snapshot()
        updates = []

        def fail_event_insert(connection, cursor, statement, parameters, context, executemany):
            if statement.startswith("UPDATE stalls"):
                updates.append(statement)
            if statement.startswith("INSERT INTO sensor_events"):
                raise OperationalError("INSERT", {}, Exception("private driver failure"))

        event.listen(self.test_engine, "before_cursor_execute", fail_event_insert)
        try:
            self.assertEqual(self.post(True, expected_status=503), {"detail": "Database unavailable"})
        finally:
            event.remove(self.test_engine, "before_cursor_execute", fail_event_insert)
        self.assertEqual(len(updates), 1)
        self.assertEqual(self.snapshot(), before)

    def test_commit_failure_does_not_return_success_or_persist_writes(self):
        before = self.snapshot()

        def fail_commit(connection):
            raise OperationalError("COMMIT", {}, Exception("private commit failure"))

        event.listen(self.test_engine, "commit", fail_commit)
        try:
            self.assertEqual(self.post(True, expected_status=503), {"detail": "Database unavailable"})
        finally:
            event.remove(self.test_engine, "commit", fail_commit)
        self.assertEqual(self.snapshot(), before)

    def test_database_unavailable_returns_503(self):
        before = self.snapshot()
        failed_db = Mock(spec=Session)
        failed_db.begin.side_effect = OperationalError("CONNECT", {}, Exception("private connection failure"))
        app.dependency_overrides[get_db] = lambda: failed_db
        self.assertEqual(self.post(True, expected_status=503), {"detail": "Database unavailable"})
        self.assertEqual(self.snapshot(), before)

    def test_two_sensors_updating_one_stall_concurrently_create_one_event(self):
        with self.sessions.begin() as db:
            second = Sensor(
                device_id="test-sensor-2", restroom_id=self.room_id, stall_id=self.stall_id,
                sensor_type="SW-520D",
            )
            db.add(second)
        ready = Barrier(2)

        def send(device_id):
            ready.wait(timeout=5)
            return self.client.post(
                "/api/sensors/stall", json={"device_id": device_id, "occupied": True, "sequence": 1},
                headers=self.auth_headers(device_id),
            )

        with ThreadPoolExecutor(max_workers=2) as executor:
            futures = [executor.submit(send, device_id) for device_id in ("test-sensor", "test-sensor-2")]
            responses = [future.result(timeout=10) for future in futures]
        self.assertTrue(all(response.status_code == 200 for response in responses), [r.text for r in responses])
        self.assertEqual(sorted(r.json()["changed"] for r in responses), [False, True])
        state, _, events = self.snapshot()
        self.assertTrue(state)
        self.assertEqual([row.value for row in events], [True])

    def test_openapi_request_and_response_fields(self):
        spec = self.client.get("/openapi.json").json()
        self.assertEqual(set(spec["paths"]["/api/sensors/stall"]), {"post"})
        schemas = spec["components"]["schemas"]
        self.assertEqual(set(schemas["SensorUpdateRequest"]["required"]), {"device_id", "occupied", "sequence"})
        response = schemas["SensorUpdateResponse"]
        self.assertEqual(set(response["properties"]), {"success", "changed"})
        self.assertEqual(set(response["required"]), {"success", "changed"})
        operation = spec["paths"]["/api/sensors/stall"]["post"]
        self.assertEqual(operation["security"], [{"SensorBearer": []}])
        self.assertIn("401", operation["responses"])
        self.assertEqual(spec["components"]["securitySchemes"]["SensorBearer"]["scheme"], "bearer")
        self.assertEqual(operation["requestBody"]["content"]["application/json"]["schema"], {
            "$ref": "#/components/schemas/SensorUpdateRequest",
        })


if __name__ == "__main__":
    unittest.main()
