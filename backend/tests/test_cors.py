"""Browser preflight and response behavior without writing any application data."""

import os
import unittest
from unittest.mock import Mock, patch

from fastapi.testclient import TestClient
from pydantic import ValidationError
from pydantic_settings import SettingsError
from sqlalchemy.exc import OperationalError
from sqlalchemy.orm import Session

from app.config import Settings, get_settings
from app.db import get_db
from app.main import app


class CORSTests(unittest.TestCase):
    def setUp(self):
        self.client = TestClient(app)
        self.addCleanup(self.client.close)

    def test_local_frontend_json_preflight(self):
        for origin in ("http://localhost:8080", "http://127.0.0.1:3000"):
            with self.subTest(origin=origin):
                response = self.client.options("/api/sensors/stall", headers={
                    "Origin": origin,
                    "Access-Control-Request-Method": "POST",
                    "Access-Control-Request-Headers": "content-type",
                })
                self.assertEqual(response.status_code, 200)
                self.assertEqual(response.headers["access-control-allow-origin"], origin)
                self.assertIn("POST", response.headers["access-control-allow-methods"])
                self.assertIn("Origin", response.headers["vary"])
                self.assertNotIn("access-control-allow-credentials", response.headers)

    def test_unlisted_origin_or_method_is_not_allowed(self):
        for origin, method in (
            ("https://unlisted.example", "POST"),
            ("http://localhost:8080.unlisted.example", "POST"),
            ("http://localhost:8080", "DELETE"),
        ):
            with self.subTest(origin=origin, method=method):
                response = self.client.options("/api/sensors/stall", headers={
                    "Origin": origin,
                    "Access-Control-Request-Method": method,
                })
                self.assertEqual(response.status_code, 400)
                if method == "POST":
                    self.assertNotIn("access-control-allow-origin", response.headers)

    def test_docs_and_validation_error_include_cors_headers(self):
        origin = "http://localhost:8080"
        for path, status in (("/docs", 200), ("/api/restrooms/recommend", 422)):
            with self.subTest(path=path):
                response = self.client.get(path, headers={"Origin": origin})
                self.assertEqual(response.status_code, status)
                self.assertEqual(response.headers["access-control-allow-origin"], origin)
        response = self.client.get("/docs")
        self.assertEqual(response.status_code, 200)
        self.assertIn("SwaggerUIBundle", response.text)
        self.assertNotIn("access-control-allow-origin", response.headers)

    def test_database_error_remains_readable_by_frontend(self):
        failed_db = Mock(spec=Session)
        failed_db.execute.side_effect = OperationalError("SELECT 1", {}, Exception("offline"))
        with patch.dict(app.dependency_overrides, {get_db: lambda: failed_db}):
            response = self.client.get("/api/health", headers={"Origin": "http://localhost:8080"})
        self.assertEqual(response.status_code, 503)
        self.assertEqual(response.json(), {"detail": "Database unavailable"})
        self.assertEqual(response.headers["access-control-allow-origin"], "http://localhost:8080")

    def test_json_environment_can_replace_or_disable_origins(self):
        credentials = {key: getattr(get_settings(), key) for key in (
            "postgres_db", "postgres_user", "postgres_password",
        )}
        for value, expected in (
            ('["http://localhost:5173"]', ["http://localhost:5173"]),
            ("[]", []),
        ):
            with self.subTest(value=value), patch.dict(os.environ, {"CORS_ALLOWED_ORIGINS": value}):
                self.assertEqual(Settings(_env_file=None, **credentials).cors_allowed_origins, expected)
        for value in ("not-json", '"http://localhost:5173"'):
            with self.subTest(value=value), patch.dict(os.environ, {"CORS_ALLOWED_ORIGINS": value}):
                with self.assertRaises((SettingsError, ValidationError)):
                    Settings(_env_file=None, **credentials)


if __name__ == "__main__":
    unittest.main()
