from sqlalchemy import select
from sqlalchemy.orm import Session

from app.models import Restroom, Sensor, Stall


def get_sensor_for_update(db: Session, device_id: str) -> Sensor | None:
    return db.scalar(
        select(Sensor).where(Sensor.device_id == device_id)
        .with_for_update().execution_options(populate_existing=True)
    )


def get_stall_for_update(db: Session, stall_id: int) -> Stall | None:
    # All sensors mapped to this stall contend for the same database row lock.
    return db.scalar(
        select(Stall).where(Stall.id == stall_id)
        .with_for_update().execution_options(populate_existing=True)
    )


def restroom_exists(db: Session, restroom_id: int) -> bool:
    return db.scalar(select(Restroom.id).where(Restroom.id == restroom_id)) is not None
