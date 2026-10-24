from typing import Annotated

from pydantic import Field, FiniteFloat

from app.schemas.restroom import Restroom


class Recommendation(Restroom):
    distance: Annotated[FiniteFloat, Field(ge=0)]
    statistics_used: bool
    historical_availability_rate: Annotated[FiniteFloat, Field(ge=0, le=1)] | None
    historical_bidet_availability_rate: Annotated[FiniteFloat, Field(ge=0, le=1)] | None
