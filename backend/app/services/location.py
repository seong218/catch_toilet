from dataclasses import dataclass
from math import asin, cos, hypot, isfinite, radians, sin, sqrt


MAX_COORDINATE = 1_000_000


class InvalidDistanceError(ValueError):
    """The requested distance cannot be represented as a finite number."""


@dataclass(frozen=True)
class GPSLocation:
    latitude: float
    longitude: float


def geographic_distance(origin: GPSLocation, latitude: float, longitude: float) -> float:
    if not all(isfinite(value) for value in (origin.latitude, origin.longitude, latitude, longitude)):
        raise InvalidDistanceError
    if not (-90 <= origin.latitude <= 90 and -90 <= latitude <= 90
            and -180 <= origin.longitude <= 180 and -180 <= longitude <= 180):
        raise InvalidDistanceError
    lat1, lat2 = radians(origin.latitude), radians(latitude)
    a = sin((lat2 - lat1) / 2) ** 2 + cos(lat1) * cos(lat2) * sin(radians(longitude - origin.longitude) / 2) ** 2
    return 2 * 6371008.8 * asin(sqrt(min(1.0, max(0.0, a))))


def restroom_distance(origin: GPSLocation | tuple[float, float] | None, room: dict) -> float | None:
    if isinstance(origin, GPSLocation):
        if room["latitude"] is None or room["longitude"] is None:
            return None
        return geographic_distance(origin, room["latitude"], room["longitude"])
    return distance_to(origin, room["x"], room["y"])


def distance_to(origin: tuple[float, float] | None, x: float, y: float) -> float | None:
    """Straight-line distance in the shared meter-based plane, without rounding."""
    if origin is None:
        return None
    result = hypot(x - origin[0], y - origin[1])
    if not isfinite(result):
        raise InvalidDistanceError
    return result
