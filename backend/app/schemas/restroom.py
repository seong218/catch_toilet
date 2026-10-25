from typing import Annotated, Literal

from pydantic import BaseModel, Field, FiniteFloat


class Stall(BaseModel):
    id: int = Field(gt=0)
    stall_number: int = Field(gt=0)
    occupied: bool | None
    has_bidet: bool | None
    is_accessible: bool
    is_simulated: bool


class Restroom(BaseModel):
    id: int = Field(gt=0)
    name: str = Field(min_length=1)
    building: str = Field(min_length=1)
    floor: int
    x: FiniteFloat
    y: FiniteFloat
    latitude: Annotated[FiniteFloat, Field(ge=-90, le=90)] | None
    longitude: Annotated[FiniteFloat, Field(ge=-180, le=180)] | None
    gender: Literal["male", "female", "unisex"]
    location_source: str
    bidet_stalls: int | None = Field(ge=0)
    accessible_stalls: int = Field(ge=0)
    unknown_stalls: int = Field(ge=0)
    simulated_stalls: int = Field(ge=0)
    distance: Annotated[FiniteFloat, Field(ge=0)] | None
    total_stalls: int = Field(ge=0)
    available_stalls: int = Field(ge=0)
    available_bidet_stalls: int = Field(ge=0)


class RestroomDetail(Restroom):
    stalls: list[Stall]
