from datetime import datetime

from sqlalchemy import extract, func, select
from sqlalchemy.orm import Session

from app.config import STATISTICS_TIMEZONE
from app.models import Restroom, RestroomSnapshot


def _sample_counts():
    return (
        func.count(RestroomSnapshot.id).label("sample_count"),
        func.count(RestroomSnapshot.id).filter(
            RestroomSnapshot.available_stalls > 0,
        ).label("available_count"),
        func.count(RestroomSnapshot.id).filter(
            RestroomSnapshot.bidet_sample_valid.is_(True),
            RestroomSnapshot.available_bidet_stalls > 0,
        ).label("bidet_count"),
        func.count(RestroomSnapshot.id).filter(
            RestroomSnapshot.bidet_sample_valid.is_(True),
        ).label("bidet_sample_count"),
    )


def count_availability_samples(
    db: Session,
    restroom_ids: tuple[int, ...],
    *,
    start_at: datetime,
    end_at: datetime,
    iso_weekday: int,
    hour: int,
) -> dict[int, tuple[int, int, int, int]]:
    """Return sample, available, and bidet counts per room in one DB snapshot.

    Observations must come from the same regular collection cadence. Production
    statistics never mix in test data, infer missing periods, or read events.
    """
    local_time = func.timezone(STATISTICS_TIMEZONE, RestroomSnapshot.captured_at)
    counts = db.execute(select(
        RestroomSnapshot.restroom_id,
        *_sample_counts(),
    ).where(
        RestroomSnapshot.restroom_id.in_(restroom_ids),
        RestroomSnapshot.is_test_data.is_(False),
        RestroomSnapshot.captured_at >= start_at,
        RestroomSnapshot.captured_at < end_at,
        extract("isodow", local_time) == iso_weekday,
        extract("hour", local_time) == hour,
    ).group_by(RestroomSnapshot.restroom_id)).all()
    return {row[0]: (row[1], row[2], row[3], row[4]) for row in counts}


def list_usage_buckets(db: Session, *, start_at: datetime, end_at: datetime,
                      restroom_id: int | None = None) -> list[dict]:
    local_time = func.timezone(STATISTICS_TIMEZONE, RestroomSnapshot.captured_at)
    weekday, hour = extract("isodow", local_time), extract("hour", local_time)
    query = select(
        Restroom.id.label("restroom_id"), Restroom.name, Restroom.building,
        Restroom.floor, Restroom.gender, weekday.label("iso_weekday"), hour.label("hour"),
        *_sample_counts(),
        func.avg(RestroomSnapshot.available_stalls).label("average_available_stalls"),
        func.avg(RestroomSnapshot.total_stalls - RestroomSnapshot.available_stalls)
            .label("average_occupied_stalls"),
    ).join(RestroomSnapshot, RestroomSnapshot.restroom_id == Restroom.id).where(
        RestroomSnapshot.is_test_data.is_(False),
        RestroomSnapshot.captured_at >= start_at,
        RestroomSnapshot.captured_at < end_at,
    ).group_by(Restroom.id, weekday, hour).order_by(Restroom.id, weekday, hour)
    if restroom_id is not None:
        query = query.where(Restroom.id == restroom_id)
    return [dict(row) for row in db.execute(query).mappings()]
