from collections.abc import AsyncIterator
from contextlib import asynccontextmanager
import asyncio

from fastapi import FastAPI
from fastapi.exceptions import RequestValidationError
from fastapi.middleware.cors import CORSMiddleware

from app.api.health import router as health_router
from app.api.restrooms import router as restrooms_router
from app.api.sensors import router as sensors_router
from app.api.websocket import router as websocket_router
from app.api.simulation import router as simulation_router
from app.simulation_state import replace_overrides
from app.config import get_settings
from app.db import engine
from app.realtime.manager import ConnectionManager
from app.errors import distance_error, sensor_rate_error, validation_error
from app.limits import SensorRateLimiter, SensorRateLimitError
from app.services.location import InvalidDistanceError
from app.services.retention import retain_recent_sensor_events
from app.services.statistics_collection import collect_regular_statistics


def initialize_state(app: FastAPI) -> None:
    replace_overrides({})
    settings = get_settings()
    app.state.connection_manager = ConnectionManager(
        max_connections=settings.ws_max_connections, max_per_ip=settings.ws_max_connections_per_ip,
    )
    app.state.sensor_limiter = SensorRateLimiter()


@asynccontextmanager
async def lifespan(app: FastAPI) -> AsyncIterator[None]:
    initialize_state(app)
    retention = asyncio.create_task(retain_recent_sensor_events())
    statistics = (asyncio.create_task(collect_regular_statistics())
                  if get_settings().enable_statistics_collection else None)
    try:
        yield
    finally:
        retention.cancel()
        tasks = [retention]
        if statistics is not None:
            statistics.cancel()
            tasks.append(statistics)
        await asyncio.gather(*tasks, return_exceptions=True)
        await app.state.connection_manager.close()
        engine.dispose()


app = FastAPI(title="Catch Toilet API", lifespan=lifespan)
app.add_middleware(
    CORSMiddleware,
    allow_origins=get_settings().cors_allowed_origins,
    allow_credentials=False,
    allow_methods=["GET", "POST"],
    allow_headers=["Content-Type", "Authorization"],
)
initialize_state(app)
app.add_exception_handler(RequestValidationError, validation_error)
app.add_exception_handler(InvalidDistanceError, distance_error)
app.add_exception_handler(SensorRateLimitError, sensor_rate_error)
app.include_router(health_router, prefix="/api", tags=["health"])
app.include_router(restrooms_router, prefix="/api/restrooms", tags=["restrooms"])
app.include_router(sensors_router, prefix="/api/sensors", tags=["sensors"])
app.include_router(websocket_router)
app.include_router(simulation_router, prefix="/api/simulation", tags=["simulation"])
