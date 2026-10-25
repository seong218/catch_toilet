"""Opt-in, authenticated PC-only controls; never ship this key in the app."""
from hashlib import sha256
import logging
from secrets import compare_digest
from typing import Annotated

from fastapi import APIRouter, Depends, HTTPException, Request
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from sqlalchemy.exc import SQLAlchemyError
from sqlalchemy.orm import Session
from starlette.concurrency import run_in_threadpool

from app.config import Settings, get_settings
from app.db import get_db
from app.schemas.simulation import SimulationReset, SimulationResponse, SimulationUpdate
from app.services.simulation import (
    SimulationCapacityExceeded, SimulationStallNotFound, change_simulation,
)

logger = logging.getLogger(__name__)
bearer = HTTPBearer(scheme_name="SimulationBearer", auto_error=False)


def authenticate_simulation(
    credentials: Annotated[HTTPAuthorizationCredentials | None, Depends(bearer)],
    settings: Annotated[Settings, Depends(get_settings)],
) -> None:
    if not settings.enable_simulation:
        raise HTTPException(404, "Simulation disabled")
    expected = settings.simulation_api_key.get_secret_value()
    if not expected:
        raise HTTPException(503, "Simulation authentication unavailable")
    supplied = credentials.credentials if credentials else ""
    if credentials is None or not compare_digest(
        sha256(supplied.encode()).digest(), sha256(expected.encode()).digest(),
    ):
        raise HTTPException(401, "Invalid simulation credentials", headers={"WWW-Authenticate": "Bearer"})


router = APIRouter(dependencies=[Depends(authenticate_simulation)])
Database = Annotated[Session, Depends(get_db)]


async def _change(request: Request, db: Session, states=None, reset_ids=None):
    manager = request.app.state.connection_manager
    try:
        async with manager.update_lock:
            events = await run_in_threadpool(change_simulation, db, states, reset_ids)
            for event in events:
                manager.broadcast(event)
    except SimulationStallNotFound:
        raise HTTPException(404, "Simulation stall not found") from None
    except SimulationCapacityExceeded:
        raise HTTPException(422, "At most 64 simulated stalls are allowed") from None
    except SQLAlchemyError:
        logger.warning("Simulation could not read PostgreSQL")
        raise HTTPException(503, "Database unavailable") from None
    return SimulationResponse(changed=len(events))


@router.post("/stalls", response_model=SimulationResponse)
async def set_states(payload: SimulationUpdate, request: Request, db: Database):
    return await _change(request, db, {state.stall_id: state.occupied for state in payload.states})


@router.post("/reset", response_model=SimulationResponse)
async def reset_states(payload: SimulationReset, request: Request, db: Database):
    return await _change(request, db, reset_ids=payload.stall_ids)
