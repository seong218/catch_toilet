"""Import all mapped models to register them with Base.metadata."""

from app.models.restroom import Restroom
from app.models.restroom_snapshot import RestroomSnapshot
from app.models.sensor import Sensor
from app.models.sensor_event import SensorEvent
from app.models.stall import Stall
from app.models.statistics_tracking import StatisticsTracking

__all__ = ["Restroom", "Stall", "Sensor", "SensorEvent", "RestroomSnapshot", "StatisticsTracking"]
