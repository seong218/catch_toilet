# Database 실행 환경과 모델

`docker-compose.yml`은 PostgreSQL 17과 Backend를 함께 실행한다.
환경변수와 전체 실행 절차는 [`backend/README.md`](../backend/README.md)에 있다.
루트 `docker-compose.yml`이 이 구성을 include하고 `backend/.env`를 읽는다. 아래 명령은 저장소 루트 기준이다.

- DB 데이터는 `catchy-toilet_postgres_data` named volume에 보관한다.
- PostgreSQL 호스트 포트는 `127.0.0.1`에만 공개한다. Backend 컨테이너는 내부 네트워크의 `db:5432`로 연결한다.
- DB 초기 사용자·DB·비밀번호는 빈 volume을 처음 생성할 때만 적용된다. 기존 DB의 비밀번호는 `.env` 수정만으로 변경되지 않는다.
- 스키마 관리는 `backend/alembic/`에서 수행한다. initial revision은 `0001`, `0003`은 센서 순번·보관 인덱스, `0004`는 디미고·GPS, `0005`는 장애인 여부 기본값을 추가한다. 시설 seed는 별도 명령이다.
- 서비스 정의는 이 디렉터리에 유지하고 루트 Compose는 실행 진입점으로 사용한다.
- DB가 healthy가 된 뒤 별도 migrate 작업이 migration·런타임 계정 권한을 설정한 뒤 API가 시작한다.

DB 접속 확인 (저장소 루트):

```bash
docker compose exec db sh -c 'psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c "SELECT 1;"'
```

이 명령은 컨테이너 내부 접속을 검사한다. 애플리케이션의 TCP 인증을 포함한 연결은
`GET /api/health` 또는 Backend의 SQLAlchemy 세션으로 확인한다.

## 모델과 관계

SQLAlchemy 모델은 `backend/app/models/`에 모델별로 분리했다. GPS·시설 미확인·미관측 상태는 null을 허용한다.
현재 디미고 시설과 추가 컬럼·실행 절차는 [디미고 인계](../docs/DIMIGO_GPS.md)와 [API 계약](../docs/api.md)을 따른다.

| 모델 / 테이블 | 필드 |
| --- | --- |
| `Restroom` / `restrooms` | `id`, `name`, `building`, `floor`, `x`, `y`, `created_at` |
| `Stall` / `stalls` | `id`, `restroom_id`, `stall_number`, `occupied`, `has_bidet`, `updated_at` |
| `Sensor` / `sensors` | `id`, `device_id`, `restroom_id`, `stall_id`, `sensor_type`, `active`, `last_sequence`, `last_occupied` |
| `SensorEvent` / `sensor_events` | `id`, `sensor_id`, `event_type`, `value`, `created_at` |
| `RestroomSnapshot` / `restroom_snapshots` | `id`, `restroom_id`, `total_stalls`, `available_stalls`, `available_bidet_stalls`, `captured_at`, `is_test_data` |

