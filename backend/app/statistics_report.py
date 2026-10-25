"""Print real historical usage by location and Seoul weekday/hour as JSON."""

import argparse
import json

from sqlalchemy.exc import SQLAlchemyError

from app.config import STATISTICS_TIMEZONE
from app.db import SessionLocal, engine
from app.services.statistics import get_usage_statistics


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--days", type=int, help="Lookback days (default: STAT_LOOKBACK_DAYS)")
    parser.add_argument("--restroom-id", type=int, help="Optional restroom ID")
    args = parser.parse_args()
    try:
        with SessionLocal() as db:
            rows = get_usage_statistics(db, days=args.days, restroom_id=args.restroom_id)
        print(json.dumps({"timezone": STATISTICS_TIMEZONE, "buckets": rows},
                         ensure_ascii=False, indent=2))
    except ValueError as error:
        parser.error(str(error))
    except SQLAlchemyError:
        raise SystemExit("통계 조회 실패: DB 연결 및 alembic upgrade head 적용을 확인하세요.") from None
    finally:
        engine.dispose()


if __name__ == "__main__":
    main()
