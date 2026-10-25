"""Sync confirmed Dimigo facilities without fabricating live sensor states."""

import sys

from sqlalchemy import select, text, update
from sqlalchemy.exc import SQLAlchemyError
from sqlalchemy.orm import Session

from app.db import SessionLocal, engine
from app.models import Restroom, Sensor, Stall
from app.seed_data import DEVELOPMENT_RESTROOMS
from app.dimigo_data import DIMIGO_LATITUDE, DIMIGO_LONGITUDE, DIMIGO_RESTROOMS

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


def seed_dimigo_data(db: Session) -> dict[str, int]:
    db.execute(text("SELECT pg_advisory_xact_lock(:key)"), {"key": SEED_LOCK_KEY})
    created = {"restrooms": 0, "stalls": 0, "sensors": 0}
    for fixture in DIMIGO_RESTROOMS:
        room = db.scalar(select(Restroom).where(Restroom.data_key == fixture.key))
        if room is None:
            room = Restroom(name=fixture.name, building="본관", floor=fixture.floor,
                            x=0, y=0, latitude=DIMIGO_LATITUDE, longitude=DIMIGO_LONGITUDE,
                            gender=fixture.gender, location_source="school_reference",
                            bidet_stalls=fixture.bidets, accessible_stalls=fixture.accessible,
                            data_key=fixture.key, is_active=True)
            db.add(room)
            db.flush()
            created["restrooms"] += 1
        room.accessible_stalls = fixture.accessible
        if fixture.bidets is not None:
            room.bidet_stalls = fixture.bidets
        for number in range(1, fixture.total + 1):
            stall = db.scalar(select(Stall).where(Stall.restroom_id == room.id, Stall.stall_number == number))
            has_bidet = fixture.stall_has_bidet(number)
            is_accessible = number <= fixture.accessible
            if stall is None:
                stall = Stall(restroom_id=room.id, stall_number=number, occupied=None,
                              has_bidet=has_bidet, is_accessible=is_accessible)
                db.add(stall)
                db.flush()
                created["stalls"] += 1
            else:
                # Sync confirmed facilities only; preserve observations,
                # their timestamps and any later-confirmed female bidets.
                facilities = {"is_accessible": is_accessible}
                if has_bidet is not None:
                    facilities["has_bidet"] = has_bidet
                if any(getattr(stall, key) != value for key, value in facilities.items()):
                    db.execute(update(Stall).where(Stall.id == stall.id).values(
                        **facilities, updated_at=Stall.updated_at,
                    ))
            device_id = f"{fixture.key}-{number:02d}"
            sensor = db.scalar(select(Sensor).where(Sensor.device_id == device_id))
            if sensor is None:
                db.add(Sensor(device_id=device_id, restroom_id=room.id, stall_id=stall.id,
                              sensor_type="SW-520D", active=True))
                created["sensors"] += 1
            elif sensor.stall_id != stall.id or sensor.restroom_id != room.id:
                raise SeedConflictError("디미고 센서 매핑이 기존 데이터와 충돌합니다")
    # Archive only the known legacy fixtures, preserving their event history.
    for fixture in DEVELOPMENT_RESTROOMS:
        for room in db.scalars(select(Restroom).where(Restroom.data_key.is_(None), Restroom.name == fixture.name)):
            room.is_active = False
            for sensor in room.sensors:
                sensor.active = False
    return created


def main() -> int:
    try:
        with SessionLocal.begin() as db:
            created = seed_dimigo_data(db)
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
        "디미고 시설 seed 완료 (실시간 상태 미확인): "
        f"신규 화장실 {created['restrooms']}개, "
        f"Stall {created['stalls']}개, Sensor {created['sensors']}개. "
        "기존 데이터는 유지했습니다."
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
