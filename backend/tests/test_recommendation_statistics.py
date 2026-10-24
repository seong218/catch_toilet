"""Recommendation + statistics integration using synthetic, isolated history."""

from datetime import datetime, timedelta, timezone
import os
import unittest
from unittest.mock import patch

from pydantic import ValidationError
from sqlalchemy import event
from sqlalchemy.exc import OperationalError

from app.config import Settings, get_settings
from app.models import Restroom, RestroomSnapshot, Stall
from app.services.statistics import RestroomStatistics, get_restrooms_statistics
import test_restrooms_api as restroom_tests


class RecommendationStatisticsTests(restroom_tests.RestroomAPIFixture):
    def setUp(self):
        super().setUp()
        self.now = datetime(2026, 10, 26, 3, 30, tzinfo=timezone.utc)
        self.settings = get_settings().model_copy(update={
            "min_stat_sample_count": 4, "stat_lookback_days": 56,
            "recommendation_distance_tolerance": 10.0,
        })
        self.enterContext(patch("app.services.statistics.get_settings", return_value=self.settings))
        self.enterContext(patch("app.services.recommendation.get_settings", return_value=self.settings))
        # Fix only the clock; all aggregation and selection use real services/SQL.
        self.lookup = self.enterContext(patch(
            "app.services.recommendation.get_restrooms_statistics",
            side_effect=lambda db, ids: get_restrooms_statistics(db, ids, now=self.now),
        ))

    def room(self, distance, *, occupied=False, bidet=True):
        room = Restroom(name="통계 추천 테스트", building="테스트", floor=1, x=distance, y=0)
        self.db.add(Stall(restroom=room, stall_number=1, occupied=occupied, has_bidet=bidet))
        self.db.flush()
        return room

    def history(self, room, available, bidet=None, *, test_data=False):
        bidet = available if bidet is None else bidet
        start = (self.now - timedelta(weeks=1)).replace(minute=0)
        for index, (free, free_bidet) in enumerate(zip(available, bidet, strict=True)):
            self.db.add(RestroomSnapshot(
                restroom_id=room.id, total_stalls=1, available_stalls=free,
                available_bidet_stalls=free_bidet,
                captured_at=start + timedelta(minutes=index * 10), is_test_data=test_data,
            ))
        self.db.flush()

    def recommend(self, *, bidet=False, status=200):
        return self.get_json("/api/restrooms/recommend", status, params={
            "x": 0, "y": 0, "bidet_required": str(bidet).lower(),
        })

    def test_sufficient_nearby_history_selects_higher_rate_and_returns_selected_values(self):
        near, farther = self.room(50), self.room(60)
        self.history(near, [1, 0, 0, 0])
        self.history(farther, [1, 1, 1, 0], [1, 0, 0, 0])
        result = self.recommend()
        self.assertEqual((result["id"], result["distance"]), (farther.id, 60.0))
        self.assertIs(result["statistics_used"], True)
        self.assertEqual((result["historical_availability_rate"], result["historical_bidet_availability_rate"]), (0.75, 0.25))

    def test_occupied_room_cannot_win_with_perfect_history(self):
        full, near, farther = self.room(20, occupied=True), self.room(50), self.room(60)
        self.history(full, [1, 1, 1, 1])
        self.history(near, [1, 0, 0, 0])
        self.history(farther, [1, 1, 1, 0])
        for bidet in (False, True):
            result = self.recommend(bidet=bidet)
            self.assertEqual(result["id"], farther.id)
            self.assertEqual(result["available_stalls"], 1)
            self.assertTrue(result["statistics_used"])

    def test_bidet_request_uses_bidet_rate_instead_of_general_rate(self):
        near, farther = self.room(50), self.room(60)
        self.history(near, [1, 1, 1, 1], [1, 0, 0, 0])
        self.history(farther, [1, 1, 1, 0], [1, 1, 1, 0])
        ordinary, bidet = self.recommend(), self.recommend(bidet=True)
        self.assertEqual(ordinary["id"], near.id)
        self.assertEqual(bidet["id"], farther.id)
        # Comparison used history even when it kept the closest room.
        self.assertTrue(ordinary["statistics_used"])
        self.assertTrue(bidet["statistics_used"])
        self.assertEqual(bidet["historical_bidet_availability_rate"], 0.75)

    def test_bidet_candidate_filter_precedes_distance_and_statistics(self):
        ordinary = self.room(20, bidet=False)
        near, farther = self.room(50), self.room(60)
        self.history(ordinary, [1, 1, 1, 1])
        self.history(near, [1, 0, 0, 0])
        self.history(farther, [1, 1, 1, 0])
        self.assertEqual(self.recommend()["id"], ordinary.id)
        result = self.recommend(bidet=True)
        self.assertEqual(result["id"], farther.id)
        self.assertEqual(result["available_bidet_stalls"], 1)

    def test_all_full_uses_nearest_without_statistical_comparison(self):
        near, farther = self.room(50, occupied=True, bidet=False), self.room(55, occupied=True)
        self.history(near, [0, 0, 0, 0])
        self.history(farther, [1, 1, 1, 1])
        for bidet in (False, True):
            result = self.recommend(bidet=bidet)
            self.assertEqual(result["id"], near.id)
            self.assertEqual(result["available_stalls"], 0)
            self.assertIs(result["statistics_used"], False)
            self.assertEqual(result["historical_availability_rate"], 0.0)

    def test_insufficient_history_falls_back_without_inventing_rates(self):
        near, farther = self.room(50), self.room(55)
        self.history(near, [0, 0, 0])
        self.history(farther, [1, 1, 1])
        result = self.recommend()
        self.assertEqual(result["id"], near.id)
        self.assertFalse(result["statistics_used"])
        self.assertIsNone(result["historical_availability_rate"])
        self.assertIsNone(result["historical_bidet_availability_rate"])

    def test_missing_nearest_history_is_not_treated_as_zero(self):
        near, farther = self.room(50), self.room(55)
        self.history(farther, [1, 1, 1, 1])
        result = self.recommend()
        self.assertEqual(result["id"], near.id)
        self.assertFalse(result["statistics_used"])
        self.assertIsNone(result["historical_availability_rate"])

    def test_any_incomplete_near_candidate_keeps_distance_fallback(self):
        near, incomplete, farther = self.room(50), self.room(55), self.room(60)
        self.history(near, [0, 0, 0, 0])
        self.history(incomplete, [1, 1, 1])
        self.history(farther, [1, 1, 1, 1])
        result = self.recommend()
        self.assertEqual(result["id"], near.id)
        self.assertFalse(result["statistics_used"])
        self.assertEqual(result["historical_availability_rate"], 0.0)

    def test_tolerance_is_inclusive_configurable_and_anchored_to_nearest(self):
        near, middle, far = self.room(50), self.room(60), self.room(70)
        self.history(near, [1, 0, 0, 0])
        self.history(middle, [1, 1, 0, 0])
        self.history(far, [1, 1, 1, 1])
        self.assertEqual(self.recommend()["id"], middle.id)
        self.settings.recommendation_distance_tolerance = 9.999
        result = self.recommend()
        self.assertEqual(result["id"], near.id)
        self.assertFalse(result["statistics_used"])
        self.settings.recommendation_distance_tolerance = 20
        self.assertEqual(self.recommend()["id"], far.id)

    def test_zero_tolerance_allows_only_exact_distance_ties(self):
        near, farther = self.room(50), self.room(50.0001)
        self.history(near, [0, 0, 0, 0])
        self.history(farther, [1, 1, 1, 1])
        self.settings.recommendation_distance_tolerance = 0
        self.assertEqual(self.recommend()["id"], near.id)
        farther.x = -50
        self.db.flush()
        result = self.recommend()
        self.assertEqual(result["id"], farther.id)
        self.assertTrue(result["statistics_used"])

    def test_equal_rates_including_zero_break_ties_by_distance_then_id(self):
        farther, first, second = self.room(60), self.room(50), self.room(-50)
        for room in (farther, first, second):
            self.history(room, [0, 0, 0, 0])
        result = self.recommend()
        self.assertEqual(result["id"], first.id)
        self.assertEqual(result["historical_availability_rate"], 0.0)
        self.assertTrue(result["statistics_used"])

    def test_single_candidate_reports_history_without_marking_it_used(self):
        room = self.room(50)
        self.history(room, [1, 1, 1, 0], [1, 0, 0, 0])
        result = self.recommend()
        self.assertEqual(result["id"], room.id)
        self.assertFalse(result["statistics_used"])
        self.assertEqual((result["historical_availability_rate"], result["historical_bidet_availability_rate"]), (0.75, 0.25))

    def test_test_only_history_cannot_influence_recommendation(self):
        near, farther = self.room(50), self.room(55)
        self.history(near, [1, 0, 0, 0])
        self.history(farther, [1, 1, 1, 1], test_data=True)
        result = self.recommend()
        self.assertEqual(result["id"], near.id)
        self.assertFalse(result["statistics_used"])

    def test_only_requested_rate_is_required_for_comparison(self):
        near, farther = self.room(50), self.room(55)
        self.lookup.side_effect = None
        self.lookup.return_value = {
            near.id: RestroomStatistics(0.25, None, 4),
            farther.id: RestroomStatistics(0.75, None, 4),
        }
        ordinary = self.recommend()
        self.assertEqual(ordinary["id"], farther.id)
        self.assertTrue(ordinary["statistics_used"])
        result = self.recommend(bidet=True)
        self.assertEqual(result["id"], near.id)
        self.assertFalse(result["statistics_used"])
        self.assertIsNone(result["historical_bidet_availability_rate"])
        self.lookup.return_value = {
            near.id: RestroomStatistics(None, 0.25, 4),
            farther.id: RestroomStatistics(None, 0.75, 4),
        }
        bidet = self.recommend(bidet=True)
        self.assertEqual(bidet["id"], farther.id)
        self.assertTrue(bidet["statistics_used"])
        self.assertIsNone(bidet["historical_availability_rate"])

    def test_stats_query_failure_returns_existing_503_contract(self):
        self.room(50)

        def fail_history(connection, cursor, statement, parameters, context, executemany):
            if "restroom_snapshots" in statement:
                raise OperationalError("SELECT", {}, Exception("private history failure"))

        event.listen(self.connection, "before_cursor_execute", fail_history)
        try:
            self.assertEqual(self.recommend(status=503), {"detail": "Database unavailable"})
        finally:
            event.remove(self.connection, "before_cursor_execute", fail_history)


class DistanceToleranceSettingsTests(unittest.TestCase):
    def test_environment_override_and_nonnegative_finite_validation(self):
        self.assertEqual(Settings.model_fields["recommendation_distance_tolerance"].default, 10.0)
        with patch.dict(os.environ, {"RECOMMENDATION_DISTANCE_TOLERANCE": "12.5"}):
            self.assertEqual(Settings().recommendation_distance_tolerance, 12.5)
        values = get_settings().model_dump()
        self.assertEqual(Settings(_env_file=None, **(values | {"recommendation_distance_tolerance": 0})).recommendation_distance_tolerance, 0)
        for invalid in (-1, float("nan"), float("inf"), float("-inf"), "invalid"):
            with self.assertRaises(ValidationError):
                Settings(_env_file=None, **(values | {"recommendation_distance_tolerance": invalid}))


if __name__ == "__main__":
    unittest.main()
