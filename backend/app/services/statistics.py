from collections.abc import Iterable
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
from zoneinfo import ZoneInfo

from sqlalchemy.orm import Session

from app.config import STATISTICS_TIMEZONE, get_settings
from app.repositories.statistics import count_availability_samples


@dataclass(frozen=True)
class RestroomStatistics:
    historical_availability_rate: float | None
    historical_bidet_availability_rate: float | None
    sample_count: int

    @property
    def is_usable(self) -> bool:
        # A measured zero is usable; missing/insufficient observations are not.
        return (
            self.historical_availability_rate is not None
            and self.historical_bidet_availability_rate is not None
        )


def get_restroom_statistics(
    db: Session, restroom_id: int, *, now: datetime | None = None,
) -> RestroomStatistics:
    """Single-room interface; shares the same computation as the batch lookup."""
    return get_restrooms_statistics(db, (restroom_id,), now=now)[restroom_id]


def get_restrooms_statistics(
    db: Session, restroom_ids: Iterable[int], *, now: datetime | None = None,
) -> dict[int, RestroomStatistics]:
    """Same Seoul weekday/hour and one clock/SQL snapshot for all requested rooms.

    now is an internal test/replay clock override, not an API input. Callers must
    supply valid, regularly sampled observations; this service does not assess
    sensor liveness. DB failures propagate instead of masquerading as no data.
    """
    ids = tuple(restroom_ids)
    if any(type(room_id) is not int or room_id <= 0 for room_id in ids):
        raise ValueError("restroom_ids must contain positive integers")
    ids = tuple(dict.fromkeys(ids))
    if not ids:
        return {}
    reference = datetime.now(timezone.utc) if now is None else now
    if not isinstance(reference, datetime) or reference.utcoffset() is None:
        raise ValueError("now must be a timezone-aware datetime")
    # Normalize before subtracting days so the caller's timezone/DST cannot
    # change the rolling window for two representations of the same instant.
    reference = reference.astimezone(timezone.utc)
    local_now = reference.astimezone(ZoneInfo(STATISTICS_TIMEZONE))
    settings = get_settings()
    counts = count_availability_samples(
        db,
        ids,
        start_at=reference - timedelta(days=settings.stat_lookback_days),
        end_at=reference,
        iso_weekday=local_now.isoweekday(),
        hour=local_now.hour,
    )
    result = {}
    for room_id in ids:
        sample_count, available_count, bidet_count = counts.get(room_id, (0, 0, 0))
        if sample_count < settings.min_stat_sample_count:
            result[room_id] = RestroomStatistics(None, None, sample_count)
        else:
            result[room_id] = RestroomStatistics(
                historical_availability_rate=available_count / sample_count,
                historical_bidet_availability_rate=bidet_count / sample_count,
                sample_count=sample_count,
            )
    return result
