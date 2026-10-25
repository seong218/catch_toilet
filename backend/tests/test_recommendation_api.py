import unittest
from unittest.mock import Mock

from sqlalchemy import event
from sqlalchemy.exc import OperationalError
from sqlalchemy.orm import Session

from app.db import get_db
from app.main import app
from app.models import Restroom, Stall
import test_restrooms_api as restroom_tests


RECOMMENDATION_FIELDS = restroom_tests.ROOM_FIELDS | {
    "statistics_used", "historical_availability_rate", "historical_bidet_availability_rate",
}
PATH = "/api/restrooms/recommend"


class RecommendationAPITests(restroom_tests.RestroomAPIFixture):
    def room(self, x, y=0, *, states=((False, False),)):
        room = Restroom(name="추천 테스트", building="테스트", floor=1, x=x, y=y)
        self.db.add(room)
        self.db.add_all([
            Stall(restroom=room, stall_number=number, occupied=occupied, has_bidet=bidet)
            for number, (occupied, bidet) in enumerate(states, start=1)
        ])
        self.db.flush()
        return room

    def recommend(self, *, x=0, y=0, bidet_required=False, expected_status=200):
        result = self.get_json(PATH, expected_status, params={
            "x": x, "y": y, "bidet_required": str(bidet_required).lower(),
        })
        if expected_status == 200:
            self.assertEqual(set(result), RECOMMENDATION_FIELDS)
            self.assertIs(result["statistics_used"], False)
            self.assertIsNone(result["historical_availability_rate"])
            self.assertIsNone(result["historical_bidet_availability_rate"])
            self.assertIsNotNone(result["distance"])
            self.assertGreaterEqual(result["distance"], 0)
        return result

    def test_nearest_full_restroom_is_excluded_for_nearest_vacancy(self):
        self.room(20, states=((True, True),))
        available = self.room(50, states=((False, False), (True, True)))
        self.room(80, states=((False, True), (False, True), (False, False)))
        result = self.recommend()
        self.assertEqual((result["id"], result["distance"]), (available.id, 50.0))
        self.assertEqual((result["total_stalls"], result["available_stalls"], result["available_bidet_stalls"]), (2, 1, 0))
        # Omitting the optional flag has exactly the same behavior as false.
        self.assertEqual(self.get_json(PATH, params={"x": 0, "y": 0}), result)

    def test_bidet_required_chooses_nearest_vacant_bidet_stall(self):
        ordinary = self.room(20, states=((False, False), (True, True)))
        bidet = self.room(60, states=((False, True),))
        self.room(100, states=((False, True), (False, True)))
        self.assertEqual(self.recommend()["id"], ordinary.id)
        result = self.recommend(bidet_required=True)
        self.assertEqual((result["id"], result["distance"]), (bidet.id, 60.0))
        self.assertEqual(result["available_bidet_stalls"], 1)

    def test_all_full_returns_nearest_for_both_bidet_settings(self):
        self.room(80, states=((True, True),))
        nearest = self.room(30, states=((True, False), (True, False)))
        for bidet_required in (False, True):
            with self.subTest(bidet_required=bidet_required):
                result = self.recommend(bidet_required=bidet_required)
                self.assertEqual((result["id"], result["distance"]), (nearest.id, 30.0))
                self.assertEqual((result["available_stalls"], result["available_bidet_stalls"]), (0, 0))

    def test_single_restroom_is_returned_when_vacant_or_full(self):
        room = self.room(3, 4, states=((False, True),))
        for occupied in (False, True):
            room.stalls[0].occupied = occupied
            self.db.flush()
            for bidet_required in (False, True):
                with self.subTest(occupied=occupied, bidet_required=bidet_required):
                    result = self.recommend(bidet_required=bidet_required)
                    self.assertEqual((result["id"], result["distance"]), (room.id, 5.0))
                    self.assertEqual(result["available_stalls"], int(not occupied))

    def test_no_vacant_bidet_does_not_relax_requirement(self):
        room = self.room(20, states=((False, False), (True, True)))
        self.assertEqual(self.recommend()["id"], room.id)
        self.assertEqual(self.recommend(bidet_required=True, expected_status=404), {
            "detail": "No available bidet stalls",
        })

    def test_no_restrooms_returns_specific_404_for_both_settings(self):
        for bidet_required in (False, True):
            self.assertEqual(self.recommend(bidet_required=bidet_required, expected_status=404), {
                "detail": "No restrooms found",
            })

    def test_room_without_stalls_only_participates_in_all_full_fallback(self):
        empty = self.room(0, states=())
        usable = self.room(50, states=((False, True),))
        for bidet_required in (False, True):
            self.assertEqual(self.recommend(bidet_required=bidet_required)["id"], usable.id)
        usable.stalls[0].occupied = True
        self.db.flush()
        for bidet_required in (False, True):
            result = self.recommend(bidet_required=bidet_required)
            self.assertEqual(result["id"], empty.id)
            self.assertEqual(result["total_stalls"], 0)

    def test_distance_ties_use_smallest_id_including_full_fallback(self):
        first = self.room(-3, -4, states=((False, True),))
        second = self.room(3, 4, states=((False, True),))
        for occupied in (False, True):
            for room in (first, second):
                room.stalls[0].occupied = occupied
            self.db.flush()
            for bidet_required in (False, True):
                result = self.recommend(bidet_required=bidet_required)
                self.assertEqual((result["id"], result["distance"]), (first.id, 5.0))

    def test_user_coordinates_and_unrounded_distance_determine_choice(self):
        # These distances round to the same display value. The nearer, higher
        # ID must win; neither presentation rounding nor floor alters distance.
        farther = self.room(1.0002, states=((False, True),))
        nearer = self.room(1.0001, states=((False, True),))
        nearer.floor = 100
        self.db.flush()
        self.assertEqual(self.recommend()["id"], nearer.id)
        self.assertEqual(self.recommend(x=farther.x)["id"], farther.id)
        negative = self.room(-20, -20, states=((False, True),))
        result = self.recommend(x=-20, y=-20)
        self.assertEqual((result["id"], result["distance"]), (negative.id, 0.0))

    def test_required_finite_coordinates_and_boolean_validation(self):
        for params, missing in (({}, {"latitude"}), ({"x": 0}, {"y"}), ({"y": 0}, {"x"})):
            body = self.get_json(PATH, 422, params=params)
            self.assertEqual({error["loc"][-1] for error in body["detail"]}, missing)
        for axis in ("x", "y"):
            for value in ("", "null", "abc", "NaN", "inf", "-inf", "1e309"):
                with self.subTest(axis=axis, value=value):
                    body = self.get_json(PATH, 422, params={"x": 0, "y": 0, axis: value})
                    self.assertEqual(body["detail"][0]["loc"], ["query", axis])
        for value in ("", "null", "maybe", "2"):
            with self.subTest(bidet_required=value):
                body = self.get_json(PATH, 422, params={"x": 0, "y": 0, "bidet_required": value})
                self.assertEqual(body["detail"][0]["loc"], ["query", "bidet_required"])

    def test_database_failure_returns_contract_503(self):
        failed_db = Mock(spec=Session)
        failed_db.execute.side_effect = OperationalError("SELECT private_query", {}, Exception("private details"))
        app.dependency_overrides[get_db] = lambda: failed_db
        self.assertEqual(self.recommend(expected_status=503), {"detail": "Database unavailable"})

    def test_reads_live_counts_and_batched_statistics_without_writes(self):
        self.seed()
        statements = []

        def record_sql(connection, cursor, statement, parameters, context, executemany):
            statements.append(statement)

        event.listen(self.connection, "before_cursor_execute", record_sql)
        try:
            self.recommend(bidet_required=True)
        finally:
            event.remove(self.connection, "before_cursor_execute", record_sql)
        self.assertEqual(len(statements), 2)
        self.assertTrue(all(statement.startswith("SELECT") for statement in statements))
        self.assertTrue(all("sensor_events" not in statement for statement in statements))
        self.assertEqual(sum("restroom_snapshots" in statement for statement in statements), 1)

    def test_openapi_recommendation_contract_and_required_inputs(self):
        specification = self.get_json("/openapi.json")
        parameters = {parameter["name"]: parameter for parameter in specification["paths"][PATH]["get"]["parameters"]}
        self.assertFalse(parameters["x"]["required"])
        self.assertIn("latitude", parameters)
        self.assertFalse(parameters["y"]["required"])
        self.assertIn("longitude", parameters)
        self.assertFalse(parameters["bidet_required"]["required"])
        self.assertIs(parameters["bidet_required"]["schema"]["default"], False)
        schema = specification["components"]["schemas"]["Recommendation"]
        self.assertEqual(set(schema["properties"]), RECOMMENDATION_FIELDS)
        self.assertEqual(set(schema["required"]), RECOMMENDATION_FIELDS)
        self.assertEqual(schema["properties"]["distance"]["type"], "number")
        for name in ("historical_availability_rate", "historical_bidet_availability_rate"):
            self.assertEqual({variant["type"] for variant in schema["properties"][name]["anyOf"]}, {"number", "null"})


if __name__ == "__main__":
    unittest.main()
