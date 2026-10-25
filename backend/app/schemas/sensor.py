from typing import Annotated, Literal

from pydantic import BaseModel, ConfigDict, Field, StrictBool


class SensorUpdateRequest(BaseModel):
    # Accept legacy senders, but no longer interpret their sequence field.
    model_config = ConfigDict(extra="ignore")
    # Validate without trimming or changing case: lookup must be an exact match.
    device_id: Annotated[str, Field(strict=True, max_length=128, pattern=r"^[A-Za-z0-9][A-Za-z0-9._:-]*$")]
    occupied: StrictBool


class SensorUpdateResponse(BaseModel):
    success: Literal[True]
    changed: bool
