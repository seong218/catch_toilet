from __future__ import annotations

from typing import TYPE_CHECKING

from sqlalchemy import (
    BigInteger,
    CheckConstraint,
    ForeignKey,
    ForeignKeyConstraint,
    Text,
    UniqueConstraint,
    true,
    false,
    text,
)
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.db import Base

if TYPE_CHECKING:
    from app.models.restroom import Restroom
    from app.models.sensor_event import SensorEvent
    from app.models.stall import Stall


class Sensor(Base):
    __tablename__ = "sensors"
    __table_args__ = (
        CheckConstraint("id > 0", name="ck_sensors_id_positive"),
        CheckConstraint("last_sequence >= 0", name="ck_sensors_sequence_nonnegative"),
        CheckConstraint("device_id ~ '[^[:space:]]'", name="ck_sensors_device_id_not_blank"),
        CheckConstraint("sensor_type ~ '[^[:space:]]'", name="ck_sensors_type_not_blank"),
        UniqueConstraint("device_id", name="uq_sensors_device_id"),
        ForeignKeyConstraint(
            ["stall_id", "restroom_id"],
            ["stalls.id", "stalls.restroom_id"],
            name="fk_sensors_stall_restroom",
            ondelete="RESTRICT",
        ),
    )

    id: Mapped[int] = mapped_column(primary_key=True)
    device_id: Mapped[str] = mapped_column(Text)
    restroom_id: Mapped[int] = mapped_column(
        ForeignKey("restrooms.id", name="fk_sensors_restroom", ondelete="RESTRICT"),
        index=True,
    )
    stall_id: Mapped[int] = mapped_column(index=True)
    sensor_type: Mapped[str] = mapped_column(Text)
    active: Mapped[bool] = mapped_column(server_default=true())
    last_sequence: Mapped[int] = mapped_column(BigInteger, server_default=text("0"))
    last_occupied: Mapped[bool] = mapped_column(server_default=false())

    restroom: Mapped[Restroom] = relationship(back_populates="sensors")
    # Only this relationship writes stall_id; restroom owns restroom_id.
    # The composite FK rejects inconsistent restroom/stall assignments.
    stall: Mapped[Stall] = relationship(back_populates="sensors", foreign_keys=[stall_id])
    events: Mapped[list[SensorEvent]] = relationship(
        back_populates="sensor", passive_deletes="all"
    )
