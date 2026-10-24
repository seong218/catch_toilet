from typing import Annotated, Literal

from pydantic import BaseModel, Field, StrictBool


class SensorUpdateRequest(BaseModel):
    # Validate without trimming or changing case: lookup must be an exact match.
    device_id: Annotated[str, Field(strict=True, min_length=1, pattern=r"\S")]
    occupied: StrictBool


class SensorUpdateResponse(BaseModel):
    success: Literal[True]
    changed: bool
