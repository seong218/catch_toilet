from typing import Annotated

from pydantic import BaseModel, Field, FiniteFloat


class Stall(BaseModel):
    id: int = Field(gt=0)
    stall_number: int = Field(gt=0)
    occupied: bool
    has_bidet: bool


class Restroom(BaseModel):
    id: int = Field(gt=0)
    name: str = Field(min_length=1)
    building: str = Field(min_length=1)
    floor: int
    x: FiniteFloat
    y: FiniteFloat
    distance: Annotated[FiniteFloat, Field(ge=0)] | None
    total_stalls: int = Field(ge=0)
    available_stalls: int = Field(ge=0)
    available_bidet_stalls: int = Field(ge=0)


class RestroomDetail(Restroom):
    stalls: list[Stall]
