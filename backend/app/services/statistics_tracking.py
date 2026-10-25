"""Control collection without restarting the API or deleting historical rows."""

from sqlalchemy import func, select
from sqlalchemy.orm import Session

from app.config import get_settings
from app.models import StatisticsTracking


def get_tracking_state(db: Session, *, for_update: bool = False) -> StatisticsTracking:
    query = select(StatisticsTracking).where(StatisticsTracking.id == 1)
    if for_update:
        query = query.with_for_update()
    state = db.scalar(query.execution_options(populate_existing=True))
    if state is None:
        raise ValueError("통계 추적 설정이 없습니다. migration 적용을 확인하세요.")
    return state


def set_tracking(db: Session, *, enabled: bool) -> StatisticsTracking:
    """The caller commits. Row locking serializes commands with collection."""
    if enabled and not get_settings().enable_statistics_collection:
        raise ValueError("ENABLE_STATISTICS_COLLECTION=true로 서버를 실행한 후 시작하세요.")
    state = get_tracking_state(db, for_update=True)
    if state.enabled == enabled:
        return state  # Retrying start/stop keeps the original transition time.
    changed_at = db.scalar(select(func.clock_timestamp()))
    state.enabled = enabled
    if enabled:
        state.started_at = changed_at
        state.stopped_at = None
    else:
        state.stopped_at = changed_at
    db.flush()
    return state