- 관계는 `Restroom 1:N Stall`, `Restroom 1:N Sensor`, `Stall 1:N Sensor`, `Sensor 1:N SensorEvent`, `Restroom 1:N RestroomSnapshot`이다.
- 각 ID는 자동 생성되는 양의 정수다. `stall_number`는 양의 정수이며 같은 화장실 안에서 유일하다.
- `device_id`는 전체에서 유일하고 대소문자를 구분한다. 빈 값·공백만 있는 값은 허용하지 않는다.
- 센서의 `(stall_id, restroom_id)`는 칸의 `(id, restroom_id)`를 함께 참조한다. 다른 화장실의 칸을 연결하면 DB가 거부한다. ORM으로 센서를 등록할 때도 `restroom`과 `stall`을 모두 지정한다.
- 모든 부모 참조에 `ON DELETE RESTRICT`를 사용해 연결 데이터와 이벤트 이력의 연쇄 삭제를 막는다. 사용하지 않는 센서는 `active=false`로 관리한다.
- `occupied`, `has_bidet`의 DB 기본값은 `false`, `active`는 `true`다.
- `x`, `y`는 미터 단위의 유한한 실수이며 음수와 0을 허용한다. `floor`는 음수도 허용하는 정수다.
- `name`, `building`, `sensor_type`, `event_type`도 빈 값·공백만 있는 값을 허용하지 않는다.
- `created_at`, `updated_at`은 timezone-aware PostgreSQL `TIMESTAMP WITH TIME ZONE`이며 DB 현재 시각을 기본값으로 사용한다. 향후 통계 집계 시 `Asia/Seoul`로 변환한다.
- `Stall.updated_at`의 일반 SQLAlchemy UPDATE 기본값은 `now()`다. Sensor Update API는 잠금을 획득한 뒤 `clock_timestamp()`를 사용해 Stall과 이벤트에 같은 처리 시각을 명시적으로 저장한다. 동일 상태 요청은 UPDATE가 없어 시각도 유지된다. 직접 SQL을 작성할 때는 이 필드도 명시적으로 갱신해야 한다.
- `SensorEvent.value`는 MVP에서 **변경 후 occupied 상태(boolean)**를 뜻한다. `event_type`은 필수 문자열이며 상태 변경 이벤트 명칭은 `occupancy_changed`를 사용한다. `sensor_type`은 필수 문자열이며 현재 센서에는 `SW-520D`를 사용한다.
- 모델이 상태 변경 이벤트를 자동 생성하지는 않는다. `backend/app/services/sensors.py`가 센서·칸을 잠그고 실제 상태 변경과 이벤트를 같은 트랜잭션에 저장하며, commit 성공 후 API가 WebSocket 이벤트를 큐에 넣고 응답한다. 방송 실패로 commit된 데이터를 롤백하지 않는다.
- 현재 상태의 `total_stalls`, `available_stalls`, `available_bidet_stalls`는 Restroom에 중복 저장하지 않는다. 조회 API는 `backend/app/repositories/restrooms.py`의 공통 SQL로 집계하며, 상세는 집계와 Stall 목록을 한 SQL 문장에서 가져온다. 과거 시점의 집계는 현재 칸 상태로 복원할 수 없어 RestroomSnapshot에 별도로 보존한다.
- WebSocket 집계도 같은 공통 SQL로 상태 변경 트랜잭션 안에서 읽는다. 단일 Backend 프로세스의 Sensor 요청을 commit·방송 등록까지 순차 처리하여 집계와 이벤트 순서를 맞춘다. 직접 DB 수정이나 seed는 WebSocket 이벤트를 생성하지 않는다. WebSocket 추가에 따른 모델·migration 변경은 없다.

## 통계 원본 데이터 검토와 RestroomSnapshot

현재 `SensorEvent`만으로 두 historical availability 비율을 신뢰성 있게 복원할 수는 없다.
[`services/sensors.py`](../backend/app/services/sensors.py)는 실제 변경 때만 변경 후 `occupied`를 저장한다.
[`seed.py`](../backend/app/seed.py)는 최초 상태의 이벤트를 만들지 않으므로 첫 이벤트 전의 관측 상태를 알 수 없다.
또한 이벤트는 현재 Sensor 매핑을 통해 칸을 찾으며, 당시 `has_bidet`, 칸 구성, 매핑 변경 이력을 보존하지 않는다.
서버 수신 시각을 기록할 뿐, 센서 단절·이벤트 누락·관측 가능한 기간도 기록하지 않는다.

`occupied=false` 이벤트 비율은 빈칸이 존재한 시간의 비율이 아니다. 한 시간 동안 1분 비어 있던 칸과
59분 비어 있던 칸 모두 잠금 해제 이벤트는 한 번일 수 있다. 변경이 잦은 칸의 이벤트 수에 가중치를 주거나
상태가 유지된 구간을 누락하면 실제 빈칸 존재 확률과 달라진다. 전체 칸의 초기 상태, 빠짐없는 이벤트,
당시 비데·매핑 이력과 관측 범위가 모두 있다면 시간 구간을 재구성할 수 있지만, 현 구조는 이를 보장하지 않는다.

이를 위해 **화장실 한 곳을 한 시점에 관측한 원본 집계**를 저장하는 `RestroomSnapshot`을 추가했다.
모델·제약조건·migration과 통계 service를 제공한다. 추천에는 가까운 후보 간 보조 기준으로 연결했고 수집 스케줄러는 아직 없다.

| 필드 | 의미 / 제약 |
| --- | --- |
| `id` | 자동 증가 양의 정수 |
| `restroom_id` | 관측 대상 화장실 FK, 부모 삭제 `RESTRICT` |
| `total_stalls` | 관측 당시 전체 칸 수, 0 이상. 이후 칸 증감과 구분하고 당시 빈칸 집계를 검증하는 용도 |
| `available_stalls` | 관측 당시 빈칸 수, `0 <= available_stalls <= total_stalls` |
| `available_bidet_stalls` | 관측 당시 빈 비데 칸 수, `0 <= available_bidet_stalls <= available_stalls` |
| `captured_at` | 실제 관측 시각, 유한한 `TIMESTAMP WITH TIME ZONE`, 자동 기본값 없음 |
| `is_test_data` | 개발·데모·합성 관측이면 `true`, 자동 기본값 없이 작성자가 반드시 지정 |

