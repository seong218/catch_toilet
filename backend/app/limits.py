"""Bounded sensor admission for the documented single-worker deployment."""

from dataclasses import dataclass
from math import ceil
from threading import Lock
from time import monotonic

from app.config import Settings


class SensorRateLimitError(Exception):
    def __init__(self, retry_after: float):
        self.retry_after = max(1, ceil(retry_after))


@dataclass
class _Bucket:
    tokens: float
    updated: float


class SensorRateLimiter:
    def __init__(self):
        self._lock = Lock()
        self._devices: dict[str, _Bucket] = {}
        self._global: _Bucket | None = None

    def consume(self, device_id: str, settings: Settings) -> None:
        # Only authenticated, configured IDs reach this method. The mapping is
        # bounded by configured devices, not by attacker-supplied identifiers.
        with self._lock:
            now = monotonic()
            self._devices = {key: value for key, value in self._devices.items()
                             if key in settings.sensor_api_keys}
            device = self._devices.setdefault(device_id, _Bucket(settings.sensor_rate_burst, now))
            if self._global is None:
                self._global = _Bucket(settings.sensor_global_burst, now)
            buckets = ((device, settings.sensor_rate_per_second, settings.sensor_rate_burst),
                       (self._global, settings.sensor_global_rate_per_second, settings.sensor_global_burst))
            wait = 0.0
            for bucket, rate, burst in buckets:
                bucket.tokens = min(burst, bucket.tokens + max(0, now - bucket.updated) * rate)
                bucket.updated = now
                wait = max(wait, (1 - bucket.tokens) / rate)
            if wait > 0:
                raise SensorRateLimitError(wait)
            for bucket, _, _ in buckets:
                bucket.tokens -= 1
