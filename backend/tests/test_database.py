"""PostgreSQL integration tests in a temporary, transaction-scoped schema."""

from datetime import datetime, timezone
from pathlib import Path
import unittest
from uuid import uuid4

from alembic import command
from alembic.autogenerate import compare_metadata
from alembic.config import Config
from alembic.runtime.migration import MigrationContext
from sqlalchemy import delete, inspect, insert, select, text
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from app.db import Base, engine
from app.models import Restroom, RestroomSnapshot, Sensor, SensorEvent, Stall
from app.seed import SeedConflictError, seed_development_data


class DatabaseTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.addClassCleanup(engine.dispose)
        cls.connection = engine.connect()
        cls.addClassCleanup(cls.connection.close)
        cls.transaction = cls.connection.begin()
        cls.addClassCleanup(cls.transaction.rollback)
        # Generated identifier only; no user input or existing data is touched.
        cls.schema = f"test_models_{uuid4().hex}"
        cls.connection.execute(text(f'CREATE SCHEMA "{cls.schema}"'))
        cls.connection.execute(text(f'SET LOCAL search_path TO "{cls.schema}"'))
        cls.config = Config(str(Path(__file__).resolve().parents[1] / "alembic.ini"))
        cls.config.attributes["connection"] = cls.connection
        command.upgrade(cls.config, "head")

    def setUp(self):
        self.savepoint = self.connection.begin_nested()
        self.db = Session(bind=self.connection, join_transaction_mode="create_savepoint")

    def tearDown(self):
        self.db.close()
        self.savepoint.rollback()

    def make_graph(self):
        restroom = Restroom(name="테스트 화장실", building="테스트 건물", floor=-1, x=-2, y=0)
        stall = Stall(restroom=restroom, stall_number=1)
        sensor = Sensor(
            restroom=restroom, stall=stall, device_id="test-device", sensor_type="SW-520D"
        )
        event = SensorEvent(sensor=sensor, event_type="occupancy_changed", value=True)
        self.db.add_all([restroom, stall, sensor, event])
        self.db.flush()
        return restroom, stall, sensor, event

    def assert_rejected(self, statement, constraint=None, sqlstate=None):
        with self.assertRaises(IntegrityError) as caught:
            with self.db.begin_nested():
                self.db.execute(statement)
        if constraint is not None:
            self.assertEqual(caught.exception.orig.diag.constraint_name, constraint)
        if sqlstate is not None:
            self.assertEqual(caught.exception.orig.sqlstate, sqlstate)

    def test_migration_round_trip_and_metadata(self):
        # Both directions run only in this disposable schema.
        command.downgrade(self.config, "base")
        self.assertEqual(inspect(self.connection).get_table_names(), ["alembic_version"])
        command.upgrade(self.config, "head")
        self.assertEqual(self.connection.scalar(text("SELECT version_num FROM alembic_version")), "0005")
        self.assertEqual(
            compare_metadata(MigrationContext.configure(self.connection), Base.metadata), []
        )

    def test_columns_separate_current_state_from_historical_counts(self):
        expected = {
            "restrooms": {"id", "name", "building", "floor", "x", "y", "created_at", "latitude", "longitude", "gender", "location_source", "bidet_stalls", "accessible_stalls", "data_key", "is_active"},
            "stalls": {"id", "restroom_id", "stall_number", "occupied", "has_bidet", "updated_at", "is_accessible"},
            "sensors": {"id", "device_id", "restroom_id", "stall_id", "sensor_type", "active", "last_sequence", "last_occupied"},
            "sensor_events": {"id", "sensor_id", "event_type", "value", "created_at"},
            "restroom_snapshots": {
                "id", "restroom_id", "total_stalls", "available_stalls",
                "available_bidet_stalls", "captured_at", "is_test_data",
            },
        }
        inspector = inspect(self.connection)
        self.assertEqual(set(inspector.get_table_names()), set(expected) | {"alembic_version"})
        for table, names in expected.items():
            with self.subTest(table=table):
                columns = inspector.get_columns(table)
                self.assertEqual({column["name"] for column in columns}, names)
                nullable = {"restrooms": {"latitude", "longitude", "bidet_stalls", "data_key"},
                            "stalls": {"occupied", "has_bidet"}}.get(table, set())
                self.assertEqual({column["name"] for column in columns if column["nullable"]}, nullable)

    def test_accessibility_migration_backfills_only_unknown_values(self):
        self.db.close()
        command.downgrade(self.config, "0004")
        restroom_id = self.connection.scalar(text(
            "INSERT INTO restrooms (name, building, floor, x, y) "
            "VALUES ('test', 'test', 1, 0, 0) RETURNING id"
        ))
        self.connection.execute(text(
            "INSERT INTO stalls (restroom_id, stall_number, occupied, has_bidet, is_accessible) "
            "VALUES (:room, 1, NULL, NULL, NULL), "
            "(:room, 2, true, false, true), (:room, 3, false, true, false)"
        ), {"room": restroom_id})
        existing_fields = text(
            "SELECT id, restroom_id, stall_number, occupied, has_bidet, updated_at "
            "FROM stalls ORDER BY id"
        )
        before = self.connection.execute(existing_fields).all()

        command.upgrade(self.config, "head")
        self.assertEqual(self.connection.execute(existing_fields).all(), before)
        self.assertEqual(self.connection.scalars(text(
            "SELECT is_accessible FROM stalls ORDER BY stall_number"
        )).all(), [False, True, False])
        column = next(column for column in inspect(self.connection).get_columns("stalls")
                      if column["name"] == "is_accessible")
        self.assertFalse(column["nullable"])
        self.assertEqual(column["default"], "false")
        # Raw SQL omits the field, so this verifies the database default itself.
        self.assertIs(self.connection.scalar(text(
            "INSERT INTO stalls (restroom_id, stall_number) "
            "VALUES (:room, 4) RETURNING is_accessible"
        ), {"room": restroom_id}), False)
        after = self.connection.execute(text("SELECT * FROM stalls ORDER BY id")).all()

        command.downgrade(self.config, "0004")
        self.assertEqual(self.connection.execute(text("SELECT * FROM stalls ORDER BY id")).all(), after)
        column = next(column for column in inspect(self.connection).get_columns("stalls")
                      if column["name"] == "is_accessible")
        self.assertTrue(column["nullable"])
        self.assertIsNone(column["default"])
        command.upgrade(self.config, "head")
        self.assertEqual(self.connection.execute(text("SELECT * FROM stalls ORDER BY id")).all(), after)

    def test_snapshot_migration_preserves_initial_data(self):
        self.make_graph()
        before = self.snapshot()
        self.db.commit()  # Release only this Session's savepoint, never the outer test transaction.
        command.downgrade(self.config, "0001")
        command.upgrade(self.config, "head")
        self.assertEqual(self.snapshot(), before)
        self.assertEqual(self.db.scalars(select(RestroomSnapshot)).all(), [])
        self.db.close()
        command.downgrade(self.config, "0001")
        self.assertNotIn("restroom_snapshots", inspect(self.connection).get_table_names())
        self.assertEqual(self.snapshot(), before)
        self.db.close()
        command.upgrade(self.config, "head")

    def test_relationships_defaults_and_timestamps(self):
        restroom, stall, sensor, event = self.make_graph()
        self.db.add(Stall(restroom=restroom, stall_number=2, has_bidet=True, is_accessible=True))
        self.db.add(Sensor(
            restroom=restroom, stall=stall, device_id="TEST-device", sensor_type="SW-520D"
        ))
        self.db.add(SensorEvent(sensor=sensor, event_type="occupancy_changed", value=False))
        self.db.flush()
        self.db.expire_all()
        self.assertEqual([s.stall_number for s in restroom.stalls], [1, 2])
        self.assertEqual(len(restroom.sensors), 2)
        self.assertEqual(len(stall.sensors), 2)
        self.assertIs(stall.restroom, restroom)
        self.assertIs(sensor.restroom, restroom)
        self.assertIs(sensor.stall, stall)
        self.assertIs(event.sensor, sensor)
        self.assertEqual({e.value for e in sensor.events}, {True, False})
        self.assertFalse(stall.occupied)
        self.assertFalse(stall.has_bidet)
        self.assertIs(stall.is_accessible, False)
        self.assertIs(restroom.stalls[1].is_accessible, True)
        self.assertTrue(sensor.active)
        for timestamp in (restroom.created_at, stall.updated_at, event.created_at):
            self.assertIsNotNone(timestamp.utcoffset())

    def test_device_and_stall_number_uniqueness(self):
        restroom, stall, sensor, _ = self.make_graph()
        self.assert_rejected(
            insert(Sensor).values(device_id=sensor.device_id, restroom_id=restroom.id,
                                  stall_id=stall.id, sensor_type="SW-520D"),
            constraint="uq_sensors_device_id",
        )
        self.assert_rejected(
            insert(Stall).values(restroom_id=restroom.id, stall_number=1),
            constraint="uq_stalls_restroom_number",
        )
        other = Restroom(name="다른 화장실", building="테스트 건물", floor=2, x=0, y=1)
        self.db.add(Stall(restroom=other, stall_number=1))
        self.db.flush()  # The same number is allowed in a different restroom.

    def test_foreign_keys_and_restroom_mapping(self):
        restroom, stall, _, _ = self.make_graph()
        other = Restroom(name="다른 화장실", building="테스트 건물", floor=2, x=0, y=1)
        self.db.add(other)
        self.db.flush()
        cases = [
            (insert(Stall).values(restroom_id=2147483647, stall_number=1), "fk_stalls_restroom"),
            (insert(SensorEvent).values(sensor_id=2147483647, event_type="occupancy_changed", value=True),
             "fk_sensor_events_sensor"),
            (insert(Sensor).values(device_id="test-mismatch", restroom_id=other.id,
                                   stall_id=stall.id, sensor_type="SW-520D"), "fk_sensors_stall_restroom"),
            (insert(Sensor).values(device_id="test-orphan", restroom_id=restroom.id,
                                   stall_id=2147483647, sensor_type="SW-520D"), "fk_sensors_stall_restroom"),
        ]
        for statement, constraint in cases:
            with self.subTest(constraint=constraint):
                self.assert_rejected(statement, constraint=constraint)

    def test_invalid_values_are_rejected(self):
        restroom, stall, sensor, _ = self.make_graph()
        for value in (float("nan"), float("inf"), float("-inf")):
            for axis in ("x", "y"):
                with self.subTest(axis=axis, value=value):
                    values = dict(name="test", building="test", floor=1, x=0, y=0)
                    values[axis] = value
                    self.assert_rejected(insert(Restroom).values(**values), sqlstate="23514")
        cases = [
            insert(Stall).values(restroom_id=restroom.id, stall_number=0),
            insert(Sensor).values(device_id=" \t\n", restroom_id=restroom.id,
                                  stall_id=stall.id, sensor_type="SW-520D"),
            insert(SensorEvent).values(sensor_id=sensor.id, event_type="", value=False),
            insert(Restroom).values(name="", building="test", floor=1, x=0, y=0),
        ]
        for statement in cases:
            self.assert_rejected(statement, sqlstate="23514")
        self.assert_rejected(
            insert(SensorEvent).values(sensor_id=sensor.id, event_type="occupancy_changed", value=None),
            sqlstate="23502",
        )
        self.assert_rejected(
            insert(Stall).values(restroom_id=restroom.id, stall_number=2, is_accessible=None),
            sqlstate="23502",
        )

    def test_history_prevents_parent_deletion(self):
        restroom, stall, sensor, _ = self.make_graph()
        for model, row in ((Restroom, restroom), (Stall, stall), (Sensor, sensor)):
            with self.subTest(table=model.__tablename__):
                self.assert_rejected(delete(model).where(model.id == row.id), sqlstate="23503")
        # ORM deletion must not erase or null out already loaded event history.
        self.assertEqual(len(sensor.events), 1)
        with self.assertRaises(IntegrityError):
            with self.db.begin_nested():
                self.db.delete(sensor)
                self.db.flush()

    def test_stall_timestamp_changes_only_when_updated(self):
        restroom = Restroom(name="test", building="test", floor=1, x=0, y=0)
        past = datetime(2020, 1, 1, tzinfo=timezone.utc)
        stall = Stall(restroom=restroom, stall_number=1, updated_at=past)
        self.db.add(stall)
        self.db.flush()
        stall.occupied = False
        self.db.flush()
        self.assertEqual(stall.updated_at, past)
        stall.occupied = True
        self.db.flush()
        self.assertGreater(stall.updated_at, past)
        # Event creation is an explicit future service/API transaction, not a model hook.
        self.assertEqual(self.db.scalars(select(SensorEvent)).all(), [])

    def snapshot(self):
        return {
            model.__tablename__: self.db.execute(
                select(*(column for column in model.__table__.columns
                         if column.name not in {"last_sequence", "last_occupied", "latitude", "longitude", "gender", "location_source", "bidet_stalls", "accessible_stalls", "data_key", "is_active", "is_accessible"})).order_by(model.id)
            ).all()
            for model in (Restroom, Stall, Sensor, SensorEvent)
        }

    def test_seed_creates_fixtures_and_preserves_state_on_rerun(self):
        self.assertEqual(seed_development_data(self.db), {"restrooms": 3, "stalls": 12, "sensors": 12})
        expected = {"본관 1층 화장실": (3, "a"), "본관 2층 화장실": (5, "b"), "체육관 화장실": (4, "c")}
        rooms = self.db.scalars(select(Restroom)).all()
        self.assertEqual({room.name for room in rooms}, set(expected))
        for room in rooms:
            count, letter = expected[room.name]
            self.assertEqual(len(room.stalls), count)
            self.assertEqual({stall.occupied for stall in room.stalls}, {True, False})
            self.assertEqual({stall.has_bidet for stall in room.stalls}, {True, False})
            for stall in room.stalls:
                self.assertEqual(len(stall.sensors), 1)
                sensor = stall.sensors[0]
                self.assertEqual(sensor.device_id, f"stall-{letter}-{stall.stall_number:02d}")
                self.assertEqual(sensor.restroom_id, room.id)
                self.assertEqual(sensor.sensor_type, "SW-520D")
                self.assertTrue(sensor.active)
        self.assertEqual(self.db.scalars(select(SensorEvent)).all(), [])

        sensor = self.db.scalar(select(Sensor).where(Sensor.device_id == "stall-a-01"))
        sensor.stall.occupied = True
        sensor.stall.has_bidet = False
        sensor.active = False
        sensor.restroom.x = 123.0
        self.db.add(SensorEvent(sensor=sensor, event_type="occupancy_changed", value=True))
        self.db.flush()
        before = self.snapshot()
        self.assertEqual(seed_development_data(self.db), {"restrooms": 0, "stalls": 0, "sensors": 0})
        self.assertEqual(self.snapshot(), before)
        self.assertEqual(self.db.scalars(select(RestroomSnapshot)).all(), [])

    def test_seed_completes_partial_data_without_overwriting(self):
        room = Restroom(name="본관 1층 화장실", building="본관", floor=1, x=-10, y=-20)
        stall = Stall(restroom=room, stall_number=1, occupied=True, has_bidet=False)
        self.db.add(stall)
        self.db.flush()
        original_id, original_updated_at = stall.id, stall.updated_at
        self.assertEqual(seed_development_data(self.db), {"restrooms": 2, "stalls": 11, "sensors": 12})
        self.db.expire_all()
        self.assertEqual(len(room.stalls), 3)
        self.assertEqual(stall.id, original_id)
        self.assertEqual(stall.updated_at, original_updated_at)
        self.assertTrue(stall.occupied)
        self.assertFalse(stall.has_bidet)
        self.assertEqual((room.x, room.y), (-10, -20))

    def test_seed_device_conflict_rolls_back_all_additions(self):
        _, _, sensor, _ = self.make_graph()
        sensor.device_id = "stall-b-03"
        self.db.flush()
        before = self.snapshot()
        with self.assertRaisesRegex(SeedConflictError, "stall-b-03"):
            with self.db.begin_nested():
                seed_development_data(self.db)
        self.assertEqual(self.snapshot(), before)

    def test_seed_ambiguous_restroom_rolls_back_all_additions(self):
        self.db.add_all([
            Restroom(name="체육관 화장실", building="체육관", floor=1, x=x, y=0)
            for x in (1, 2)
        ])
        self.db.flush()
        before = self.snapshot()
        with self.assertRaisesRegex(SeedConflictError, "체육관 화장실"):
            with self.db.begin_nested():
                seed_development_data(self.db)
        self.assertEqual(self.snapshot(), before)


if __name__ == "__main__":
    unittest.main()
