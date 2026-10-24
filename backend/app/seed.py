"""Insert development fixtures with `python -m app.seed` after migrations."""

import sys

from sqlalchemy import select, text
from sqlalchemy.exc import SQLAlchemyError
from sqlalchemy.orm import Session

from app.db import SessionLocal, engine
from app.models import Restroom, Sensor, Stall
from app.seed_data import DEVELOPMENT_RESTROOMS

# Stable PostgreSQL transaction lock shared by all invocations of this seed.
SEED_LOCK_KEY = 0x43545F53454544  # CT_SEED


class SeedConflictError(RuntimeError):
    """Existing records cannot be unambiguously reused without changing them."""


def seed_development_data(db: Session) -> dict[str, int]:
    """Insert missing records only. The caller must commit or roll back as a unit."""
    # Restroom has no natural-key UNIQUE constraint; serialize seed invocations.
    db.execute(text("SELECT pg_advisory_xact_lock(:key)"), {"key": SEED_LOCK_KEY})
    created = {"restrooms": 0, "stalls": 0, "sensors": 0}

    for fixture in DEVELOPMENT_RESTROOMS:
        matches = db.scalars(select(Restroom).where(
            Restroom.name == fixture.name,
            Restroom.building == fixture.building,
            Restroom.floor == fixture.floor,
        ).limit(2)).all()
        if len(matches) > 1:
            raise SeedConflictError(f"동일한 이름·건물·층의 화장실이 여러 개입니다: {fixture.name}")
        if matches:
            restroom = matches[0]
        else:
            restroom = Restroom(
                name=fixture.name, building=fixture.building, floor=fixture.floor,
                x=fixture.x, y=fixture.y,
            )
            db.add(restroom)
            db.flush()
            created["restrooms"] += 1

        for number, stall_fixture in enumerate(fixture.stalls, start=1):
            stall = db.scalar(select(Stall).where(
                Stall.restroom_id == restroom.id,
                Stall.stall_number == number,
            ))
            if stall is None:
                stall = Stall(
                    restroom_id=restroom.id, stall_number=number,
                    occupied=stall_fixture.occupied, has_bidet=stall_fixture.has_bidet,
                )
                db.add(stall)
                db.flush()
                created["stalls"] += 1

            device_id = f"{fixture.device_prefix}-{number:02d}"
            sensor = db.scalar(select(Sensor).where(Sensor.device_id == device_id))
            if sensor is None:
                db.add(Sensor(
                    device_id=device_id, restroom_id=restroom.id, stall_id=stall.id,
                    sensor_type="SW-520D", active=True,
                ))
                db.flush()
                created["sensors"] += 1
            elif sensor.restroom_id != restroom.id or sensor.stall_id != stall.id:
                raise SeedConflictError(f"센서가 다른 화장실 또는 칸에 연결되어 있습니다: {device_id}")

    return created


def main() -> int:
    try:
        with SessionLocal.begin() as db:
            created = seed_development_data(db)
    except SeedConflictError as error:
        print(f"Seed 중단: {error} 변경사항을 모두 롤백했습니다.", file=sys.stderr)
        return 1
    except SQLAlchemyError:
        # Avoid printing driver errors, SQL parameters, or connection credentials.
        print(
            "Seed 실패: DB 연결과 alembic upgrade head 적용 여부, 제약조건을 확인하세요. "
            "변경사항을 모두 롤백했습니다.",
            file=sys.stderr,
        )
        return 1
    finally:
        engine.dispose()

    print(
        "개발용 테스트 seed 완료: "
        f"신규 화장실 {created['restrooms']}개, "
        f"Stall {created['stalls']}개, Sensor {created['sensors']}개. "
        "기존 데이터는 유지했습니다."
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
