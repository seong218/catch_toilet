from datetime import datetime

from sqlalchemy import extract, func, select
from sqlalchemy.orm import Session

from app.config import STATISTICS_TIMEZONE
from app.models import RestroomSnapshot


def count_availability_samples(
    db: Session,
    restroom_ids: tuple[int, ...],
    *,
    start_at: datetime,
    end_at: datetime,
    iso_weekday: int,
    hour: int,
) -> dict[int, tuple[int, int, int]]:
    """Return sample, available, and bidet counts per room in one DB snapshot.

    Observations must come from the same regular collection cadence. Production
    statistics never mix in test data, infer missing periods, or read events.
    """
    local_time = func.timezone(STATISTICS_TIMEZONE, RestroomSnapshot.captured_at)
    counts = db.execute(select(
        RestroomSnapshot.restroom_id,
        func.count(RestroomSnapshot.id),
        func.count(RestroomSnapshot.id).filter(RestroomSnapshot.available_stalls > 0),
        func.count(RestroomSnapshot.id).filter(RestroomSnapshot.available_bidet_stalls > 0),
    ).where(
        RestroomSnapshot.restroom_id.in_(restroom_ids),
        RestroomSnapshot.is_test_data.is_(False),
        RestroomSnapshot.captured_at >= start_at,
        RestroomSnapshot.captured_at < end_at,
        extract("isodow", local_time) == iso_weekday,
        extract("hour", local_time) == hour,
    ).group_by(RestroomSnapshot.restroom_id)).all()
    return {row[0]: (row[1], row[2], row[3]) for row in counts}
