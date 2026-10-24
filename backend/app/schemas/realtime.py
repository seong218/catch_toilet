from typing import Literal

from pydantic import BaseModel, NonNegativeInt, PositiveInt, StrictBool


class StallUpdated(BaseModel):
    type: Literal["stall.updated"] = "stall.updated"
    restroom_id: PositiveInt
    stall_id: PositiveInt
    occupied: StrictBool
    total_stalls: NonNegativeInt
    available_stalls: NonNegativeInt
    available_bidet_stalls: NonNegativeInt