모든 필드는 non-null이다. 삽입 시각을 과거 관측 시각으로 오인하지 않도록 `captured_at`을 명시한다.
ORM은 timezone 없는 datetime을 거부한다. 직접 SQL을 사용할 때도 UTC 또는 명시적 offset을 전달한다.
동일한 `(restroom_id, captured_at)`은 중복 저장할 수 없다. 이 unique constraint의 B-tree index가
화장실별 기간 조회에도 쓰인다. 서로 다른 timezone 표기의 같은 순간도 중복이다.
요일·시간대·비율은 별도 컬럼에 중복 저장하지 않는다.

통계 집계와 후속 수집에서 적용할 기준:

- 상태 변경 횟수와 독립적인 **일정 간격의 유효한 관측**을 사용한다. 변하지 않은 상태도 표본이다.
  센서 이벤트마다만 스냅샷을 만들거나, 임의 시각의 수동 기록을 같은 가중치의 정기 표본으로 섞지 않는다.
- 미래 수집기는 공통 집계 repository로 같은 DB snapshot의 세 집계값을 얻고 실제 관측 시각과 함께 저장한다.
  반복 작업의 같은 관측은 같은 시각을 재사용한다. 현재의 unique 제약은 정확히 같은 순간의 중복만 막으므로
  일정 간격의 수집과 한 구간 내 중복 방지는 수집기에서도 보장해야 한다.
- `captured_at AT TIME ZONE 'Asia/Seoul'`로 현지 요일·시간대를 정한다. 예를 들어 UTC 일요일 15:30은
  서울 월요일 00:30이다. `ISODOW` 기준은 월요일 1, 일요일 7이며 시간 구간은 `[시작, 종료)`로 다룬다.
  조회할 과거 기간을 제한하고 미래 관측은 제외한다.
- 같은 화장실·요일·시간대의 **동일한 간격으로 수집된 유효 표본** 중 `available_stalls > 0`인 표본의 비율이
  `historical_availability_rate`, `available_bidet_stalls > 0`인 표본의 비율이 `historical_bidet_availability_rate`의 근거가 된다.
  비데가 없는 화장실의 유효한 0과 관측 자체가 없는 상태를 구분한다. 수집 간격이 달라지면 단순 표본 수 비율을 쓰지 않고
  기간별 수집 방식 분리 또는 시간 가중 처리 여부를 먼저 정한다.
- 누락 구간을 0으로 채우거나 마지막 상태로 무제한 연장하지 않는다. `is_test_data=true`는 실사용 통계에서 제외한다.
  유효 표본이 없거나 정할 최소 표본 수·관측 범위를 충족하지 못하면 비율은 `null`로 처리한다.
- 스냅샷 테이블 자체가 센서 신뢰성을 보장하지는 않는다. 현재 `Sensor.active`는 관리자 설정이고
  `Stall.updated_at`은 변경 시각이어서 heartbeat가 아니다. 정기 수집을 켜기 전에 센서 연결·데이터 신선도와
  관측 가능 구간의 판단 기준이 필요하다. DB에 오래 남은 상태를 확인 없이 실제 관측으로 취급하지 않는다.

