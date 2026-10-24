from __future__ import annotations

from datetime import datetime
from typing import TYPE_CHECKING

from sqlalchemy import CheckConstraint, DateTime, ForeignKey, UniqueConstraint, false, func
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.db import Base

if TYPE_CHECKING:
    from app.models.restroom import Restroom
    from app.models.sensor import Sensor


class Stall(Base):
    __tablename__ = "stalls"
    __table_args__ = (
        CheckConstraint("id > 0", name="ck_stalls_id_positive"),
        CheckConstraint("stall_number > 0", name="ck_stalls_number_positive"),
        UniqueConstraint("restroom_id", "stall_number", name="uq_stalls_restroom_number"),
        # PostgreSQL requires this key for Sensor's composite foreign key.
        UniqueConstraint("id", "restroom_id", name="uq_stalls_id_restroom"),
    )

    id: Mapped[int] = mapped_column(primary_key=True)
    restroom_id: Mapped[int] = mapped_column(
        ForeignKey("restrooms.id", name="fk_stalls_restroom", ondelete="RESTRICT")
    )
    stall_number: Mapped[int]
    occupied: Mapped[bool] = mapped_column(server_default=false())
    has_bidet: Mapped[bool] = mapped_column(server_default=false())
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), onupdate=func.now()
    )

    restroom: Mapped[Restroom] = relationship(back_populates="stalls")
    sensors: Mapped[list[Sensor]] = relationship(
        back_populates="stall", foreign_keys="Sensor.stall_id", passive_deletes="all"
    )
