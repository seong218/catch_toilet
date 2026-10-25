from sqlalchemy.orm import Session

from app.config import get_settings
from app.repositories import restrooms
from app.schemas.recommendation import Recommendation
from app.services.location import GPSLocation, restroom_distance
from app.services.statistics import get_restrooms_statistics


class NoRestroomsFoundError(Exception):
    """There are no registered restrooms."""


class NoAvailableBidetStallsError(Exception):
    """Ordinary stalls are available, but no vacant bidet stall exists."""


class LiveAvailabilityUnavailableError(Exception):
    pass


class RestroomLocationUnavailableError(Exception):
    pass


def recommend_restroom(
    db: Session, origin: GPSLocation | tuple[float, float], *, bidet_required: bool = False,
    gender: str | None = None,
) -> Recommendation:
    """Filter live availability, then compare statistics only within a near group.

    Partial history never penalizes an unknown candidate: if any near candidate
    lacks the relevant rate, keep the nearest. Full rooms only use distance.
    """
    rows = restrooms.list_restrooms(db, gender=gender)
    if not rows:
        raise NoRestroomsFoundError

    available = [room for room in rows if room["available_stalls"] > 0]
    if not available:
        if any(room["unknown_stalls"] > 0 for room in rows):
            raise LiveAvailabilityUnavailableError
        # The all-full fallback applies even when a bidet was required.
        candidates = rows
    elif bidet_required:
        candidates = [room for room in available if room["available_bidet_stalls"] > 0]
        if not candidates:
            raise NoAvailableBidetStallsError
    else:
        candidates = available

    located = [(room, restroom_distance(origin, room)) for room in candidates]
    ranked = sorted(
        ((room, distance) for room, distance in located if distance is not None),
        key=lambda candidate: (candidate[1], candidate[0]["id"]),
    )
    if not ranked:
        raise RestroomLocationUnavailableError
    room, distance = ranked[0]
    tolerance = get_settings().recommendation_distance_tolerance
    nearby = (
        [candidate for candidate in ranked if candidate[1] - distance <= tolerance]
        if available else ranked[:1]
    )
    statistics = get_restrooms_statistics(db, (candidate[0]["id"] for candidate in nearby))
    metric = "historical_bidet_availability_rate" if bidet_required else "historical_availability_rate"
    rates = {room_id: getattr(history, metric) for room_id, history in statistics.items()}
    statistics_used = bool(available) and len(nearby) > 1 and all(rate is not None for rate in rates.values())
    if statistics_used:
        room, distance = min(
            nearby,
            key=lambda candidate: (-rates[candidate[0]["id"]], candidate[1], candidate[0]["id"]),
        )
    selected_statistics = statistics[room["id"]]
    return Recommendation(
        **room,
        distance=distance,
        statistics_used=statistics_used,
        historical_availability_rate=selected_statistics.historical_availability_rate,
        historical_bidet_availability_rate=selected_statistics.historical_bidet_availability_rate,
    )
