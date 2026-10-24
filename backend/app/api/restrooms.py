import logging
from typing import Annotated

from fastapi import APIRouter, Depends, HTTPException, Path, Query, status
from fastapi.exceptions import RequestValidationError
from pydantic import FiniteFloat
from sqlalchemy.exc import SQLAlchemyError
from sqlalchemy.orm import Session

from app.db import get_db
from app.repositories import restrooms
from app.schemas.recommendation import Recommendation
from app.schemas.restroom import Restroom, RestroomDetail
from app.services.location import distance_to
from app.services.recommendation import (
    NoAvailableBidetStallsError,
    NoRestroomsFoundError,
    recommend_restroom,
)

logger = logging.getLogger(__name__)
router = APIRouter()


def optional_coordinates(
    x: Annotated[FiniteFloat | None, Query()] = None,
    y: Annotated[FiniteFloat | None, Query()] = None,
) -> tuple[float, float] | None:
    if (x is None) != (y is None):
        missing = "x" if x is None else "y"
        raise RequestValidationError([
            {"type": "missing", "loc": ("query", missing), "msg": "Field required", "input": None}
        ])
    return (x, y) if x is not None and y is not None else None


Database = Annotated[Session, Depends(get_db)]
Coordinates = Annotated[tuple[float, float] | None, Depends(optional_coordinates)]


@router.get("", response_model=list[Restroom], responses={503: {"description": "Database unavailable"}})
def list_restrooms(db: Database, coordinates: Coordinates) -> list[Restroom]:
    try:
        rows = restrooms.list_restrooms(db)
    except SQLAlchemyError:
        logger.warning("Restroom list could not access PostgreSQL")
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE, detail="Database unavailable"
        ) from None
    result = [Restroom(**row, distance=distance_to(coordinates, row["x"], row["y"])) for row in rows]
    if coordinates is not None:
        result.sort(key=lambda room: (room.distance, room.id))
    return result


# The static path must precede /{restroom_id} so "recommend" is not parsed as an ID.
@router.get(
    "/recommend",
    response_model=Recommendation,
    responses={
        404: {"description": "No restrooms found or no available bidet stalls"},
        503: {"description": "Database unavailable"},
    },
)
def get_recommendation(
    db: Database,
    x: Annotated[FiniteFloat, Query()],
    y: Annotated[FiniteFloat, Query()],
    bidet_required: Annotated[bool, Query()] = False,
) -> Recommendation:
    try:
        return recommend_restroom(db, (x, y), bidet_required=bidet_required)
    except NoRestroomsFoundError:
        raise HTTPException(status_code=404, detail="No restrooms found") from None
    except NoAvailableBidetStallsError:
        raise HTTPException(status_code=404, detail="No available bidet stalls") from None
    except SQLAlchemyError:
        logger.warning("Restroom recommendation could not access PostgreSQL")
        raise HTTPException(status_code=503, detail="Database unavailable") from None


@router.get(
    "/{restroom_id}",
    response_model=RestroomDetail,
    responses={404: {"description": "Restroom not found"}, 503: {"description": "Database unavailable"}},
)
def get_restroom(
    restroom_id: Annotated[int, Path(gt=0)], db: Database, coordinates: Coordinates,
) -> RestroomDetail:
    try:
        row = restrooms.get_restroom(db, restroom_id)
    except SQLAlchemyError:
        logger.warning("Restroom detail could not access PostgreSQL")
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE, detail="Database unavailable"
        ) from None
    if row is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Restroom not found")
    return RestroomDetail(**row, distance=distance_to(coordinates, row["x"], row["y"]))
