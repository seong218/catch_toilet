from typing import Any

from sqlalchemy import Select, cast, func, select
from sqlalchemy.dialects.postgresql import JSONB, aggregate_order_by
from sqlalchemy.orm import Session

from app.models import Restroom, Stall

POSTGRES_INTEGER_MAX = 2**31 - 1


def _summary_query() -> Select:
    # Outer join keeps restrooms with no stalls; COUNT(id) excludes the null row.
    return (
        select(
            Restroom.id, Restroom.name, Restroom.building, Restroom.floor,
            Restroom.x, Restroom.y,
            func.count(Stall.id).label("total_stalls"),
            func.count(Stall.id).filter(Stall.occupied.is_(False)).label("available_stalls"),
            func.count(Stall.id).filter(
                Stall.occupied.is_(False), Stall.has_bidet.is_(True)
            ).label("available_bidet_stalls"),
        )
        .outerjoin(Stall, Stall.restroom_id == Restroom.id)
        .group_by(Restroom.id)
    )


def list_restrooms(db: Session) -> list[dict[str, Any]]:
    rows = db.execute(_summary_query().order_by(Restroom.id)).mappings().all()
    return [dict(row) for row in rows]


def get_restroom_summary(db: Session, restroom_id: int) -> dict[str, Any]:
    row = db.execute(
        _summary_query().where(Restroom.id == restroom_id)
    ).mappings().one()
    return dict(row)


def get_restroom(db: Session, restroom_id: int) -> dict[str, Any] | None:
    # IDs are PostgreSQL INTEGER. Larger positive integers are valid request
    # syntax but cannot identify an existing row; avoid a driver overflow.
    if restroom_id > POSTGRES_INTEGER_MAX:
        return None
    # Aggregate counts and ordered stall details in ONE SQL statement so they
    # describe the same PostgreSQL snapshot even while other sessions write.
    stalls = func.coalesce(
        func.jsonb_agg(aggregate_order_by(
            func.jsonb_build_object(
                "id", Stall.id,
                "stall_number", Stall.stall_number,
                "occupied", Stall.occupied,
                "has_bidet", Stall.has_bidet,
            ),
            Stall.stall_number,
        )).filter(Stall.id.is_not(None)),
        cast([], JSONB),
    ).label("stalls")
    row = db.execute(
        _summary_query().add_columns(stalls).where(Restroom.id == restroom_id)
    ).mappings().one_or_none()
    return dict(row) if row is not None else None
