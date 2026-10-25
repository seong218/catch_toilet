"""Ephemeral display overrides. Real sensor storage is never changed.

One backend worker is required (as with the existing WebSocket manager).
Writers replace the whole mapping while holding the manager's update lock;
readers capture one immutable-by-convention snapshot for each SQL statement.
"""
from app.config import get_settings

_overrides: dict[int, bool | None] = {}


def current_overrides() -> dict[int, bool | None]:
    return _overrides if get_settings().enable_simulation else {}


def replace_overrides(values: dict[int, bool | None]) -> None:
    global _overrides
    _overrides = dict(values)
