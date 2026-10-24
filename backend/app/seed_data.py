"""Development-only fixtures, not real locations, sensor readings, or statistics."""

from dataclasses import dataclass


@dataclass(frozen=True)
class StallSeed:
    occupied: bool
    has_bidet: bool


@dataclass(frozen=True)
class RestroomSeed:
    name: str
    building: str
    floor: int
    x: float
    y: float
    device_prefix: str
    stalls: tuple[StallSeed, ...]


# A shared demonstration coordinate plane in meters, with an arbitrary (0, 0) origin.
# Tuple order defines stable stall numbers starting at 1.
DEVELOPMENT_RESTROOMS = (
    RestroomSeed(
        name="본관 1층 화장실", building="본관", floor=1, x=10.0, y=20.0,
        device_prefix="stall-a",
        stalls=(
            StallSeed(occupied=False, has_bidet=True),
            StallSeed(occupied=True, has_bidet=False),
            StallSeed(occupied=False, has_bidet=False),
        ),
    ),
    RestroomSeed(
        name="본관 2층 화장실", building="본관", floor=2, x=40.0, y=60.0,
        device_prefix="stall-b",
        stalls=(
            StallSeed(occupied=False, has_bidet=True),
            StallSeed(occupied=True, has_bidet=True),
            StallSeed(occupied=False, has_bidet=False),
            StallSeed(occupied=True, has_bidet=False),
            StallSeed(occupied=False, has_bidet=True),
        ),
    ),
    RestroomSeed(
        name="체육관 화장실", building="체육관", floor=1, x=100.0, y=20.0,
        device_prefix="stall-c",
        stalls=(
            StallSeed(occupied=True, has_bidet=True),
            StallSeed(occupied=False, has_bidet=False),
            StallSeed(occupied=True, has_bidet=False),
            StallSeed(occupied=False, has_bidet=True),
        ),
    ),
)
