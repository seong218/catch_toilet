from __future__ import annotations

from datetime import datetime
from typing import TYPE_CHECKING

from sqlalchemy import CheckConstraint, DateTime, ForeignKey, Index, Text, func
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.db import Base

if TYPE_CHECKING:
    from app.models.sensor import Sensor


class SensorEvent(Base):
    __tablename__ = "sensor_events"
    __table_args__ = (
        CheckConstraint("id > 0", name="ck_sensor_events_id_positive"),
        CheckConstraint("event_type ~ '[^[:space:]]'", name="ck_sensor_events_type_not_blank"),
        Index("ix_sensor_events_sensor_id_created_at", "sensor_id", "created_at"),
    )

    id: Mapped[int] = mapped_column(primary_key=True)
    sensor_id: Mapped[int] = mapped_column(
        ForeignKey("sensors.id", name="fk_sensor_events_sensor", ondelete="RESTRICT")
    )
    event_type: Mapped[str] = mapped_column(Text)
    # In the MVP, the event value is the occupied state after the change.
    value: Mapped[bool]
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now()
    )

    sensor: Mapped[Sensor] = relationship(back_populates="events")
