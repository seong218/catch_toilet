"""Bounded, JSON-safe error responses that never echo rejected input."""

from fastapi import Request
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse

from app.limits import SensorRateLimitError
from app.services.location import InvalidDistanceError


def safe_text(value) -> str:
    return str(value).encode("utf-8", errors="replace").decode("utf-8")[:512]


async def validation_error(request: Request, error: RequestValidationError) -> JSONResponse:
    return JSONResponse(status_code=422, content={"detail": [
        {"loc": [part if isinstance(part, int) else safe_text(part) for part in item["loc"]],
         "msg": safe_text(item["msg"]), "type": safe_text(item["type"])}
        for item in error.errors()[:50]
    ]})


async def distance_error(request: Request, error: InvalidDistanceError) -> JSONResponse:
    return JSONResponse(status_code=422, content={"detail": [{
        "loc": ["query", "x", "y"], "msg": "Distance exceeds the supported range", "type": "value_error",
    }]})


async def sensor_rate_error(request: Request, error: SensorRateLimitError) -> JSONResponse:
    return JSONResponse(status_code=429, content={"detail": "Sensor rate limit exceeded"},
                        headers={"Retry-After": str(error.retry_after)})
