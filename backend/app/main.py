from collections.abc import AsyncIterator
from contextlib import asynccontextmanager

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app.api.health import router as health_router
from app.api.restrooms import router as restrooms_router
from app.api.sensors import router as sensors_router
from app.api.websocket import router as websocket_router
from app.config import get_settings
from app.db import engine
from app.realtime.manager import ConnectionManager


@asynccontextmanager
async def lifespan(app: FastAPI) -> AsyncIterator[None]:
    app.state.connection_manager = ConnectionManager()
    try:
        yield
    finally:
        await app.state.connection_manager.close()
        engine.dispose()


app = FastAPI(title="Catchy Toilet API", lifespan=lifespan)
app.add_middleware(
    CORSMiddleware,
    allow_origins=get_settings().cors_allowed_origins,
    allow_credentials=False,
    allow_methods=["GET", "POST"],
    allow_headers=["Content-Type"],
)
app.state.connection_manager = ConnectionManager()
app.include_router(health_router, prefix="/api", tags=["health"])
app.include_router(restrooms_router, prefix="/api/restrooms", tags=["restrooms"])
app.include_router(sensors_router, prefix="/api/sensors", tags=["sensors"])
app.include_router(websocket_router)
