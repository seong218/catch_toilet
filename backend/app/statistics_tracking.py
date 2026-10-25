"""Start, stop, or inspect statistics tracking on this backend's database."""

import argparse
import json

from sqlalchemy.exc import SQLAlchemyError

from app.config import get_settings
from app.db import SessionLocal, engine
from app.services.statistics_tracking import get_tracking_state, set_tracking


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=("start", "stop", "status"))
    args = parser.parse_args()
    try:
        with SessionLocal.begin() as db:
            state = (get_tracking_state(db) if args.action == "status"
                     else set_tracking(db, enabled=args.action == "start"))
            output = {
                "tracking": state.enabled,
                "collector_enabled": get_settings().enable_statistics_collection,
                "started_at": state.started_at.isoformat() if state.started_at else None,
                "stopped_at": state.stopped_at.isoformat() if state.stopped_at else None,
            }
        print(json.dumps(output, ensure_ascii=False, indent=2))
    except ValueError as error:
        parser.error(str(error))
    except SQLAlchemyError:
        raise SystemExit("추적 설정 실패: DB 연결, migration 및 런타임 권한을 확인하세요.") from None
    finally:
        engine.dispose()


if __name__ == "__main__":
    main()
