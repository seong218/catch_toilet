from typing import Annotated, Literal

from pydantic import BaseModel, Field, StrictBool


class SensorUpdateRequest(BaseModel):
    # Validate without trimming or changing case: lookup must be an exact match.
    device_id: Annotated[str, Field(strict=True, max_length=128, pattern=r"^[A-Za-z0-9][A-Za-z0-9._:-]*$")]
    occupied: StrictBool
    sequence: Annotated[int, Field(strict=True, ge=1, le=9223372036854775807)]


class SensorUpdateResponse(BaseModel):
    success: Literal[True]
    changed: bool
