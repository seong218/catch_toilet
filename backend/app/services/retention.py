"""Delete expired raw sensor events in bounded batches; keep derived snapshots."""

import asyncio
from datetime import datetime, timedelta, timezone
import logging

from sqlalchemy import delete, select
from sqlalchemy.exc import SQLAlchemyError
from sqlalchemy.orm import Session
from starlette.concurrency import run_in_threadpool

from app.config import get_settings
from app.db import SessionLocal
from app.models import SensorEvent

logger = logging.getLogger(__name__)


def purge_sensor_events(db: Session, *, before: datetime, batch_size: int = 1000) -> int:
    ids = select(SensorEvent.id).where(SensorEvent.created_at < before).order_by(
        SensorEvent.created_at, SensorEvent.id,
    ).limit(batch_size)
    result = db.execute(delete(SensorEvent).where(SensorEvent.id.in_(ids)),
                        execution_options={"synchronize_session": False})
    return result.rowcount


def _purge_batch() -> None:
    before = datetime.now(timezone.utc) - timedelta(days=get_settings().sensor_event_retention_days)
    try:
        with SessionLocal.begin() as db:
            purge_sensor_events(db, before=before)
    except SQLAlchemyError:
        logger.warning("Sensor event retention could not access PostgreSQL")


async def retain_recent_sensor_events() -> None:
    while True:
        # No startup deletion. At most 1,000 rows per minute and the DB's
        # statement timeout also applies. Shutdown cancels the scheduler.
        await asyncio.sleep(60)
        await run_in_threadpool(_purge_batch)
