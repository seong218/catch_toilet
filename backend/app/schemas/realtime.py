from typing import Literal

from pydantic import BaseModel, Field, NonNegativeInt, PositiveInt, StrictBool


class StallUpdated(BaseModel):
    unknown_stalls: int = Field(default=0, ge=0)
    simulated_stalls: int = Field(default=0, ge=0)
    is_simulated: bool = False
    type: Literal["stall.updated"] = "stall.updated"
    restroom_id: PositiveInt
    stall_id: PositiveInt
    occupied: StrictBool | None
    total_stalls: NonNegativeInt
    available_stalls: NonNegativeInt
    available_bidet_stalls: NonNegativeInt
