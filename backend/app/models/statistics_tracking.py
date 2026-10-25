"""Persistent, explicitly controlled collection state (one row)."""

from datetime import datetime

from sqlalchemy import CheckConstraint, DateTime, false
from sqlalchemy.orm import Mapped, mapped_column

from app.db import Base


class StatisticsTracking(Base):
    __tablename__ = "statistics_tracking"
    __table_args__ = (
        CheckConstraint("id = 1", name="ck_statistics_tracking_singleton"),
        CheckConstraint(
            "NOT enabled OR (started_at IS NOT NULL AND stopped_at IS NULL)",
            name="ck_statistics_tracking_started",
        ),
        CheckConstraint(
            "stopped_at IS NULL OR (started_at IS NOT NULL AND stopped_at >= started_at)",
            name="ck_statistics_tracking_order",
        ),
        CheckConstraint(
            "isfinite(started_at) AND isfinite(stopped_at)",
            name="ck_statistics_tracking_finite",
        ),
    )

    id: Mapped[int] = mapped_column(primary_key=True, autoincrement=False)
    enabled: Mapped[bool] = mapped_column(server_default=false())
    started_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    stopped_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
