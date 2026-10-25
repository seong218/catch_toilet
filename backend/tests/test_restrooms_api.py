"""Read API contract tests against PostgreSQL in a rolled-back test schema."""

from pathlib import Path
import unittest
from unittest.mock import Mock
from uuid import uuid4

from alembic import command
from alembic.config import Config
from fastapi.testclient import TestClient
from sqlalchemy import event, select, text
from sqlalchemy.exc import OperationalError
from sqlalchemy.orm import Session

from app.db import engine, get_db
from app.main import app
from app.models import Restroom, Sensor, Stall
from app.seed import seed_development_data


ROOM_FIELDS = {
    "id", "name", "building", "floor", "x", "y", "distance",
    "total_stalls", "available_stalls", "available_bidet_stalls",
    "latitude", "longitude", "gender", "location_source", "bidet_stalls", "accessible_stalls", "unknown_stalls", "simulated_stalls",
}
STALL_FIELDS = {"id", "stall_number", "occupied", "has_bidet", "is_accessible", "is_simulated"}


class RestroomAPIFixture(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.addClassCleanup(engine.dispose)
        cls.connection = engine.connect()
        cls.addClassCleanup(cls.connection.close)
        cls.transaction = cls.connection.begin()
        cls.addClassCleanup(cls.transaction.rollback)
        schema = f"test_restrooms_{uuid4().hex}"
        cls.connection.execute(text(f'CREATE SCHEMA "{schema}"'))
        cls.connection.execute(text(f'SET LOCAL search_path TO "{schema}"'))
        config = Config(str(Path(__file__).resolve().parents[1] / "alembic.ini"))
        config.attributes["connection"] = cls.connection
        command.upgrade(config, "head")

    def setUp(self):
        savepoint = self.connection.begin_nested()
        self.addCleanup(savepoint.rollback)
        self.db = Session(bind=self.connection, join_transaction_mode="create_savepoint")
        self.addCleanup(self.db.close)
        app.dependency_overrides[get_db] = lambda: self.db
        self.addCleanup(app.dependency_overrides.clear)
        # The live server check covers lifespan. Here the class owns the pool
        # and transaction, so per-test app shutdown must not dispose that pool.
        self.client = TestClient(app)
        self.addCleanup(self.client.close)

    def seed(self):
        seed_development_data(self.db)
        return {room.name: room.id for room in self.db.scalars(select(Restroom))}

    def get_json(self, path, expected_status=200, **kwargs):
        response = self.client.get(path, **kwargs)
        self.assertEqual(response.status_code, expected_status, response.text)
        self.assertEqual(response.headers["content-type"], "application/json")
        return response.json()


class RestroomAPITests(RestroomAPIFixture):
    def test_seed_list_and_details_match_exact_contract(self):
        self.seed()
        rooms = self.get_json("/api/restrooms")
        expected_counts = {
            "본관 1층 화장실": (3, 2, 1),
            "본관 2층 화장실": (5, 3, 2),
            "체육관 화장실": (4, 2, 1),
        }
        self.assertEqual({room["name"] for room in rooms}, set(expected_counts))
        self.assertEqual([room["id"] for room in rooms], sorted(room["id"] for room in rooms))
        for room in rooms:
            with self.subTest(room=room["name"]):
                self.assertEqual(set(room), ROOM_FIELDS)
                self.assertIsNone(room["distance"])
                self.assertEqual(
                    (room["total_stalls"], room["available_stalls"], room["available_bidet_stalls"]),
                    expected_counts[room["name"]],
                )
                detail = self.get_json(f"/api/restrooms/{room['id']}")
                self.assertEqual(set(detail), ROOM_FIELDS | {"stalls"})
                self.assertEqual({key: detail[key] for key in ROOM_FIELDS}, room)
                stalls = detail["stalls"]
                self.assertEqual(len(stalls), detail["total_stalls"])
                self.assertEqual(sum(not s["occupied"] for s in stalls), detail["available_stalls"])
                self.assertEqual(sum(not s["occupied"] and s["has_bidet"] for s in stalls), detail["available_bidet_stalls"])
                self.assertEqual([s["stall_number"] for s in stalls], sorted(s["stall_number"] for s in stalls))
                for stall in stalls:
                    self.assertEqual(set(stall), STALL_FIELDS)
                    self.assertIs(type(stall["occupied"]), bool)
                    self.assertIs(type(stall["has_bidet"]), bool)

    def test_empty_list_and_restroom_without_stalls(self):
        self.assertEqual(self.get_json("/api/restrooms"), [])
        self.assertEqual(self.get_json("/api/restrooms?x=0&y=0"), [])
        room = Restroom(name="빈 화장실", building="test", floor=-1, x=0, y=0)
        self.db.add(room)
        self.db.flush()
        detail = self.get_json(f"/api/restrooms/{room.id}")
        self.assertEqual(detail["stalls"], [])
        for key in ("total_stalls", "available_stalls", "available_bidet_stalls"):
            self.assertEqual(detail[key], 0)
        self.assertEqual(self.get_json("/api/restrooms")[0]["total_stalls"], 0)

    def test_full_restroom_and_multiple_sensors_do_not_distort_counts(self):
        room = Restroom(name="만석 화장실", building="test", floor=1, x=0, y=0)
        stalls = [Stall(restroom=room, stall_number=n, occupied=True, has_bidet=n == 1) for n in (3, 1, 2)]
        self.db.add_all(stalls)
        self.db.flush()
        self.db.add_all([
            Sensor(restroom=room, stall=stalls[0], device_id=f"extra-{n}", sensor_type="SW-520D")
            for n in (1, 2)
        ])
        self.db.flush()
        rooms = self.get_json("/api/restrooms")
        self.assertEqual(len(rooms), 1)
        self.assertEqual((rooms[0]["total_stalls"], rooms[0]["available_stalls"], rooms[0]["available_bidet_stalls"]), (3, 0, 0))
        detail = self.get_json(f"/api/restrooms/{room.id}")
        self.assertEqual([s["stall_number"] for s in detail["stalls"]], [1, 2, 3])

    def test_optional_distance_sorting_ties_and_negative_coordinates(self):
        ids = self.seed()
        rooms = self.get_json("/api/restrooms?x=100&y=20")
        self.assertEqual([r["name"] for r in rooms], ["체육관 화장실", "본관 2층 화장실", "본관 1층 화장실"])
        self.assertEqual(rooms[0]["distance"], 0)
        detail = self.get_json(f"/api/restrooms/{ids['본관 2층 화장실']}?x=10&y=20")
        self.assertEqual(detail["distance"], 50.0)
        ties = self.get_json("/api/restrooms?x=25&y=40")
        self.assertEqual([r["distance"] for r in ties[:2]], [25.0, 25.0])
        self.assertLess(ties[0]["id"], ties[1]["id"])
        detail = self.get_json(f"/api/restrooms/{ids['본관 1층 화장실']}?x=-20&y=-20")
        self.assertEqual(detail["distance"], 50.0)

    def test_query_validation_returns_standard_422_details(self):
        for path in ("/api/restrooms", "/api/restrooms/1"):
            for provided, missing in (("x", "y"), ("y", "x")):
                with self.subTest(path=path, missing=missing):
                    body = self.get_json(path, 422, params={provided: "0"})
                    self.assertIsInstance(body["detail"], list)
                    self.assertEqual(body["detail"][0]["loc"], ["query", missing])
            for axis in ("x", "y"):
                for value in ("", "null", "abc", "NaN", "inf", "-inf", "1e309"):
                    with self.subTest(path=path, axis=axis, value=value):
                        params = {"x": "0", "y": "0", axis: value}
                        body = self.get_json(path, 422, params=params)
                        self.assertIsInstance(body["detail"], list)
                        self.assertEqual(body["detail"][0]["loc"], ["query", axis])

    def test_missing_restroom_and_invalid_id(self):
        for value in ("999999", str(10 ** 100)):
            self.assertEqual(self.get_json(f"/api/restrooms/{value}", 404), {"detail": "Restroom not found"})
        for value in ("0", "-1", "abc", "1.5", "null"):
            with self.subTest(value=value):
                body = self.get_json(f"/api/restrooms/{value}", 422)
                self.assertEqual(body["detail"][0]["loc"], ["path", "restroom_id"])

    def test_database_failure_returns_503_without_internal_details(self):
        failed_db = Mock(spec=Session)
        failed_db.execute.side_effect = OperationalError("SELECT private_query", {}, Exception("private connection details"))
        app.dependency_overrides[get_db] = lambda: failed_db
        for path in ("/api/restrooms", "/api/restrooms/1"):
            self.assertEqual(self.get_json(path, 503), {"detail": "Database unavailable"})

    def test_new_db_state_is_reflected_and_detail_uses_one_select(self):
        ids = self.seed()
        sensor = self.db.scalar(select(Sensor).where(Sensor.device_id == "stall-a-01"))
        sensor.stall.occupied = True
        self.db.flush()
        statements = []

        def record_sql(connection, cursor, statement, parameters, context, executemany):
            if statement.lstrip().upper().startswith("SELECT"):
                statements.append(statement)

        event.listen(self.connection, "before_cursor_execute", record_sql)
        try:
            detail = self.get_json(f"/api/restrooms/{ids['본관 1층 화장실']}")
        finally:
            event.remove(self.connection, "before_cursor_execute", record_sql)
        self.assertEqual(len(statements), 1)
        self.assertEqual((detail["total_stalls"], detail["available_stalls"], detail["available_bidet_stalls"]), (3, 1, 0))
        self.assertTrue(detail["stalls"][0]["occupied"])
        rooms = self.get_json("/api/restrooms")
        self.assertEqual(rooms[0]["available_stalls"], 1)
        self.assertEqual(rooms[0]["available_bidet_stalls"], 0)

    def test_openapi_keeps_all_response_fields_required(self):
        specification = self.get_json("/openapi.json")
        self.assertEqual(set(specification["paths"]), {
            "/api/health", "/api/restrooms", "/api/restrooms/{restroom_id}", "/api/sensors/stall",
            "/api/restrooms/recommend", "/api/simulation/stalls", "/api/simulation/reset",
        })
        for name, fields, nullable in (
            ("HealthResponse", {"status"}, set()),
            ("Restroom", ROOM_FIELDS, {"distance", "latitude", "longitude", "bidet_stalls"}),
            ("RestroomDetail", ROOM_FIELDS | {"stalls"}, {"distance", "latitude", "longitude", "bidet_stalls"}),
            ("Stall", STALL_FIELDS, {"occupied", "has_bidet"}),
        ):
            schema = specification["components"]["schemas"][name]
            self.assertEqual(set(schema["properties"]), fields)
            self.assertEqual(set(schema["required"]), fields)
            self.assertEqual({
                field for field, definition in schema["properties"].items()
                if any(variant.get("type") == "null" for variant in definition.get("anyOf", []))
            }, nullable)


if __name__ == "__main__":
    unittest.main()
