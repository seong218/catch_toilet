from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timedelta, timezone
from threading import Barrier
from unittest.mock import patch
import unittest

from sqlalchemy import event, select
from sqlalchemy.exc import OperationalError

from app.config import get_settings
from app.main import app
from app.models import Restroom, RestroomSnapshot, Sensor, SensorEvent, Stall
from app.services.statistics import get_restrooms_statistics
import test_sensors_api as sensor_tests


class WebSocketAPITests(sensor_tests.SensorAPIFixture):
    def expected(self, occupied):
        return {
            "type": "stall.updated", "restroom_id": self.room_id,
            "stall_id": self.stall_id, "occupied": occupied,
            "total_stalls": 1, "available_stalls": int(not occupied),
            "available_bidet_stalls": int(not occupied), "unknown_stalls": 0, "simulated_stalls": 0, "is_simulated": False,
        }

    def test_recommendation_changes_after_committed_sensor_event(self):
        with self.sessions.begin() as db:
            other = Restroom(name="다음 화장실", building="테스트", floor=2, x=50, y=0)
            db.add(Stall(restroom=other, stall_number=1, occupied=False, has_bidet=True))
            db.flush()
            other_id = other.id

        def assert_views(occupied, recommended_id):
            response = self.client.get("/api/restrooms")
            self.assertEqual(response.status_code, 200, response.text)
            listed = next(room for room in response.json() if room["id"] == self.room_id)
            self.assertIsNone(listed["distance"])
            self.assertEqual(listed["total_stalls"], 1)
            self.assertEqual(listed["available_stalls"], int(not occupied))
            self.assertEqual(listed["available_bidet_stalls"], int(not occupied))
            response = self.client.get(f"/api/restrooms/{self.room_id}")
            self.assertEqual(response.status_code, 200, response.text)
            detail = response.json()
            self.assertEqual({key: value for key, value in detail.items() if key != "stalls"}, listed)
            self.assertEqual(detail["stalls"], [{
                "id": self.stall_id, "stall_number": 1,
                "occupied": occupied, "has_bidet": True, "is_accessible": False, "is_simulated": False,
            }])
            for bidet_required in ("false", "true"):
                response = self.client.get("/api/restrooms/recommend", params={
                    "x": 0, "y": 0, "bidet_required": bidet_required,
                })
                self.assertEqual(response.status_code, 200, response.text)
                result = response.json()
                self.assertEqual(result["id"], recommended_id)
                self.assertEqual(result["distance"], 50.0 if occupied else 0.0)
                self.assertIs(result["statistics_used"], False)
                self.assertIsNone(result["historical_availability_rate"])
                self.assertIsNone(result["historical_bidet_availability_rate"])

        assert_views(False, self.room_id)
        with self.client.websocket_connect("/ws") as client:
            for occupied, expected_id, values in (
                (True, other_id, [True]), (False, self.room_id, [True, False]),
            ):
                self.assertEqual(self.post(occupied), {"success": True, "changed": True})
                self.assertEqual(client.receive_json(), self.expected(occupied))
                # A separate PostgreSQL session verifies the committed state/event
                # before the three REST views are read, matching Flutter's flow.
                state, updated_at, events = self.snapshot()
                self.assertIs(state, occupied)
                self.assertEqual([row.value for row in events], values)
                self.assertTrue(all(row.sensor_id == self.sensor_id for row in events))
                self.assertTrue(all(row.event_type == "occupancy_changed" for row in events))
                self.assertEqual(events[-1].created_at, updated_at)
                assert_views(occupied, expected_id)

    def test_statistical_winner_is_excluded_when_its_last_stall_becomes_occupied(self):
        reference = datetime(2026, 10, 26, 3, 30, tzinfo=timezone.utc)
        settings = get_settings().model_copy(update={
            "min_stat_sample_count": 4, "recommendation_distance_tolerance": 10.0,
        })
        self.enterContext(patch("app.services.statistics.get_settings", return_value=settings))
        self.enterContext(patch("app.services.recommendation.get_settings", return_value=settings))
        self.enterContext(patch("app.services.recommendation.get_restrooms_statistics", side_effect=
                               lambda db, ids: get_restrooms_statistics(db, ids, now=reference)))
        with self.sessions.begin() as db:
            other = Restroom(name="통계 추천 후보", building="테스트", floor=1, x=5, y=0)
            stall = Stall(restroom=other, stall_number=1, occupied=False, has_bidet=True)
            db.add(Sensor(restroom=other, stall=stall, device_id="other-sensor", sensor_type="SW-520D"))
            db.flush()
            other_id, other_stall_id = other.id, stall.id
            for room_id, free_samples in ((self.room_id, 1), (other_id, 3)):
                for index in range(4):
                    free = int(index < free_samples)
                    db.add(RestroomSnapshot(
                        restroom_id=room_id, total_stalls=1, available_stalls=free,
                        available_bidet_stalls=free,
                        captured_at=(reference - timedelta(weeks=1)).replace(minute=index * 10),
                        is_test_data=False,
                    ))

        def recommendation():
            response = self.client.get("/api/restrooms/recommend?x=0&y=0&bidet_required=true")
            self.assertEqual(response.status_code, 200, response.text)
            return response.json()

        initial = recommendation()
        self.assertEqual(initial["id"], other_id)
        self.assertTrue(initial["statistics_used"])
        with self.client.websocket_connect("/ws") as client:
            for occupied, expected_id, used in ((True, self.room_id, False), (False, other_id, True)):
                self.post(occupied, "other-sensor")
                self.assertEqual(client.receive_json(), {
                    "type": "stall.updated", "restroom_id": other_id, "stall_id": other_stall_id,
                    "occupied": occupied, "total_stalls": 1,
                    "available_stalls": int(not occupied), "available_bidet_stalls": int(not occupied), "unknown_stalls": 0, "simulated_stalls": 0, "is_simulated": False,
                })
                updated = recommendation()
                self.assertEqual(updated["id"], expected_id)
                self.assertIs(updated["statistics_used"], used)

    def test_committed_changes_reach_two_clients_and_duplicates_do_not_broadcast(self):
        manager = app.state.connection_manager
        with self.client.websocket_connect("/ws") as first, self.client.websocket_connect("/ws") as second:
            with patch.object(manager, "broadcast", wraps=manager.broadcast) as broadcast:
                self.assertEqual(self.post(False), {"success": True, "changed": False})
                broadcast.assert_not_called()
                self.assertEqual(self.post(True), {"success": True, "changed": True})
                self.assertEqual(first.receive_json(), self.expected(True))
                self.assertEqual(second.receive_json(), self.expected(True))
                # A separate DB connection sees the committed event and state.
                state, _, events = self.snapshot()
                self.assertTrue(state)
                self.assertEqual([row.value for row in events], [True])
                broadcast.reset_mock()
                self.assertEqual(self.post(True), {"success": True, "changed": False})
                broadcast.assert_not_called()
                self.post(False)
                self.assertEqual(first.receive_json(), self.expected(False))
                self.assertEqual(second.receive_json(), self.expected(False))

    def test_disconnect_reconnect_and_incoming_messages(self):
        with self.client.websocket_connect("/ws") as survivor:
            with self.client.websocket_connect("/ws") as departing:
                self.post(True)
                self.assertEqual(survivor.receive_json(), self.expected(True))
                self.assertEqual(departing.receive_json(), self.expected(True))
            with self.client.websocket_connect("/ws") as newcomer:
                before = self.snapshot()
                newcomer.send_json({"device_id": "test-sensor", "occupied": False})
                newcomer.send_bytes(b"not a command")
                # HTTP is a scheduling boundary; app messages cannot mutate DB.
                self.client.get("/api/health")
                self.assertEqual(self.snapshot(), before)
                self.post(False)
                self.assertEqual(survivor.receive_json(), self.expected(False))
                # No initial snapshot or replay of the previous True event.
                self.assertEqual(newcomer.receive_json(), self.expected(False))

    def test_failed_commit_does_not_broadcast(self):
        def fail_commit(connection):
            raise OperationalError("COMMIT", {}, Exception("test commit failure"))

        manager = app.state.connection_manager
        before = self.snapshot()
        with self.client.websocket_connect("/ws") as client:
            with patch.object(manager, "broadcast", wraps=manager.broadcast) as broadcast:
                event.listen(self.test_engine, "commit", fail_commit)
                try:
                    self.post(True, expected_status=503)
                finally:
                    event.remove(self.test_engine, "commit", fail_commit)
                broadcast.assert_not_called()
                self.assertEqual(self.snapshot(), before)
                self.post(True)
                self.assertEqual(client.receive_json(), self.expected(True))
                broadcast.assert_called_once()

    def test_publication_failure_keeps_committed_success(self):
        with patch.object(app.state.connection_manager, "broadcast", side_effect=RuntimeError("send failed")):
            self.assertEqual(self.post(True), {"success": True, "changed": True})
        state, _, events = self.snapshot()
        self.assertTrue(state)
        self.assertEqual([row.value for row in events], [True])

    def test_concurrent_stalls_broadcast_counts_in_commit_order(self):
        with self.sessions.begin() as db:
            second_stall = Stall(restroom_id=self.room_id, stall_number=2, occupied=False, has_bidet=False)
            db.add(second_stall)
            db.flush()
            second = Sensor(
                device_id="test-sensor-2", restroom_id=self.room_id,
                stall_id=second_stall.id, sensor_type="SW-520D",
            )
            db.add(second)
        ready = Barrier(2)

        def send(device_id):
            ready.wait(timeout=5)
            return self.post(True, device_id)

        with self.client.websocket_connect("/ws") as client:
            with ThreadPoolExecutor(max_workers=2) as executor:
                futures = [executor.submit(send, device) for device in ("test-sensor", "test-sensor-2")]
                for future in futures:
                    self.assertTrue(future.result(timeout=10)["changed"])
            messages = [client.receive_json(), client.receive_json()]
        with self.sessions() as db:
            committed_stalls = list(db.scalars(
                select(Sensor.stall_id).join(SensorEvent).order_by(SensorEvent.id)
            ))
        self.assertEqual([message["stall_id"] for message in messages], committed_stalls)
        self.assertEqual([message["total_stalls"] for message in messages], [2, 2])
        self.assertEqual([message["available_stalls"] for message in messages], [1, 0])
        self.assertEqual(messages[0]["available_bidet_stalls"], int(committed_stalls[0] != self.stall_id))
        self.assertEqual(messages[1]["available_bidet_stalls"], 0)


if __name__ == "__main__":
    unittest.main()
