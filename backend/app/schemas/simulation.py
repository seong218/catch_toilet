from typing import Annotated

from pydantic import BaseModel, ConfigDict, Field, StrictBool, StrictInt, model_validator

StallId = Annotated[StrictInt, Field(gt=0, le=2147483647)]


class SimulatedState(BaseModel):
    model_config = ConfigDict(extra="forbid")
    stall_id: StallId
    occupied: StrictBool | None


class SimulationUpdate(BaseModel):
    model_config = ConfigDict(extra="forbid")
    states: list[SimulatedState] = Field(min_length=1, max_length=64)

    @model_validator(mode="after")
    def unique_stalls(self):
        if len({state.stall_id for state in self.states}) != len(self.states):
            raise ValueError("Duplicate stall IDs")
        return self


class SimulationReset(BaseModel):
    model_config = ConfigDict(extra="forbid")
    stall_ids: list[StallId] | None = Field(default=None, min_length=1, max_length=64)

    @model_validator(mode="after")
    def unique_stalls(self):
        if self.stall_ids is not None and len(set(self.stall_ids)) != len(self.stall_ids):
            raise ValueError("Duplicate stall IDs")
        return self


class SimulationResponse(BaseModel):
    success: bool = True
    changed: int = Field(ge=0)
