from math import hypot


def distance_to(origin: tuple[float, float] | None, x: float, y: float) -> float | None:
    """Straight-line distance in the shared meter-based plane, without rounding."""
    if origin is None:
        return None
    return hypot(x - origin[0], y - origin[1])
