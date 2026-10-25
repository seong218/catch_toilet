from functools import lru_cache
import json
from pathlib import Path
import re
from typing import Annotated

from pydantic import Field, SecretStr, field_validator
from pydantic_settings import BaseSettings, NoDecode, SettingsConfigDict
from sqlalchemy import URL


# Fixed by docs/api.md; shared by Python and PostgreSQL time bucketing.
STATISTICS_TIMEZONE = "Asia/Seoul"


class Settings(BaseSettings):
    model_config = SettingsConfigDict(
        env_file=Path(__file__).resolve().parents[1] / ".env",
        env_file_encoding="utf-8",
        extra="ignore",
        hide_input_in_errors=True,
    )

    postgres_host: str = Field(default="localhost", min_length=1)
    postgres_port: int = Field(default=5432, ge=1, le=65535)
    postgres_db: str = Field(min_length=1)
    postgres_user: str = Field(min_length=1)
    postgres_password: SecretStr = Field(min_length=1)
    db_connect_timeout: int = Field(default=5, ge=1)
    db_statement_timeout_ms: int = Field(default=5000, ge=1)
    min_stat_sample_count: int = Field(default=30, ge=1)
    stat_lookback_days: int = Field(default=56, ge=1, le=3650)
    enable_statistics_collection: bool = True
    stat_sensor_max_age_seconds: int = Field(default=300, ge=60, le=3600)
    recommendation_distance_tolerance: float = Field(default=10.0, ge=0, allow_inf_nan=False)
    # Empty configuration disables sensor writes; read APIs remain available.
    sensor_api_keys: Annotated[dict[str, SecretStr], NoDecode] = Field(default_factory=dict)
    enable_simulation: bool = False
    simulation_api_key: SecretStr = SecretStr("")
    sensor_rate_per_second: float = Field(default=0.2, gt=0, allow_inf_nan=False)
    sensor_rate_burst: int = Field(default=2, ge=1, le=1000)
    sensor_global_rate_per_second: float = Field(default=5, gt=0, allow_inf_nan=False)
    sensor_global_burst: int = Field(default=10, ge=1, le=10000)
    sensor_min_state_interval_seconds: float = Field(default=1, ge=0, allow_inf_nan=False)
    sensor_event_retention_days: int = Field(default=90, ge=1, le=3650)
    ws_max_connections: int = Field(default=100, ge=1, le=10000)
    ws_max_connections_per_ip: int = Field(default=10, ge=1, le=1000)
    ws_allowed_origins: list[str] = Field(default_factory=list)
    cors_allowed_origins: list[str] = Field(default_factory=lambda: [
        "http://localhost:3000",
        "http://127.0.0.1:3000",
        "http://localhost:8080",
        "http://127.0.0.1:8080",
    ])

    @field_validator("sensor_api_keys", mode="before")
    @classmethod
    def decode_sensor_api_keys(cls, value):
        # Decode explicitly so JSON null cannot silently fall back to .env keys.
        if isinstance(value, str):
            try:
                value = json.loads(value)
            except ValueError:
                raise ValueError("SENSOR_API_KEYS must be a JSON object") from None
        if not isinstance(value, dict):
            raise ValueError("SENSOR_API_KEYS must be a JSON object")
        return value

    @field_validator("simulation_api_key")
    @classmethod
    def validate_simulation_key(cls, secret: SecretStr) -> SecretStr:
        value = secret.get_secret_value()
        if value and re.fullmatch(r"[A-Za-z0-9_-]{43,128}", value) is None:
            raise ValueError("Simulation key must be a 43-128 character URL-safe secret")
        return secret

    @field_validator("sensor_api_keys")
    @classmethod
    def validate_sensor_api_keys(cls, keys: dict[str, SecretStr]) -> dict[str, SecretStr]:
        seen = set()
        for device_id, secret in keys.items():
            value = secret.get_secret_value()
            if (re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9._:-]{0,127}", device_id) is None
                    or re.fullmatch(r"[A-Za-z0-9_-]{43,128}", value) is None):
                raise ValueError("Sensor keys require a nonblank device ID and a 43-128 character URL-safe secret")
            if value in seen:
                raise ValueError("Each sensor must have a different secret")
            seen.add(value)
        return keys

    @property
    def database_url(self) -> URL:
        # URL.create safely handles special characters in credentials.
        return URL.create(
            "postgresql+psycopg",
            username=self.postgres_user,
            password=self.postgres_password.get_secret_value(),
            host=self.postgres_host,
            port=self.postgres_port,
            database=self.postgres_db,
        )


@lru_cache
def get_settings() -> Settings:
    return Settings()
