from sqlalchemy import select
from sqlalchemy.orm import Session

from app.models import Restroom, Stall
from app.repositories.restrooms import get_restroom
from app.schemas.realtime import StallUpdated
from app.simulation_state import current_overrides, replace_overrides


class SimulationStallNotFound(Exception):
    pass


class SimulationCapacityExceeded(Exception):
    pass


def change_simulation(db: Session, states: dict[int, bool | None] | None,
                      reset_ids: list[int] | None = None) -> list[StallUpdated]:
    """Validate and prepare everything before atomically publishing a new map.

    The caller holds the WebSocket manager's update lock, also used by sensors.
    This function only SELECTs from PostgreSQL; synthetic events are not saved.
    Notifications carry sequential counts so cached client details stay valid.
    """
    previous = current_overrides()
    proposed = dict(previous)
    ids = list(states) if states is not None else (reset_ids if reset_ids is not None else list(previous))
    if not ids:
        return []
    if states is not None:
        proposed.update(states)
    else:
        for stall_id in ids:
            proposed.pop(stall_id, None)
    if len(proposed) > 64:
        raise SimulationCapacityExceeded
    notifications = []
    with db.begin():
        mapping = dict(db.execute(select(Stall.id, Stall.restroom_id).join(Restroom).where(
            Stall.id.in_(ids), Restroom.is_active.is_(True),
        )).all())
        if (states is not None or reset_ids is not None) and len(mapping) != len(ids):
            raise SimulationStallNotFound
        step = dict(previous)
        for stall_id in ids:
            if states is not None:
                if stall_id in previous and previous[stall_id] is states[stall_id]:
                    continue
                step[stall_id] = states[stall_id]
            else:
                if stall_id not in previous:
                    continue
                step.pop(stall_id, None)
            if stall_id not in mapping:
                continue  # Reset-all also forgets any subsequently archived room.
            room = get_restroom(db, mapping[stall_id], overrides=step)
            stall = next(stall for stall in room["stalls"] if stall["id"] == stall_id)
            notifications.append(StallUpdated(
                restroom_id=room["id"], stall_id=stall_id,
                occupied=stall["occupied"], is_simulated=stall["is_simulated"],
                **{key: room[key] for key in (
                    "total_stalls", "available_stalls", "available_bidet_stalls",
                    "unknown_stalls", "simulated_stalls",
                )},
            ))
    # Commit/connection errors above leave the previously displayed state intact.
    replace_overrides(proposed)
    return notifications
