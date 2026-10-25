"""One real, fully observed room snapshot per UTC minute; no backfilling."""

import asyncio
from datetime import datetime, timedelta, timezone
import logging

from sqlalchemy import DateTime, exists, func, literal, select
from sqlalchemy.dialects.postgresql import insert
from sqlalchemy.exc import SQLAlchemyError
from sqlalchemy.orm import Session
from starlette.concurrency import run_in_threadpool

from app.config import get_settings
from app.db import SessionLocal
from app.models import Restroom, RestroomSnapshot, Sensor, Stall, StatisticsTracking

logger = logging.getLogger(__name__)
SAMPLE_INTERVAL_SECONDS = 60


def capture_restroom_snapshots(db: Session, *, now: datetime | None = None) -> int:
    """Insert atomically; the caller owns commit/rollback.

    now is an internal test clock. Production uses PostgreSQL's statement clock
    and one INSERT/SELECT snapshot. Never read the simulation display overlay.
    """
    if now is not None and (not isinstance(now, datetime) or now.utcoffset() is None):
        raise ValueError("now must be a timezone-aware datetime")
    # Hold a shared lock through the caller's commit. Stop waits for any running
    # sample to commit; after stop returns, no collector can save another sample.
    tracking = db.scalar(select(StatisticsTracking).where(
        StatisticsTracking.id == 1,
    ).with_for_update(read=True).execution_options(populate_existing=True))
    if tracking is None or not tracking.enabled:
        return 0
    observed_at = (func.statement_timestamp() if now is None
                   else literal(now, type_=DateTime(timezone=True)))
    sample_at = func.date_trunc("minute", observed_at)
    cutoff = observed_at - timedelta(seconds=get_settings().stat_sensor_max_age_seconds)
    fresh_sensor = exists(select(Sensor.id).where(
        Sensor.stall_id == Stall.id,
        Sensor.restroom_id == Stall.restroom_id,
        Sensor.active.is_(True),
        Sensor.last_occupied == Stall.occupied,
        Sensor.last_seen_at >= cutoff,
        Sensor.last_seen_at >= tracking.started_at,
        Sensor.last_seen_at <= observed_at,
    ).correlate(Stall))
    observations = select(
        Restroom.id,
        func.count(Stall.id),
        func.count(Stall.id).filter(Stall.occupied.is_(False)),
        func.count(Stall.id).filter(Stall.occupied.is_(False), Stall.has_bidet.is_(True)),
        sample_at,
        literal(False),
        func.bool_and(Stall.has_bidet.is_not(None)),
    ).join(Stall, Stall.restroom_id == Restroom.id).where(
        Restroom.is_active.is_(True),
        # First sample is the next minute boundary, never dated before start.
        sample_at >= tracking.started_at,
    ).group_by(Restroom.id).having(
        func.count(Stall.id) > 0,
        func.bool_and(Stall.occupied.is_not(None)),
        func.bool_and(fresh_sensor),
    )
    statement = insert(RestroomSnapshot).from_select([
        "restroom_id", "total_stalls", "available_stalls", "available_bidet_stalls",
        "captured_at", "is_test_data", "bidet_sample_valid",
    ], observations).on_conflict_do_nothing(
        constraint="uq_restroom_snapshots_room_captured_at",
    ).returning(RestroomSnapshot.id)
    return len(db.scalars(statement).all())


def _collect_once() -> None:
    try:
        with SessionLocal.begin() as db:
            count = capture_restroom_snapshots(db)
        logger.info("Statistics collection saved %d restroom snapshots", count)
    except SQLAlchemyError:
        # Never log driver exceptions or SQL parameters containing credentials.
        logger.warning("Statistics collection failed; retrying next minute")


async def collect_regular_statistics() -> None:
    while True:
        await run_in_threadpool(_collect_once)
        # Align to minute boundaries after work; do not manufacture missed rows
        # or drift by adding the query duration to every sampling interval.
        delay = SAMPLE_INTERVAL_SECONDS - datetime.now(timezone.utc).timestamp() % SAMPLE_INTERVAL_SECONDS
        await asyncio.sleep(delay)
