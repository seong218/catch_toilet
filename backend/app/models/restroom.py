from __future__ import annotations

from datetime import datetime
from typing import TYPE_CHECKING

from sqlalchemy import CheckConstraint, DateTime, Float, Text, func
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.db import Base

if TYPE_CHECKING:
    from app.models.restroom_snapshot import RestroomSnapshot
    from app.models.sensor import Sensor
    from app.models.stall import Stall


class Restroom(Base):
    __tablename__ = "restrooms"
    __table_args__ = (
        CheckConstraint("id > 0", name="ck_restrooms_id_positive"),
        CheckConstraint("name ~ '[^[:space:]]'", name="ck_restrooms_name_not_blank"),
        CheckConstraint("building ~ '[^[:space:]]'", name="ck_restrooms_building_not_blank"),
        CheckConstraint(
            "x > '-Infinity'::float8 AND x < 'Infinity'::float8",
            name="ck_restrooms_x_finite",
        ),
        CheckConstraint(
            "y > '-Infinity'::float8 AND y < 'Infinity'::float8",
            name="ck_restrooms_y_finite",
        ),
    )

    id: Mapped[int] = mapped_column(primary_key=True)
    name: Mapped[str] = mapped_column(Text)
    building: Mapped[str] = mapped_column(Text)
    floor: Mapped[int]
    x: Mapped[float] = mapped_column(Float)
    y: Mapped[float] = mapped_column(Float)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now()
    )

    stalls: Mapped[list[Stall]] = relationship(
        back_populates="restroom", passive_deletes="all", order_by="Stall.stall_number"
    )
    sensors: Mapped[list[Sensor]] = relationship(
        back_populates="restroom", passive_deletes="all"
    )
    snapshots: Mapped[list[RestroomSnapshot]] = relationship(
        back_populates="restroom", passive_deletes="all"
    )
