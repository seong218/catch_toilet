from math import isclose, sqrt
import unittest

from app.services.location import distance_to


class LocationTests(unittest.TestCase):
    def test_straight_line_distance_in_meters(self):
        self.assertEqual(distance_to((10, 20), 40, 60), 50.0)
        self.assertEqual(distance_to((-20, -20), 10, 20), 50.0)
        self.assertEqual(distance_to((3, -4), 3, -4), 0.0)
        self.assertEqual(distance_to((0, 0), 1, 1), sqrt(2))

    def test_large_finite_distances_avoid_squaring_overflow(self):
        self.assertTrue(isclose(distance_to((0, 0), 3e200, 4e200), 5e200, rel_tol=1e-15))

    def test_missing_origin_keeps_existing_list_detail_null_behavior(self):
        self.assertIsNone(distance_to(None, 10, 20))


if __name__ == "__main__":
    unittest.main()
