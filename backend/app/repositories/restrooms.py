from typing import Any

from sqlalchemy import Boolean, Select, case, cast, false, func, literal, select
from sqlalchemy.dialects.postgresql import JSONB, aggregate_order_by
from sqlalchemy.orm import Session

from app.models import Restroom, Stall
from app.simulation_state import current_overrides

POSTGRES_INTEGER_MAX = 2**31 - 1


def _display_columns(overrides):
    if not overrides:
        return Stall.occupied, false()
    return (
        case(*[(Stall.id == key, literal(value, type_=Boolean)) for key, value in overrides.items()],
             else_=Stall.occupied),
        Stall.id.in_(list(overrides)),
    )


def _summary_query(occupied=None, simulated=None) -> Select:
    if occupied is None:
        occupied, simulated = _display_columns(current_overrides())
    # Outer join keeps restrooms with no stalls; COUNT(id) excludes the null row.
    return (
        select(
            Restroom.id, Restroom.name, Restroom.building, Restroom.floor,
            Restroom.x, Restroom.y,
            Restroom.latitude, Restroom.longitude, Restroom.gender, Restroom.location_source,
            Restroom.bidet_stalls, Restroom.accessible_stalls,
            func.count(Stall.id).label("total_stalls"),
            func.count(Stall.id).filter(occupied.is_(False)).label("available_stalls"),
            func.count(Stall.id).filter(
                occupied.is_(False), Stall.has_bidet.is_(True)
            ).label("available_bidet_stalls"),
            func.count(Stall.id).filter(occupied.is_(None)).label("unknown_stalls"),
            func.count(Stall.id).filter(simulated).label("simulated_stalls"),
        )
        .outerjoin(Stall, Stall.restroom_id == Restroom.id)
        .where(Restroom.is_active.is_(True))
        .group_by(Restroom.id)
    )


def list_restrooms(db: Session, *, gender: str | None = None) -> list[dict[str, Any]]:
    query = _summary_query()
    if gender is not None:
        query = query.where(Restroom.gender == gender)
    rows = db.execute(query.order_by(Restroom.id)).mappings().all()
    return [dict(row) for row in rows]


def get_restroom_summary(db: Session, restroom_id: int) -> dict[str, Any]:
    row = db.execute(
        _summary_query().where(Restroom.id == restroom_id)
    ).mappings().one()
    return dict(row)


def get_restroom(db: Session, restroom_id: int, *, overrides=None) -> dict[str, Any] | None:
    # IDs are PostgreSQL INTEGER. Larger positive integers are valid request
    # syntax but cannot identify an existing row; avoid a driver overflow.
    if restroom_id > POSTGRES_INTEGER_MAX:
        return None
    # Aggregate counts and ordered stall details in ONE SQL statement so they
    # describe the same PostgreSQL snapshot even while other sessions write.
    occupied, simulated = _display_columns(current_overrides() if overrides is None else overrides)
    stalls = func.coalesce(
        func.jsonb_agg(aggregate_order_by(
            func.jsonb_build_object(
                "id", Stall.id,
                "stall_number", Stall.stall_number,
                "occupied", occupied,
                "is_simulated", simulated,
                "has_bidet", Stall.has_bidet,
                "is_accessible", Stall.is_accessible,
            ),
            Stall.stall_number,
        )).filter(Stall.id.is_not(None)),
        cast([], JSONB),
    ).label("stalls")
    row = db.execute(
        _summary_query(occupied, simulated).add_columns(stalls).where(Restroom.id == restroom_id)
    ).mappings().one_or_none()
    return dict(row) if row is not None else None
