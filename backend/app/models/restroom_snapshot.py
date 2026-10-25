from __future__ import annotations

from datetime import datetime
from typing import TYPE_CHECKING

from sqlalchemy import CheckConstraint, DateTime, ForeignKey, UniqueConstraint, true
from sqlalchemy.orm import Mapped, mapped_column, relationship, validates

from app.db import Base

if TYPE_CHECKING:
    from app.models.restroom import Restroom


class RestroomSnapshot(Base):
    """Historical room-level observation, independent of later stall changes.

    captured_at and is_test_data are deliberately required without defaults:
    insertion time is not observation time, and provenance must be explicit.
    Collection scheduling and statistics are separate services.
    """

    __tablename__ = "restroom_snapshots"
    __table_args__ = (
        CheckConstraint("id > 0", name="ck_restroom_snapshots_id_positive"),
        CheckConstraint("total_stalls >= 0", name="ck_restroom_snapshots_total_nonnegative"),
        CheckConstraint(
            "available_stalls >= 0 AND available_stalls <= total_stalls",
            name="ck_restroom_snapshots_available_range",
        ),
        CheckConstraint(
            "available_bidet_stalls >= 0 AND available_bidet_stalls <= available_stalls",
            name="ck_restroom_snapshots_bidet_range",
        ),
        CheckConstraint("isfinite(captured_at)", name="ck_restroom_snapshots_captured_finite"),
        # Also supplies the index for per-room historical time-range queries.
        UniqueConstraint("restroom_id", "captured_at", name="uq_restroom_snapshots_room_captured_at"),
    )

    id: Mapped[int] = mapped_column(primary_key=True)
    restroom_id: Mapped[int] = mapped_column(
        ForeignKey("restrooms.id", name="fk_restroom_snapshots_restroom", ondelete="RESTRICT")
    )
    total_stalls: Mapped[int]
    available_stalls: Mapped[int]
    available_bidet_stalls: Mapped[int]
    captured_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))
    is_test_data: Mapped[bool]
    bidet_sample_valid: Mapped[bool] = mapped_column(server_default=true())

    restroom: Mapped[Restroom] = relationship(back_populates="snapshots")

    @validates("captured_at")
    def validate_captured_at(self, key: str, value: datetime) -> datetime:
        if not isinstance(value, datetime) or value.utcoffset() is None:
            raise ValueError("captured_at must be a timezone-aware datetime")
        return value
