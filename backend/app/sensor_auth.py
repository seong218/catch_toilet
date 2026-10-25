"""Authenticate a sensor write before acquiring a database session."""

from hashlib import sha256
from secrets import compare_digest
from typing import Annotated

from fastapi import Depends, HTTPException, Request
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer

from app.config import Settings, get_settings
from app.schemas.sensor import SensorUpdateRequest


sensor_bearer = HTTPBearer(
    scheme_name="SensorBearer",
    description="The secret assigned to the request's device_id (IoT only).",
    auto_error=False,
)


def authenticate_sensor(
    payload: SensorUpdateRequest,
    request: Request,
    credentials: Annotated[HTTPAuthorizationCredentials | None, Depends(sensor_bearer)],
    settings: Annotated[Settings, Depends(get_settings)],
) -> SensorUpdateRequest:
    if not settings.sensor_api_keys:
        raise HTTPException(status_code=503, detail="Sensor authentication unavailable")

    expected = settings.sensor_api_keys.get(payload.device_id)
    supplied = credentials.credentials if credentials is not None else ""
    # Hash to equal-length bytes before a constant-time comparison, including
    # unknown IDs and malformed/non-ASCII credentials. Never log the header.
    matches = compare_digest(
        sha256(supplied.encode("utf-8")).digest(),
        sha256(expected.get_secret_value().encode("utf-8") if expected else b"").digest(),
    )
    if expected is None or credentials is None or not matches:
        raise HTTPException(
            status_code=401,
            detail="Invalid sensor credentials",
            headers={"WWW-Authenticate": "Bearer"},
        )
    request.app.state.sensor_limiter.consume(payload.device_id, settings)
    return payload
