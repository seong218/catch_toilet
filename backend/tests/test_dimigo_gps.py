"""Campus inventory and geographic behavior in disposable schemas."""
from math import isfinite

from sqlalchemy import select

from app.dimigo_data import DIMIGO_LATITUDE, DIMIGO_LONGITUDE
from app.models import Restroom, Sensor, SensorEvent, Stall
from app.seed import seed_dimigo_data
from app.services.location import GPSLocation, geographic_distance
import test_restrooms_api as room_tests
import test_sensors_api as sensor_tests


class DimigoGPSTests(room_tests.RestroomAPIFixture):
    def campus(self):
        seed_dimigo_data(self.db)
        self.db.flush()
        return list(self.db.scalars(select(Restroom).where(Restroom.data_key.is_not(None))))

    def test_inventory_has_eight_restrooms_and_39_unobserved_stalls(self):
        self.campus()
        rooms = self.get_json('/api/restrooms')
        self.assertEqual(len(rooms), 8)
        self.assertEqual(sum(room['total_stalls'] for room in rooms), 39)
        male = sorted((room['floor'], room['total_stalls'], room['bidet_stalls'], room['accessible_stalls'])
                      for room in rooms if room['gender'] == 'male')
        self.assertEqual(male, [(-1, 5, 1, 0), (1, 4, 3, 1), (2, 5, 2, 0), (3, 5, 2, 0)])
        self.assertEqual([room['bidet_stalls'] for room in rooms if room['gender'] == 'female'], [None] * 4)
        self.assertTrue(all(room['unknown_stalls'] == room['total_stalls'] and room['available_stalls'] == 0 for room in rooms))
        for room in rooms:
            detail = self.get_json(f"/api/restrooms/{room['id']}")
            self.assertTrue(all(stall['occupied'] is None for stall in detail['stalls']))
            self.assertEqual([stall['stall_number'] for stall in detail['stalls'] if stall['is_accessible']],
                             [1] if room['floor'] == 1 else [])
            if room['gender'] == 'male':
                expected = {-1: [1], 1: [2, 3, 4], 2: [1, 2], 3: [1, 2]}[room['floor']]
                self.assertEqual([stall['stall_number'] for stall in detail['stalls'] if stall['has_bidet']], expected)
                self.assertTrue(all(stall['has_bidet'] is not None for stall in detail['stalls']))
            else:
                self.assertEqual([stall['has_bidet'] for stall in detail['stalls']],
                                 [False, None, None, None] if room['floor'] == 1 else [None] * room['total_stalls'])
        self.assertEqual(self.db.scalars(select(SensorEvent)).all(), [])

    def test_campus_seed_preserves_observations_and_archives_only_legacy_fixtures(self):
        old = self.seed()
        rooms = self.campus()
        stall = rooms[0].stalls[0]
        stall.occupied = True
        stall.has_bidet = True
        self.db.flush()
        self.assertEqual(seed_dimigo_data(self.db), {'restrooms': 0, 'stalls': 0, 'sensors': 0})
        self.db.flush()
        self.assertTrue(stall.occupied)
        self.assertTrue(stall.has_bidet)
        self.assertEqual(len(self.get_json('/api/restrooms')), 8)
        self.get_json(f"/api/restrooms/{next(iter(old.values()))}", 404)
        self.assertTrue(all(not sensor.active for sensor in self.db.scalars(select(Sensor).where(Sensor.device_id.like('stall-%')))))

    def test_confirmed_facilities_are_synced_without_changing_live_state_or_time(self):
        rooms = self.campus()
        male = next(room for room in rooms if room.gender == 'male' and room.floor == 1)
        female = next(room for room in rooms if room.gender == 'female' and room.floor == 1)
        male.stalls[0].is_accessible = False
        male.stalls[0].has_bidet = True
        male.stalls[0].occupied = True
        female.stalls[1].has_bidet = True  # Later field survey must be preserved.
        self.db.flush()
        before = male.stalls[0].updated_at
        self.assertEqual(seed_dimigo_data(self.db), {'restrooms': 0, 'stalls': 0, 'sensors': 0})
        self.db.flush()
        self.db.expire_all()
        self.assertTrue(male.stalls[0].is_accessible)
        self.assertFalse(male.stalls[0].has_bidet)
        self.assertTrue(male.stalls[0].occupied)
        self.assertEqual(male.stalls[0].updated_at, before)
        self.assertTrue(female.stalls[1].has_bidet)

    def test_gps_filter_and_unknown_availability_do_not_fabricate_recommendations(self):
        self.campus()
        query = {'latitude': DIMIGO_LATITUDE, 'longitude': DIMIGO_LONGITUDE, 'gender': 'female'}
        rooms = self.get_json('/api/restrooms', params=query)
        self.assertEqual(len(rooms), 4)
        self.assertTrue(all(room['gender'] == 'female' and room['distance'] == 0 for room in rooms))
        self.assertEqual(self.get_json('/api/restrooms/recommend', 404, params=query),
                         {'detail': 'Live availability unavailable'})

    def test_gps_distance_compares_buildings_without_floor_preference(self):
        rooms = self.campus()
        for room in rooms:
            if room.gender == 'male':
                room.stalls[0].occupied = False
        nearer = Restroom(name='테스트 신관', building='신관', floor=3, x=0, y=0,
                          latitude=DIMIGO_LATITUDE + 0.001, longitude=DIMIGO_LONGITUDE, gender='male')
        self.db.add(Stall(restroom=nearer, stall_number=1, occupied=False, has_bidet=True))
        self.db.flush()
        query = {'latitude': nearer.latitude, 'longitude': nearer.longitude, 'gender': 'male'}
        result = self.get_json('/api/restrooms/recommend', params=query)
        self.assertEqual(result['id'], nearer.id)
        self.assertEqual(result['distance'], 0)
        nearer.stalls[0].occupied = True
        self.db.flush()
        self.assertNotEqual(self.get_json('/api/restrooms/recommend', params=query)['id'], nearer.id)

    def test_geographic_ranges_pairing_and_legacy_mixing_are_rejected(self):
        for query in ({'latitude': 91, 'longitude': 0}, {'latitude': 0, 'longitude': 181},
                      {'latitude': 'NaN', 'longitude': 0}, {'latitude': 37}, {'longitude': 126},
                      {'latitude': 37, 'longitude': 126, 'x': 0, 'y': 0}):
            for path in ('/api/restrooms', '/api/restrooms/1', '/api/restrooms/recommend'):
                self.get_json(path, 422, params=query)
        self.assertAlmostEqual(geographic_distance(GPSLocation(0, 0), 0, 1), 111195.0802, places=3)
        self.assertTrue(isfinite(geographic_distance(GPSLocation(0, 0), 0, 180)))


class FirstObservationTests(sensor_tests.SensorAPIFixture):
    def test_first_free_observation_records_event_and_reduces_unknown_count(self):
        with self.sessions.begin() as db:
            stall = db.get(Stall, self.stall_id)
            stall.occupied = None
            stall.has_bidet = None
        with self.client.websocket_connect('/ws') as websocket:
            self.assertEqual(self.post(False), {'success': True, 'changed': True})
            event = websocket.receive_json()
            self.assertEqual((event['unknown_stalls'], event['available_stalls'], event['available_bidet_stalls']), (0, 1, 0))
        self.assertEqual([row.value for row in self.snapshot()[2]], [False])
