from sqlalchemy import func, select
from sqlalchemy.orm import Session

from app.models import SensorEvent
from app.limits import SensorRateLimitError
from app.repositories import restrooms, sensors
from app.schemas.realtime import StallUpdated
from app.simulation_state import current_overrides


class SensorNotFoundError(Exception):
    """The device is not registered."""


class InactiveSensorError(Exception):
    """The registered sensor is disabled."""


class InvalidSensorMappingError(Exception):
    """The sensor's restroom/stall mapping is missing or inconsistent."""


def update_stall_occupancy(
    db: Session, device_id: str, occupied: bool, *, minimum_interval: float = 1,
) -> StallUpdated | None:
    """Own one transaction; return only after commit succeeds.

    Call with a fresh session. Lock sensor then stall, compare the locked state,
    and persist the state and event together. Exceptions roll back both writes.
    The API holds the manager's update lock through this call and publication.
    """
    notification = None
    with db.begin():
        sensor = sensors.get_sensor_for_update(db, device_id)
        if sensor is None:
            raise SensorNotFoundError
        if not sensor.active:
            raise InactiveSensorError
        if sensor.stall_id is None or sensor.restroom_id is None:
            raise InvalidSensorMappingError

        stall = sensors.get_stall_for_update(db, sensor.stall_id)
        if (
            stall is None
            or stall.restroom_id != sensor.restroom_id
            or not sensors.restroom_exists(db, sensor.restroom_id)
        ):
            raise InvalidSensorMappingError

        # Every accepted report refreshes liveness, including unchanged states.
        # Client ordering/replay detection is no longer part of the API.
        observed_at = db.scalar(select(func.clock_timestamp()))
        changed = stall.occupied != occupied
        if changed:
            # Use processing time AFTER lock acquisition, not transaction start
            # time, so a queued request cannot backdate the previous update.
            changed_at = observed_at
            remaining = minimum_interval - (changed_at - stall.updated_at).total_seconds()
            if stall.occupied is not None and remaining > 0:
                raise SensorRateLimitError(remaining)
            stall.occupied = occupied
            stall.updated_at = changed_at
            db.flush()
            db.add(SensorEvent(
                sensor_id=sensor.id,
                event_type="occupancy_changed",
                value=occupied,
                created_at=changed_at,
            ))
            summary = restrooms.get_restroom_summary(db, stall.restroom_id)
            overrides = current_overrides()
            notification = StallUpdated(
                restroom_id=stall.restroom_id,
                stall_id=stall.id,
                occupied=overrides.get(stall.id, occupied),
                is_simulated=stall.id in overrides,
                simulated_stalls=summary["simulated_stalls"],
                total_stalls=summary["total_stalls"],
                available_stalls=summary["available_stalls"],
                available_bidet_stalls=summary["available_bidet_stalls"],
                unknown_stalls=summary["unknown_stalls"],
            )
        sensor.last_occupied = occupied
        sensor.last_seen_at = observed_at
        # An unchanged state keeps the stall timestamp and event history intact.
    return notification
