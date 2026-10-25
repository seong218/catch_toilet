"""Inventory supplied by the project owner; no fabricated live observations."""

from dataclasses import dataclass

# School representative point from the Ministry of Education school map:
# https://www.hifive.go.kr/search/schoolMap.do?sch_seq=653
# Not a surveyed restroom entrance; replace with measured coordinates later.
DIMIGO_LATITUDE = 37.34156740773243
DIMIGO_LONGITUDE = 126.83126714636612


@dataclass(frozen=True)
class CampusRestroom:
    gender: str
    floor: int
    total: int
    bidets: int | None
    accessible: int = 0

    def stall_has_bidet(self, number: int) -> bool | None:
        # The first accessible stall on 1F has no bidet. Known bidets start
        # at the first ordinary stall; female bidet counts remain unknown.
        if number <= self.accessible:
            return False
        if self.bidets is None:
            return None
        return number <= self.accessible + self.bidets

    @property
    def key(self):
        level = "b1" if self.floor == -1 else str(self.floor)
        return f"dimigo-main-{self.gender[0]}-{level}"

    @property
    def name(self):
        level = "지하 1층" if self.floor == -1 else f"{self.floor}층"
        gender = "남자" if self.gender == "male" else "여자"
        return f"본관 {level} {gender} 화장실"


DIMIGO_RESTROOMS = (
    CampusRestroom("male", -1, 5, 1), CampusRestroom("male", 1, 4, 3, 1),
    CampusRestroom("male", 2, 5, 2), CampusRestroom("male", 3, 5, 2),
    CampusRestroom("female", -1, 5, None), CampusRestroom("female", 1, 4, None, 1),
    CampusRestroom("female", 2, 6, None), CampusRestroom("female", 3, 5, None),
)
