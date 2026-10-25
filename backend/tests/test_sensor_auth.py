"""Device-bound authentication, fail-closed configuration, and revocation."""

import json
import os
from secrets import token_urlsafe
import unittest
from unittest.mock import Mock, patch

from fastapi.testclient import TestClient
from pydantic import SecretStr, ValidationError
from pydantic_settings import SettingsError

from app.config import Settings, get_settings
from app.db import get_db
from app.main import app


class SensorAuthenticationTests(unittest.TestCase):
    def setUp(self):
        self.key = token_urlsafe(32)
        self.other_key = token_urlsafe(32)
        self.settings = get_settings().model_copy(update={"sensor_api_keys": {
            "sensor-a": SecretStr(self.key), "sensor-b": SecretStr(self.other_key),
        }})
        self.database = Mock(side_effect=AssertionError("Rejected request reached the database"))
        # A plain function keeps dependency inspection independent of Mock's signature.
        def database():
            return self.database()
        self.enterContext(patch.dict(app.dependency_overrides, {
            get_settings: lambda: self.settings, get_db: database,
        }))
        self.enterContext(patch("app.main.get_settings", return_value=
            self.settings.model_copy(update={"enable_statistics_collection": False})))
        self.client = self.enterContext(TestClient(app))

    def send(self, header=None, *, device="sensor-a", params=None):
        return self.client.post(
            "/api/sensors/stall", json={"device_id": device, "occupied": True},
            headers={} if header is None else {"Authorization": header}, params=params,
        )

    def assert_rejected(self, response):
        self.assertEqual(response.status_code, 401)
        self.assertEqual(response.json(), {"detail": "Invalid sensor credentials"})
        self.assertEqual(response.headers["www-authenticate"], "Bearer")
        self.database.assert_not_called()
        self.assertNotIn(self.key, response.text)
        self.assertNotIn(self.other_key, response.text)

    def test_missing_wrong_and_malformed_authorization_stop_before_database(self):
        for header in (None, "", "Bearer", "Bearer ", "Basic " + self.key,
                       "Bearer " + token_urlsafe(32), "Bearer " + self.key + " extra"):
            with self.subTest(kind="missing or invalid header"):
                self.assert_rejected(self.send(header))

    def test_other_device_and_unknown_or_nonexact_id_do_not_disclose_registration(self):
        for device in ("sensor-b", "unknown", "SENSOR-A"):
            with self.subTest(device=device):
                self.assert_rejected(self.send("Bearer " + self.key, device=device))

    def test_key_in_query_is_not_authentication(self):
        self.assert_rejected(self.send(params={"api_key": self.key, "token": self.key}))

    def test_empty_configuration_fails_closed_without_touching_database(self):
        self.settings.sensor_api_keys = {}
        for header in (None, "Bearer " + self.key):
            response = self.send(header)
            self.assertEqual(response.status_code, 503)
            self.assertEqual(response.json(), {"detail": "Sensor authentication unavailable"})
        self.database.assert_not_called()

    def test_rotated_and_revoked_keys_are_rejected(self):
        self.settings.sensor_api_keys["sensor-a"] = SecretStr(token_urlsafe(32))
        self.assert_rejected(self.send("Bearer " + self.key))
        del self.settings.sensor_api_keys["sensor-a"]
        self.assert_rejected(self.send("Bearer " + self.key))

    def test_public_routes_have_no_bearer_requirement_and_docs_never_contain_keys(self):
        self.settings.sensor_api_keys = {}
        response = self.client.get("/openapi.json")
        self.assertEqual(response.status_code, 200)
        self.assertNotIn(self.key, response.text)
        for path, operations in response.json()["paths"].items():
            for method, operation in operations.items():
                if method == "get":
                    self.assertNotIn("security", operation, path)
        with self.client.websocket_connect("/ws"):
            self.database.assert_not_called()


class SensorKeyConfigurationTests(unittest.TestCase):
    def setUp(self):
        settings = get_settings()
        self.credentials = {name: getattr(settings, name) for name in (
            "postgres_db", "postgres_user", "postgres_password",
        )}

    def settings(self, keys):
        return Settings(_env_file=None, sensor_api_keys=keys, **self.credentials)

    def test_json_environment_is_loaded_as_redacted_secrets(self):
        secret = token_urlsafe(32)
        with patch.dict(os.environ, {"SENSOR_API_KEYS": json.dumps({"sensor-a": secret})}):
            settings = Settings(_env_file=None, **self.credentials)
        self.assertEqual(settings.sensor_api_keys["sensor-a"].get_secret_value(), secret)
        self.assertNotIn(secret, repr(settings))
        self.assertNotIn(secret, settings.model_dump_json())

    def test_missing_configuration_defaults_to_disabled_writes(self):
        with patch.dict(os.environ):
            os.environ.pop("SENSOR_API_KEYS", None)
            self.assertEqual(Settings(_env_file=None, **self.credentials).sensor_api_keys, {})
        self.assertEqual(self.settings({}).sensor_api_keys, {})

    def test_invalid_short_blank_non_urlsafe_or_shared_keys_are_rejected_without_leaking(self):
        valid = token_urlsafe(32)
        for mapping in (
            {"sensor-a": ""}, {"sensor-a": "short"}, {"sensor-a": "a" * 42},
            {"sensor-a": "a" * 129}, {"sensor-a": valid + " "}, {"sensor-a": valid + "한"},
            {" ": valid}, {"sensor-a": valid, "sensor-b": valid}, {"sensor-a": None},
        ):
            with self.subTest(kind="invalid configuration"):
                with self.assertRaises(ValidationError) as error:
                    self.settings(mapping)
                self.assertNotIn(valid, str(error.exception))

    def test_malformed_json_or_nonobject_configuration_is_rejected(self):
        for value in ("not-json", "[]", '"secret"', "null"):
            with patch.dict(os.environ, {"SENSOR_API_KEYS": value}):
                with self.assertRaises((SettingsError, ValidationError)):
                    Settings(_env_file=None, **self.credentials)


if __name__ == "__main__":
    unittest.main()
