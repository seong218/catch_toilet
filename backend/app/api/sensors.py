import logging
from typing import Annotated

from fastapi import APIRouter, Depends, HTTPException, Request
from sqlalchemy.exc import SQLAlchemyError
from sqlalchemy.orm import Session
from starlette.concurrency import run_in_threadpool

from app.db import get_db
from app.config import Settings, get_settings
from app.realtime.manager import ConnectionManager
from app.schemas.sensor import SensorUpdateRequest, SensorUpdateResponse
from app.sensor_auth import authenticate_sensor
from app.services.sensors import (
    InactiveSensorError,
    InvalidSensorMappingError,
    SensorNotFoundError,
    update_stall_occupancy,
)

logger = logging.getLogger(__name__)
router = APIRouter()


@router.post(
    "/stall",
    response_model=SensorUpdateResponse,
    responses={
        401: {"description": "Missing or invalid credentials for this sensor"},
        404: {"description": "Sensor not found"},
        409: {"description": "Sensor inactive or invalid mapping"},
        429: {"description": "Sensor rate limit exceeded"},
        503: {"description": "Database or sensor authentication unavailable"},
    },
)
async def update_stall(
    payload: Annotated[SensorUpdateRequest, Depends(authenticate_sensor)],
    request: Request,
    db: Annotated[Session, Depends(get_db)],
    settings: Annotated[Settings, Depends(get_settings)],
) -> SensorUpdateResponse:
    manager: ConnectionManager = request.app.state.connection_manager
    try:
        async with manager.update_lock:
            notification = await run_in_threadpool(
                update_stall_occupancy, db, payload.device_id, payload.occupied,
                minimum_interval=settings.sensor_min_state_interval_seconds,
            )
            if notification is not None:
                try:
                    manager.broadcast(notification)
                except Exception:
                    # The transaction is already committed. Reconnect + REST
                    # resync recovers delivery failures; never report a DB failure.
                    logger.exception("Committed sensor update could not be broadcast")
    except SensorNotFoundError:
        raise HTTPException(status_code=404, detail="Sensor not found") from None
    except InactiveSensorError:
        raise HTTPException(status_code=409, detail="Sensor is inactive") from None
    except InvalidSensorMappingError:
        raise HTTPException(status_code=409, detail="Sensor mapping is invalid") from None
    except SQLAlchemyError:
        logger.warning("Sensor update could not complete its PostgreSQL transaction")
        raise HTTPException(status_code=503, detail="Database unavailable") from None
    return SensorUpdateResponse(success=True, changed=notification is not None)