현재 통계 service는 서울 기준 1시간 구간, 최근 56일(`STAT_LOOKBACK_DAYS`), 최소 30개 관측(`MIN_STAT_SAMPLE_COUNT`)을 기본값으로 사용한다.
요청한 화장실들의 같은 요일·시간대 실사용 관측을 동일한 기준 시각의 단일 SQL로 집계한다. 기간은 `[기준 시각 - 조회 기간, 기준 시각)`이고
현재 순간·미래·테스트 관측은 제외한다. 표본 부족이면 두 비율은 `None`이며 실제 표본 수를 함께 반환한다.
세부 호출법은 [Backend 통계 service](../backend/README.md#통계-service)에 있다.
수집 간격과 품질 정책은 후속 수집 단계에서 정한다. 현재 service의 사용 가능 판정은 최소 표본 수 기준이다.
migration·seed·Sensor API·앱 시작은 스냅샷을 자동 생성하지 않는다. 기존 개발 이벤트로 과거 스냅샷을 역산하지 않는다.
추천은 실시간 후보를 먼저 고른 뒤 가장 가까운 후보와 거리 차이가 `RECOMMENDATION_DISTANCE_TOLERANCE` 이내인 후보만 통계로 비교한다(기본 10m).
관련 통계가 가까운 후보 모두에 충분할 때만 `statistics_used=true`다. 부족하면 최단 거리로 fallback한다.
전체 만석에서는 통계로 후보를 비교하지 않는다. 응답 비율은 항상 최종 선택된 화장실의 값이며 부족하면 `null`이다.

## Migration 적용

로컬 Python 환경에서는 저장소 루트에서 다음을 실행한다.

```bash
backend/.venv/bin/alembic -c backend/alembic.ini upgrade head
backend/.venv/bin/alembic -c backend/alembic.ini current
backend/.venv/bin/alembic -c backend/alembic.ini check
```

Docker 실행에서는 변경된 모델과 migration이 이미지에 포함되도록 Backend를 먼저 빌드한다.
별도 migrate 작업이 관리자 계정으로 migration·런타임 권한을 설정한다. 아래 upgrade 명령으로 명시적인 재적용도 가능하다.

```bash
docker compose up -d --build --wait backend
docker compose run --rm migrate alembic upgrade head
```

initial migration은 참조 순서대로 네 테이블을 생성하고 `downgrade`는 역순으로 제거한다.
`0002`는 `restroom_snapshots`만 추가하고 기존 네 테이블·데이터를 변경하거나 과거 데이터를 채우지 않는다.
`0002 → 0001` downgrade는 스냅샷 이력을 삭제하므로 테스트에서는 임시 스키마에서만 수행한다.
`downgrade base`는 업무 테이블과 데이터를 삭제하므로 개발 DB에 직접 실행하는 대신,
[`backend/tests/test_database.py`](../backend/tests/test_database.py)의 임시 스키마 테스트로 왕복 적용을 검증한다.

## 이전 개발용 fixture (테스트 전용)

현재 `python -m app.seed`는 디미고 본관 8곳·39칸을 반영한다. 아래는 이전 가상 fixture이며 일반 앱 조회에서 제외된다.

`backend/app/seed_data.py`에 정의된 **개발·데모 전용 테스트 데이터**다. 실제 건물 좌표나 센서 측정값이 아니다.
모든 좌표는 임의 원점 `(0, 0)`을 기준으로 한 동일한 미터 단위 평면이며, 예시 사용자 기준 위치도 `(0, 0)`이다.
실행 방법은 [`backend/README.md`](../backend/README.md#디미고-시설-seed-실행)를 따른다.

| 화장실 | building / floor | (x, y) | 칸 / 센서 수 | 초기 빈칸 / 빈 비데 칸 |
| --- | --- | --- | --- | --- |
| 본관 1층 화장실 | 본관 / 1 | (10, 20) | 3 / 3 | 2 / 1 |
| 본관 2층 화장실 | 본관 / 2 | (40, 60) | 5 / 5 | 3 / 2 |
| 체육관 화장실 | 체육관 / 1 | (100, 20) | 4 / 4 | 2 / 1 |

각 칸에는 테스트 센서 하나를 생성하며 `sensor_type="SW-520D"`, `active=true`다.
칸 번호는 각 화장실 안에서 1부터 시작한다. DB의 `id`는 자동 생성되므로 특정 숫자로 고정하지 않는다.

| 화장실 | stall_number | device_id | occupied | has_bidet |
| --- | --- | --- | --- | --- |
| 본관 1층 화장실 | 1 | `stall-a-01` | false | true |
| 본관 1층 화장실 | 2 | `stall-a-02` | true | false |
| 본관 1층 화장실 | 3 | `stall-a-03` | false | false |
| 본관 2층 화장실 | 1 | `stall-b-01` | false | true |
| 본관 2층 화장실 | 2 | `stall-b-02` | true | true |
| 본관 2층 화장실 | 3 | `stall-b-03` | false | false |
| 본관 2층 화장실 | 4 | `stall-b-04` | true | false |
| 본관 2층 화장실 | 5 | `stall-b-05` | false | true |
| 체육관 화장실 | 1 | `stall-c-01` | true | true |
| 체육관 화장실 | 2 | `stall-c-02` | false | false |
| 체육관 화장실 | 3 | `stall-c-03` | true | false |
| 체육관 화장실 | 4 | `stall-c-04` | false | true |

총 화장실 3개, 칸 12개, 센서 12개다. 위 집계는 초기 fixture를 설명하기 위한 값이며 DB 컬럼으로 저장하지 않는다.
이미 존재하는 레코드는 초기 값으로 되돌리지 않으므로 재실행 후 상태는 이 표와 다를 수 있다.
초기 상태 설정은 실제 센서 상태 변경 이력이 아니므로 `SensorEvent`는 생성하지 않는다.

API 컨테이너는 `APP_DB_USER`의 제한된 권한으로 실행한다. 관리자 자격 증명은 API에 전달하지 않는다.
센서 순번·기본 90일 이벤트 보관 정책과 실행 계정 권한은 [보안 안내](../backend/SECURITY.md)를 참고한다.
