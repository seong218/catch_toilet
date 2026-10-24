from functools import lru_cache
from pathlib import Path

from pydantic import Field, SecretStr
from pydantic_settings import BaseSettings, SettingsConfigDict
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
    recommendation_distance_tolerance: float = Field(default=10.0, ge=0, allow_inf_nan=False)
    cors_allowed_origins: list[str] = Field(default_factory=lambda: [
        "http://localhost:3000",
        "http://127.0.0.1:3000",
        "http://localhost:8080",
        "http://127.0.0.1:8080",
    ])

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
