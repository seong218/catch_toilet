# Backend 실행 환경과 API

Python 3.13, FastAPI, SQLAlchemy 2, psycopg 3, Alembic을 사용한다.
현재 `GET /api/health`, `GET /api/restrooms`, `GET /api/restrooms/{restroom_id}`,
`GET /api/restrooms/recommend`, `POST /api/sensors/stall`, `WS /ws`를 제공한다.
계약은 [`docs/api.md`](../docs/api.md)를 따른다.

## 환경변수

저장소 루트에서 최초 한 번 실행한다. 기존 `.env`가 있으면 덮어쓰지 않는다.

```bash
cp backend/.env.example backend/.env
```

`backend/.env`의 `POSTGRES_PASSWORD`에 직접 생성한 비밀번호를 입력한다.
예를 들어 `python3 -c 'import secrets; print(secrets.token_urlsafe(32))'`로 생성할 수 있다.
`.env`는 Git 및 Docker 빌드에서 제외한다. 실제 비밀번호를 예제나 코드에 기록하지 않는다.

| 변수 | 용도 |
| --- | --- |
| `POSTGRES_HOST` | 로컬 실행의 DB 호스트, 기본 `localhost`. Compose 내부에서는 `db`로 설정 |
| `POSTGRES_PORT` | 로컬 DB 포트 및 Compose의 호스트 공개 포트, 기본 `5432`. 컨테이너 내부는 `5432` |
| `POSTGRES_DB` | 필수 DB 이름 |
| `POSTGRES_USER` | 필수 DB 사용자 |
| `POSTGRES_PASSWORD` | 필수 비밀번호, 빈 값 불가 |
| `DB_CONNECT_TIMEOUT` | 연결 및 connection pool 대기 제한(초), 기본 `5` |
| `DB_STATEMENT_TIMEOUT_MS` | SQL 실행 제한(밀리초), 기본 `5000` |
| `MIN_STAT_SAMPLE_COUNT` | 통계를 사용할 최소 관측 표본 수, 기본 `30`, 1 이상 |
| `STAT_LOOKBACK_DAYS` | 통계의 과거 조회 기간(일), 기본 `56`, 1~3650 |
| `RECOMMENDATION_DISTANCE_TOLERANCE` | 가장 가까운 사용 가능 후보와의 거리 차이 허용값(m), 기본 `10`, 0 이상의 유한한 수. 0이면 같은 거리끼리만 비교 |
| `API_PORT` | Compose에서 공개할 API 포트, 기본 `8000` |
| `CORS_ALLOWED_ORIGINS` | 브라우저 프론트엔드의 허용 origin JSON 배열. 기본 localhost·127.0.0.1의 3000·8080 포트, `[]`로 비활성화 |

FastAPI와 Alembic 모두 작업 디렉터리와 무관하게 `backend/.env`를 읽는다.
프로세스 환경변수가 `.env`보다 우선한다. DB URL은 위 값으로 조립하므로 별도 `DATABASE_URL`은 사용하지 않는다.
설정은 프로세스에서 캐시한다. `.env`를 바꾸면 `docker compose up -d --wait backend`로 컨테이너를 갱신한다.
단순 `docker compose restart`는 변경된 Compose 환경변수를 반영하지 않는다. 로컬 Uvicorn은 다시 실행한다.
루트 Compose는 `backend/.env`를 자동으로 읽으므로 루트 `.env`를 추가할 필요가 없다.

## Docker로 전체 실행

Docker Compose **2.20.3 이상**이 필요하다 (`docker compose version`으로 확인).
루트 Compose가 기존 `database/docker-compose.yml`을 [include](https://docs.docker.com/compose/how-tos/multiple-compose-files/include/)하므로
서비스 정의는 한 곳에서 관리한다. 다음 명령은 모두 저장소 루트 기준이다.

`backend/.env` 준비 후 터미널에서 실행한다. 처음에는 이미지를 자동으로 빌드한다.

```bash
docker compose up
```

실행 순서는 **PostgreSQL healthcheck → Alembic upgrade head → 단일 Uvicorn 프로세스**다.
`backend/docker-start.sh`에서 migration이 실패하면 서버를 시작하지 않고 오류로 종료한다.
개발용 seed는 자동 실행하지 않는다. 빈 DB에서 화장실 목록은 `[]`이며 아래 seed 명령으로 데모 데이터를 넣는다.

백그라운드 실행 또는 소스·migration 변경 후 이미지 갱신:

```bash
docker compose up -d --build --wait
docker compose exec backend python -m app.seed
docker compose ps
curl -i http://localhost:8000/api/health
```

정상 응답은 `200 {"status":"ok"}`다. DB에 실제로 `SELECT 1`을 실행하며,
접근 실패 시 `503 {"detail":"Database unavailable"}`를 반환한다. DB가 복구되면 재시작 없이 재연결한다.
Swagger UI는 <http://localhost:8000/docs>, OpenAPI는 <http://localhost:8000/openapi.json>이다.
`API_PORT`를 바꾸면 접속 포트도 변경한다. Swagger UI의 JS/CSS는 기본 CDN에서 가져온다.

문제 확인과 종료:

```bash
docker compose logs --tail=100 backend db
docker compose down
```

PostgreSQL 데이터는 기존 `catchy-toilet_postgres_data` named volume에 유지된다.
`down -v`는 데이터를 삭제하므로 일반 종료에는 사용하지 않는다.
DB 초기 계정 설정은 빈 volume에만 적용된다. 기존 비밀번호를 `.env`만 바꾸면 인증 오류가 나므로 기존 DB의 설정과 맞춘다.
포트 충돌 시 `API_PORT` 또는 `POSTGRES_PORT`를 변경한다.

기존 명령 `docker compose --env-file backend/.env -f database/docker-compose.yml ...`도 같은 서비스·볼륨을 사용한다.
로컬 개발용 구성이고 WebSocket manager는 메모리에 있으므로 Backend worker/replica는 하나로 유지한다.

## Migration 명령

Compose 시작 시 자동 적용된다. 현재 revision 확인과 명시적인 재적용은 다음과 같다.

```bash
docker compose exec backend alembic current
docker compose exec backend alembic upgrade head
docker compose exec backend alembic check
```

서버가 시작하지 못한 상태에서 migration만 실행하려면 DB를 먼저 준비한다.

```bash
docker compose up -d --wait db
docker compose run --rm --build backend alembic upgrade head
```

모델·migration 파일 변경 후에는 이미지를 다시 빌드한다. 데이터가 있는 개발 DB에 downgrade를 실행하지 않는다.

## 개발용 CORS와 기기 접속

[FastAPI CORSMiddleware](https://fastapi.tiangolo.com/tutorial/cors/)를 사용한다.
기본 허용 origin은 `http://localhost:3000`, `http://127.0.0.1:3000`,
`http://localhost:8080`, `http://127.0.0.1:8080`이다. GET·POST 및 JSON Content-Type preflight를 지원하며
쿠키 credentials는 사용하지 않는다. 허용되지 않은 origin의 preflight는 400이다.

브라우저 프론트엔드의 실제 origin(프로토콜·호스트·포트)에 맞춰 `backend/.env`를 변경한다.
경로와 마지막 `/`를 붙이지 않고 JSON 배열로 작성한다. 예를 들어 5173 포트만 허용하려면:

```dotenv
CORS_ALLOWED_ORIGINS='["http://localhost:5173","http://127.0.0.1:5173"]'
```

변경 후 `docker compose up -d --wait backend`를 실행한다. 브라우저의 포트가 매번 달라지면 개발 서버 포트를 고정한다.
`CORS_ALLOWED_ORIGINS='[]'`는 cross-origin 허용을 끈다. 같은 origin의 `/docs`는 그대로 사용할 수 있다.
CORS는 브라우저 HTTP 정책이며 native Flutter·Arduino에는 적용되지 않는다. WebSocket 연결 계약도 그대로다.

- 개발 PC에서 REST: `http://localhost:8000`, WebSocket: `ws://localhost:8000/ws`.
- Android 기본 에뮬레이터에서 개발 PC: `http://10.0.2.2:8000`, `ws://10.0.2.2:8000/ws`.
- 실제 기기·Arduino: 같은 네트워크의 **개발 PC LAN IP**와 API 포트를 사용한다. 모바일의 `localhost`는 기기 자신이다.
- API는 기기 접속을 위해 호스트 인터페이스에 공개하고, PostgreSQL은 `127.0.0.1`에만 공개한다.

## 로컬 Python으로 실행

전체 Compose 실행 대신 DB만 실행한다. 이미 Backend 컨테이너가 실행 중이면 먼저 중지해 포트 충돌을 피한다.

```bash
docker compose up -d --wait db
cd backend
python3.13 -m venv .venv
source .venv/bin/activate
python -m pip install -r requirements.txt
alembic upgrade head
uvicorn app.main:app --host 0.0.0.0 --port 8000 --reload
```

로컬 Uvicorn의 포트는 `--port`로 지정한다. Docker 없이 준비된 PostgreSQL을 쓰려면
`.env`의 DB 연결 값을 해당 서버에 맞춘 뒤 Python 실행 단계부터 진행한다.

## 구조와 다음 단계 인계

- `app/main.py`: 앱 생성, 라우터 등록, 시작·종료 시 WebSocket manager와 connection pool 관리.
- `app/config.py`: 환경변수 검증과 DB URL 조립.
- `app/db.py`: 공통 `Base`, engine, `SessionLocal`, 요청 단위 `get_db`.
- `app/models/`: Restroom, Stall, Sensor, SensorEvent, RestroomSnapshot SQLAlchemy 모델.
- `app/seed_data.py`, `app/seed.py`: 개발용 fixture와 기존 데이터를 유지하는 seed 명령.
- `app/api/health.py`: health 응답 모델과 라우터, DB 오류 처리.
- `app/api/restrooms.py`: 목록·상세·추천 라우터, 좌표·ID·비데 조건 검증, 404/503 처리.
- `app/schemas/restroom.py`: 계약의 `Restroom`, `RestroomDetail`, `Stall` 응답 모델.
- `app/schemas/recommendation.py`: 거리 필수·통계 필드를 포함하는 `Recommendation` 응답 모델.
- `app/repositories/restrooms.py`: 목록·상세 공통 SQL 집계 및 상세 Stall 조회.
- `app/services/location.py`: 미터 단위 직선거리 계산.
- `app/services/recommendation.py`: 현재 빈칸·비데 조건으로 후보를 정하고 가까운 후보 사이에서만 통계로 보정.
- `app/repositories/statistics.py`: 같은 화장실·서울 요일·1시간 구간의 과거 관측 집계 SQL.
- `app/services/statistics.py`: 두 빈칸 존재 비율·표본 수 계산과 최소 표본 수 판정, 추천 후보들의 일괄 조회.
- `app/api/sensors.py`, `app/schemas/sensor.py`: Sensor Update 라우터, strict 요청 검증, 응답 모델과 오류 처리.
- `app/repositories/sensors.py`: 센서·칸 행 잠금 조회, 화장실 존재 확인.
- `app/services/sensors.py`: 상태 비교, 동일 상태 생략, 상태·이벤트 원자적 저장과 commit.
- `app/api/websocket.py`, `app/schemas/realtime.py`: `/ws` 연결과 `stall.updated` 이벤트 모델.
- `app/realtime/manager.py`: 클라이언트별 전송 큐, 방송 순서, 연결 실패·종료 처리.
- `alembic.ini`, `alembic/`: initial migration `0001`, 통계 원본 스냅샷 테이블을 추가하는 `0002`.
- `tests/test_database.py`: 임시 PostgreSQL 스키마에서 수행하는 모델·migration·seed 통합 테스트.
- `tests/test_restroom_snapshots.py`: 관측 시각·집계·출처·중복 제약, 과거 상태 보존, 서울 요일·시간 조회 검사.
- `tests/test_statistics.py`: 비율·표본 기준·시간대·조회 기간·설정·오류와 여러 화장실의 통계 일괄 조회 검증.
- `tests/test_recommendation_statistics.py`: 통계 충분·부족·부분 누락, 거리 범위, 실시간 우선, 비데별 기준, 만석 fallback 검증.
- `tests/test_restrooms_api.py`: 임시 PostgreSQL 스키마를 사용하는 조회 API 계약 테스트.
- `tests/test_recommendation_api.py`, `tests/test_location.py`: 추천 분기·입력·응답 계약과 거리 계산 테스트.
- `tests/test_sensors_api.py`: 실제 commit·rollback·동시 요청을 검사하는 Sensor API 통합 테스트.
- `tests/test_websocket_api.py`, `tests/test_connection_manager.py`: DB→WebSocket 흐름, 순서, 다중 연결·실패 격리 검사.
- `requirements-dev.txt`: 테스트 클라이언트에 필요한 개발 의존성. 런타임 이미지에는 설치하지 않는다.
- `Dockerfile`, `docker-start.sh`, `requirements.txt`, `.env.example`: 실행 이미지, migration 후 서버 시작, 의존성, 환경변수 예제.
- `tests/test_cors.py`: 개발 origin·preflight·오류 응답·환경변수 검사.
- `.gitignore`, `.dockerignore`: 로컬 비밀번호와 가상환경, Python 캐시 제외.
- [`database/docker-compose.yml`](../database/docker-compose.yml): PostgreSQL과 Backend 실행.

FastAPI 앱 자체는 `create_all`이나 migration을 실행하지 않는다.
Docker 개발 시작 스크립트에서 Alembic을 먼저 실행하며, 로컬 Python 실행에서는 아래 명령을 직접 실행한다.
`alembic upgrade head`는 `restrooms`, `stalls`, `sensors`, `sensor_events`, `restroom_snapshots`와 Alembic 관리 테이블을 생성한다.
추후 모델을 추가할 때 공통 `Base`를 사용하고 `app/models/__init__.py`에 모델을 import한 뒤
`alembic revision --autogenerate -m "설명"`으로 생성된 변경을 검토한다.

관계, 제약조건, 이벤트 필드의 의미는 [`database/README.md`](../database/README.md)에 기록했다.
개발용 seed는 아래 명령으로 직접 실행한다. 실시간 상태·거리 기반 추천과 독립 통계 service를 제공한다.
추천은 충분히 가까운 후보 사이에서 신뢰 가능한 통계를 보조 기준으로 사용한다.
API 계약과 Flutter/IoT 영역은 변경하지 않는다. 루트 Compose와 README는 개발 실행 진입점이다.

통계 원본용 `RestroomSnapshot` 구조와 `0002` migration을 제공한다. 관측 당시 전체 칸·빈칸·빈 비데 칸,
timezone이 있는 실제 관측 시각, 테스트 데이터 여부를 필수로 저장한다. 통계 계산은 아래 service로 제공하며 자동 수집은 아직 없다.
SensorEvent만으로 충분하지 않은 이유와 후속 수집 기준은 [통계 데이터 검토](../database/README.md#통계-원본-데이터-검토와-restroomsnapshot)에 기록했다.

## 화장실 조회 API

서버 실행 및 seed 생성 후 다음 요청으로 확인한다. 상세의 ID는 목록 응답의 실제 `id`를 사용한다.

```bash
curl -i http://localhost:8000/api/restrooms
curl -i 'http://localhost:8000/api/restrooms?x=10&y=20'
curl -i http://localhost:8000/api/restrooms/1
curl -i 'http://localhost:8000/api/restrooms/1?x=10&y=20'
```

- 목록은 화장실 배열, 상세는 같은 필드에 `stalls` 배열을 추가한 객체를 반환한다. 별도 wrapper나 통계 필드는 없다.
- `total_stalls`, `available_stalls`, `available_bidet_stalls`는 공통 SQL 집계로 DB에서 계산한다. 칸이 없는 화장실은 모두 0이다.
- 상세의 집계값과 `stall_number`순 Stall 목록은 **한 SQL 문장**에서 조회하므로 같은 DB snapshot을 나타낸다.
- `x`, `y`를 모두 생략하면 `distance: null`이고 목록은 `id` 오름차순이다.
- 좌표를 함께 제공하면 미터 단위 직선거리를 계산하고 목록을 `(distance, id)` 오름차순으로 정렬한다.
- 좌표 한쪽 누락·빈 문자열·문자열 null·비숫자·NaN·무한대, 양의 정수가 아닌 ID는 기본 형식의 검증 오류 배열과 `422`를 반환한다.
- 등록된 화장실이 없으면 목록은 `200 []`, 존재하지 않는 ID의 상세는 `404 {"detail":"Restroom not found"}`다.
- DB 접근 실패는 `503 {"detail":"Database unavailable"}`이며 내부 연결 정보를 응답에 노출하지 않는다.

신규 DB migration이나 환경변수는 필요하지 않다. 정적 `/recommend` 경로는
`/{restroom_id}`보다 먼저 등록해 정수 ID 검증과 충돌하지 않도록 했다.

## 추천 API

```bash
curl -i 'http://localhost:8000/api/restrooms/recommend?x=10&y=20&bidet_required=false'
curl -i 'http://localhost:8000/api/restrooms/recommend?x=10&y=20&bidet_required=true'
```

`x`, `y`는 필수이며 같은 미터 단위 평면 좌표를 사용한다. 음수와 0을 허용한다.
누락·빈 값·문자열 null·비숫자·비유한 좌표, 해석할 수 없는 boolean은 `422`다.
`bidet_required`는 생략하면 `false`이며 Flutter는 `true`/`false` 문자열로 전송한다.

| 현재 상태 | 선택 / 응답 |
| --- | --- |
| 일반 요청, 빈칸 있음 | `available_stalls > 0`을 후보로 선정 |
| 비데 필수, 빈 비데 칸 있음 | `available_bidet_stalls > 0`을 후보로 선정 |
| 모든 화장실의 `available_stalls == 0` | 비데 설정과 관계없이 전체에서 가장 가까운 화장실 |
| 일반 빈칸은 있으나 빈 비데 칸이 없는 비데 필수 요청 | `404 {"detail":"No available bidet stalls"}` |
| 화장실 미등록 | `404 {"detail":"No restrooms found"}` |
| DB 접근 실패 | `503 {"detail":"Database unavailable"}` |

거리는 기존 `Location Service`의 `math.hypot`으로 계산하며 반올림하지 않는다.
층·계단·실제 보행 경로는 거리 계산에 포함하지 않는다.
칸이 없는 화장실은 집계값이 모두 0이며, 전체 빈칸이 없을 때의 fallback에는 포함된다.

사용 가능한 후보의 선택 순서:

1. 가장 가까운 후보의 거리 `d_min`을 구한다. 현재 만석이거나 비데 필수 조건을 충족하지 못한 화장실은 여기에 참여하지 않는다.
2. `distance - d_min <= RECOMMENDATION_DISTANCE_TOLERANCE`인 후보만 통계 비교 범위로 삼는다.
   기본값은 10m이며 경계값을 포함한다. 50m·60m·70m가 있다면 50m·60m까지만 비교하고, 60m를 기준으로 범위를 다시 넓히지 않는다.
3. 가까운 후보가 둘 이상이고 **모든 해당 후보**에 충분한 관련 통계가 있으면 높은 비율을 우선한다.
   일반 요청은 `historical_availability_rate`, 비데 필수는 `historical_bidet_availability_rate`를 사용한다.
4. 한 후보라도 관련 통계의 표본이 부족하거나 값이 없으면 가장 가까운 후보로 fallback한다.
   통계가 없는 값을 0으로 간주하거나, 통계가 있는 후보만 남겨 더 먼 곳을 선택하지 않는다.
5. 통계 비교가 동률이면 거리, ID 순이다. 통계를 사용하지 않을 때도 거리, ID 순으로 고른다.

전체 만석은 위 통계 비교를 거치지 않고 전체에서 가장 가까운 화장실을 선택한다.
통계가 충분해도 현재 사용할 수 없는 칸을 사용 가능한 후보보다 우선하지 않는다.

응답은 `Restroom`의 10개 필드에 다음 3개 필드를 더한 평평한 객체다. `stalls`나 wrapper는 없다.
추천의 `distance`는 항상 숫자이며 null이 아니다. 아래는 통계가 없는 경우의 세 필드다.

```json
{
  "statistics_used": false,
  "historical_availability_rate": null,
  "historical_bidet_availability_rate": null
}
```

- 통계로 여러 후보를 실제 비교하면 `statistics_used=true`다. 가장 가까운 후보를 그대로 선택하거나 비율이 동률이어도 비교했다면 true다.
- 단일 후보, 전체 만석, 통계 부족 fallback에서는 false다. 이때도 **선택된 화장실**의 충분한 통계는 숫자로 반환한다.
  선택된 화장실의 표본이 부족한 비율만 null이며 0.0은 유효한 값이다. 두 통계 필드는 각각 null일 수 있다.
- 추천 service는 실시간 집계 SELECT 한 번과 가까운 후보들의 통계 SELECT 한 번을 사용한다.
  모든 후보의 통계는 같은 기준 시각과 한 SQL snapshot에서 얻는다. 전체 만석에서는 선택된 한 곳의 통계만 표시용으로 조회한다.
- GET은 데이터를 쓰거나 이력을 만들어내지 않는다. 통계 조회의 DB 오류는 기존 계약의 `503`이며 표본 부족과 구분한다.
  새 의존성·migration·API 계약 변경은 없다.

Flutter는 WebSocket 이벤트를 받으면 현재 좌표와 비데 설정으로 이 API를 재요청한다.
`available_stalls == 0`인 성공 응답에는 만석 안내를 표시하고, 비데 조건의 `404`에서는 조건을 임의로 해제하지 않는다.
추천은 요청 시점의 상태를 반영하며 예약이나 도착 시 빈칸을 보장하지 않는다.
Flutter는 비율의 존재만으로 통계 추천이라고 표시하지 않고 `statistics_used`를 기준으로 설명한다.

## 통계 service

`app.services.statistics.get_restroom_statistics(db, restroom_id)`는 `RestroomStatistics`를 반환한다.
`get_restrooms_statistics(db, restroom_ids)`는 같은 기준 시각으로 일괄 조회한 `{restroom_id: RestroomStatistics}`를 반환한다.
추천은 이 일괄 조회를 사용한다. 별도 통계 HTTP endpoint는 추가하지 않았다.

| 반환값 | 의미 |
| --- | --- |
| `historical_availability_rate` | 유효 표본 중 `available_stalls > 0`인 비율 |
| `historical_bidet_availability_rate` | 유효 표본 중 `available_bidet_stalls > 0`인 비율 |
| `sample_count` | 해당 화장실·요일·시간·조회 기간·출처 조건을 만족한 스냅샷 수 |
| `is_usable` (property) | 최소 표본 수를 충족하여 두 비율을 사용할 수 있는지 여부 |

- 서버 현재 시각을 `Asia/Seoul`로 변환하여 **같은 요일·같은 1시간 구간**을 고른다.
  예를 들어 서울 월요일 12:35에는 월요일 `[12:00, 13:00)`의 관측을 사용한다.
- 기간은 `[현재 시각 - STAT_LOOKBACK_DAYS, 현재 시각)`이다. 시작은 포함하고 현재 순간·미래는 제외한다.
  현재 시간대에서 이미 지나간 시각의 관측도 조건에 맞으면 포함된다. 다른 timezone으로 표현한 같은 현재 시각은 같은 결과다.
- `is_test_data=true`, 다른 화장실·요일·시간대, 조회 기간 밖의 스냅샷은 표본 수에도 포함하지 않는다.
- `sample_count < MIN_STAT_SAMPLE_COUNT`이면 실제 표본 수는 유지하고 두 비율은 `None`, `is_usable=False`다.
  경계값과 같으면 사용 가능하다. 충분히 관측된 `0.0`과 `1.0`은 유효하며, 없는 관측을 0으로 채우지 않는다.
- 빈칸 **존재 여부**를 센다. 빈칸 개수의 평균·전체 칸 대비 사용률·SensorEvent의 잠금 해제 비율은 사용하지 않는다.
  두 분자와 공통 분모를 하나의 SELECT에서 얻고 DB에 결과를 저장하거나 캐시하지 않는다.
  일괄 조회는 ID를 중복 제거하고 요청한 모든 ID의 결과를 반환한다. 관측이 없는 ID는 표본 0이며, 빈 ID 목록은 SQL 없이 빈 dict를 반환한다.
- `now=`는 내부 테스트·재현용 timezone-aware datetime이며 클라이언트 입력이 아니다. 생략하면 서버 시각을 사용한다.
  잘못된 ID·timezone 없는 시각은 `ValueError`, DB 실패는 원래 SQLAlchemy 예외를 전달한다.
  없는 화장실이나 관측이 없는 화장실은 표본 0·비율 `None`이며, DB 오류를 데이터 부족으로 숨기지 않는다.

입력은 같은 주기로 수집된 유효한 관측이라는 전제다. `is_usable`은 최소 표본 수 판정이며 센서 신선도 보증은 아니다.
정기 수집·센서 관측 품질 판단은 후속 단계다. 실제 데이터 생성 전에 `database/README.md`의 수집 기준을 적용해야 한다.

로컬 조회 예시(개발 DB에 스냅샷이 없으면 0 / None / False):

```bash
cd backend
.venv/bin/python - <<'PY'
from dataclasses import asdict
from app.db import SessionLocal, engine
from app.services.statistics import get_restroom_statistics

try:
    with SessionLocal() as db:
        result = get_restroom_statistics(db, restroom_id=1)
        print({**asdict(result), "is_usable": result.is_usable})
finally:
    engine.dispose()
PY
```

테스트는 별도 임시 PostgreSQL 스키마에 과거 데이터를 만들고 종료 시 전부 롤백한다.
실사용 필터 검사를 위해 그 스키마 안에서만 `is_test_data=false`인 합성 관측을 사용한다.
개발 DB에 가짜 관측을 넣거나 테스트 표시를 실사용으로 바꾸지 않는다.

```bash
cd backend
.venv/bin/python -W error -m unittest discover -s tests -p test_statistics.py -v
```

검증 예시: 같은 시간대의 네 표본에서 빈칸 수가 `[0, 1, 5, 0]`, 빈 비데 칸이 `[0, 0, 1, 0]`이면
`sample_count=4`, 두 비율은 각각 `0.5`, `0.25`다. 최소 표본 수가 5 이상이면 두 비율은 `None`이다.

## Sensor Update API

Arduino UNO R4 WiFi는 등록된 `device_id`와 안정화된 JSON boolean 상태를 보낸다.
비밀번호·인증 헤더 등 추가 필드는 현재 계약에서 요구하지 않는다.

```bash
curl -i -X POST http://localhost:8000/api/sensors/stall \
  -H 'Content-Type: application/json' \
  -d '{"device_id":"stall-a-01","occupied":true}'
```

성공은 `200 {"success":true,"changed":true}`이며, 같은 상태를 재전송하면
`200 {"success":true,"changed":false}`다. 다음 순서로 처리한다.

1. `device_id`는 공백만 있는 값이나 빈 문자열을 거부하고, 대소문자·앞뒤 공백을 바꾸지 않고 정확히 조회한다.
   `occupied`는 JSON `true`/`false`만 허용하며 숫자나 문자열 boolean은 `422`다.
2. 한 트랜잭션에서 센서 행을 잠근 뒤 존재 여부와 활성 상태를 확인한다.
3. 연결된 칸 행을 `FOR UPDATE`로 잠그고 화장실 존재·소속 일치를 확인한다.
   서로 다른 센서가 같은 칸을 갱신하더라도 칸 잠금을 기준으로 순차 처리한다.
4. 상태가 같으면 Stall UPDATE와 SensorEvent INSERT를 모두 생략하며 `updated_at`도 유지한다.
5. 상태가 바뀌면 `occupied`와 `updated_at`을 갱신하고 `occupancy_changed` 이벤트를 같은 트랜잭션에 저장한다.
   이벤트 `value`는 변경 후 상태다. 잠금 획득 뒤 DB의 `clock_timestamp()`를 읽어 Stall과 이벤트에 같은 처리 시각을 기록한다.
6. 같은 트랜잭션에서 변경 후 집계값을 읽어 이벤트를 준비한다. commit 성공 뒤에만 WebSocket 큐에 넣고 성공 응답을 반환한다.
   저장 또는 commit 실패는 rollback하며 `503`으로 응답하고 방송하지 않는다. commit 후 방송 실패는 이미 저장된 결과와 성공 응답을 바꾸지 않는다.

| 오류 | 응답 |
| --- | --- |
| 등록되지 않은 기기 | `404 {"detail":"Sensor not found"}` |
| 비활성 센서 | `409 {"detail":"Sensor is inactive"}` |
| 연결된 칸·화장실 없음 또는 소속 불일치 | `409 {"detail":"Sensor mapping is invalid"}` |
| 누락·null·잘못된 타입·빈 ID·잘못된 JSON | `422`, FastAPI 기본 검증 오류 배열 |
| DB 연결·저장 실패 | `503 {"detail":"Database unavailable"}` |

현 DB 제약조건은 연결 누락·소속 불일치를 막지만 API도 방어적으로 검사한다. 모델과 migration은 변경하지 않았다.
서비스 `update_stall_occupancy`는 시작된 트랜잭션이 없는 새 Session을 받아 트랜잭션을 직접 관리한다.
반환값은 commit된 변경의 `StallUpdated` 이벤트이며, 상태가 같으면 `None`이다.
Sensor 라우터는 manager의 프로세스 내 잠금으로 트랜잭션과 방송 큐 등록을 순차 처리한다.
DB 작업은 thread pool에서 실행하여 WebSocket 전송과 다른 비동기 요청을 막지 않는다.

초기 상태가 false인 개발용 seed 기기에 아래 요청을 순서대로 보내면
`changed`는 `false → true → false → true`이며 이벤트는 총 2건 추가된다.
이 명령은 **개발용 HTTP 시뮬레이션**이고 실제 센서 관측 통계로 취급하지 않는다.

```bash
for occupied in false true true false; do
  curl --fail-with-body -sS -X POST http://localhost:8000/api/sensors/stall \
    -H 'Content-Type: application/json' \
    -d "{\"device_id\":\"stall-a-01\",\"occupied\":$occupied}"
  echo
done
```

IoT는 같은 기기의 요청을 겹쳐 보내지 않고, 응답을 못 받으면 현재 안정화된 상태를 재전송한다.
네트워크 단절은 DB 미반영을 뜻하지 않으며, 오래된 요청의 임의 재생까지 방지하는 API는 아니다.

## WebSocket 실시간 업데이트

`ws://localhost:8000/ws`에 연결하면 이후 모든 화장실의 변경을 받는다.
인증 헤더·구독 메시지·application ping은 필요하지 않다. 클라이언트가 보내는 메시지는 무시한다.
이벤트는 UTF-8 JSON text frame이며 계약대로 다음 **7개 필드**를 포함한다.

```json
{
  "type": "stall.updated",
  "restroom_id": 1,
  "stall_id": 1,
  "occupied": true,
  "total_stalls": 3,
  "available_stalls": 1,
  "available_bidet_stalls": 0
}
```

- 실제 상태 변경이 commit된 경우에만 방송한다. `changed=false`, 검증 오류, DB 실패는 방송하지 않는다.
- 같은 화장실의 이벤트와 집계값은 commit 순서로 전송한다. 집계는 기존 조회 API의 공통 SQL을 사용한다.
- 클라이언트마다 64개 이벤트 큐와 독립 sender task를 둔다. 전송은 최대 2초 대기하며 실패·지연·큐 초과 시 해당 연결만 `1011`로 종료한다.
  다른 클라이언트 전송과 Sensor HTTP 응답은 해당 소켓을 기다리지 않는다. 정상 정리는 `1000`이다.
- 최초 연결에 snapshot을 보내거나 단절 중 이벤트를 재전송하지 않는다. Flutter는 연결·재연결 후 REST로 동기화한다.
  목록의 세 집계값과 상세의 `occupied`를 이벤트 값으로 대입하며, 재동기화 규칙은 `docs/api.md`를 따른다.
- 현재 manager는 메모리에 있으므로 **Backend 프로세스 1개, worker 1개**로 실행한다(제공된 Compose 기본값).
  여러 worker/replica로 확장하려면 공유 메시지 전달과 순서 제어를 먼저 구현해야 한다.

수신 확인은 로컬 의존성을 설치한 뒤 아래 명령으로 실행한다. 다른 터미널에서 위 Sensor POST를 보내면 이벤트가 출력된다.
두 터미널에서 수신기를 실행하면 동시 방송을 확인할 수 있다. `Ctrl+C`로 종료한다.

```bash
cd backend
.venv/bin/python - <<'PY'
from websockets.sync.client import connect

with connect("ws://localhost:8000/ws") as websocket:
    for message in websocket:
        print(message, flush=True)
PY
```

## 개발용 seed 실행

환경변수와 PostgreSQL을 준비한 뒤 실행한다. 개발용 초기 상태이며 실제 센서 관측이나 과거 통계 데이터가 아니다.
앱 시작이나 migration 과정에서 자동 실행되지 않는다.

로컬 Python (저장소 루트에서):

```bash
cd backend
.venv/bin/alembic upgrade head
.venv/bin/python -m app.seed
```

Docker (저장소 루트에서):

```bash
docker compose up -d --build --wait backend
docker compose exec backend python -m app.seed
```

최초 실행 시 화장실 3개, Stall 12개, Sensor 12개를 추가한다. 재실행 시 빠진 레코드만 추가한다.
기존 `occupied`, `has_bidet`, `updated_at`, 센서 활성 상태, 위치 등은 덮어쓰지 않는다.
기존 이벤트도 보존하며 새로운 `SensorEvent`나 가짜 통계를 만들지 않는다.

화장실은 `(name, building, floor)`, 칸은 `(restroom_id, stall_number)`, 센서는 `device_id`로 찾는다.
화장실 식별값이 중복되어 모호하거나 같은 device_id가 다른 칸에 연결되어 있으면 오류로 종료하고
이번 실행 전체를 롤백한다. 동일 seed의 동시 실행은 PostgreSQL transaction advisory lock으로 순차 처리한다.
다른 작업자가 식별값을 바꾸거나 데이터를 충돌되게 등록한 경우에는 seed가 임의로 병합·재연결하지 않는다.

생성되는 이름·좌표·device_id·칸별 상태는 [`database/README.md`](../database/README.md#개발용-seed-데이터)에 있다.

## Database 및 API 통합 테스트

설정된 PostgreSQL에 접속하여 임시 스키마를 만든 뒤 migration과 데이터 제약조건을 검사한다.
모델·조회 테스트는 트랜잭션 종료 시 롤백한다. Sensor/WebSocket API 테스트는 독립된 임시 스키마에서 실제 commit과
여러 연결의 동시 요청을 검사한 뒤 해당 테스트 스키마만 삭제한다. 기존 업무 테이블과 데이터는 변경하지 않는다.
테스트 DB 사용자에게 스키마 생성 권한이 필요하다. Compose의 개발용 사용자는 이 권한을 가진다.

```bash
cd backend
.venv/bin/python -m pip install -r requirements-dev.txt
.venv/bin/python -W error -m unittest discover -s tests -v
```

## 기본 실행 환경 검증 기록 (모델 추가 전, 2026-10-24)

- Python 3.13 가상환경에서 의존성 설치 및 `pip check` 통과.
- Docker 이미지 빌드 및 Compose의 Backend/PostgreSQL healthcheck 통과.
- 로컬 SQLAlchemy 세션으로 PostgreSQL 17.11에 TCP 접속하여 `SELECT 1` 성공.
- 실제 HTTP 요청으로 정상 시 `200 {"status":"ok"}`, DB 중단 시
  `503 {"detail":"Database unavailable"}`, DB 복구 후 Backend 재시작 없이 `200` 확인.
- OpenAPI의 업무 경로가 `/api/health` 하나인지 확인.
- 로컬 Alembic `upgrade head`, `current`, `check`, offline SQL 생성 및 컨테이너의 `upgrade head` 통과.
- 당시 DB 테이블은 `alembic_version`만 존재하고, 업무 모델 metadata는 비어 있었음.
- 빈 비밀번호 설정 거부 및 `.env`/가상환경의 Git 제외 확인. 발견된 실행 오류 없음.

## 모델·initial migration 검증 기록 (2026-10-24)

- PostgreSQL 임시 스키마 통합 테스트 8개 통과. 테스트 suite는 연결 정리 경고 수정 전후 총 2회 실행했다.
- migration 적용 → 되돌리기 → 재적용, ORM 관계, 기본값·시간대, 중복 device_id·칸 번호 거부,
  외래키·소속 화장실 일치, 잘못된 값 거부, 이력 참조 삭제 방지, updated_at 갱신을 확인했다.
- Docker Backend를 다시 빌드하고 개발 DB에 `alembic upgrade head` 적용 완료.
- `alembic current`: `0001 (head)`. `alembic check`: 추가 변경 없음.
- 모델 구현 당시 개발 DB에는 네 업무 테이블과 `alembic_version`만 생성했으며, seed/test 데이터는 넣지 않았다.
- 기존 `/api/health`는 `200 {"status":"ok"}`. OpenAPI의 업무 경로도 여전히 `/api/health` 하나다.
- 남아 있는 실행 오류나 경고 없음.

## Seed 검증 기록 (2026-10-24)

- `app/seed_data.py`, `app/seed.py` 추가. 기존 모델·migration·API는 변경하지 않았다.
- `tests/test_database.py`에 seed 관련 테스트 4개를 추가하고 전체 12개 테스트가 한 번에 통과했다.
  반복 실행 시 변경된 상태·ID·timestamp·기존 이벤트 보존, 부분 데이터 보충, 매핑 충돌과 모호한 화장실의 전체 롤백을 검증했다.
- Docker seed 실행으로 개발 DB에 화장실 3개, Stall 12개, Sensor 12개를 생성했다.
- 로컬 명령으로 다시 실행한 결과 신규 생성은 모두 0개이며, 실행 전후 모든 행의 값이 동일했다.
- 각 칸에 고유한 센서 하나가 연결되어 있고 `SensorEvent`는 0개다. 임시 테스트 스키마는 남아 있지 않다.
- 기존 health API 정상, OpenAPI 경로 추가 없음. 발견된 실행 오류 없음.

## 화장실 조회 API 검증 기록 (2026-10-24)

- API 계약 테스트 9개를 추가했고 기존 DB·seed 테스트를 포함한 21개 테스트가 통과했다. 회귀 suite는 총 3회 실행했다.
- 빈 목록, 칸 없는 화장실, 만석, 여러 센서 연결 시 집계, 좌표 쌍·유한성·ID 검증,
  거리 정렬·동률 정렬, 404/503 응답, 정확한 필드·null 처리, 상세 단일 SQL 조회를 검사했다.
- 테스트 중 발견한 클라이언트 의존성 호환성, 큰 ID의 정수 범위 초과, 테스트 connection pool 정리 문제를 수정했다.
- Docker Backend를 다시 빌드하고 seed 데이터로 `/api/restrooms` 및 `/api/restrooms/1`, `/2`, `/3`을 실제 호출하여 모두 `200`을 확인했다.
- 전체 칸 / 빈칸 / 빈 비데 칸은 본관 1층 `3 / 2 / 1`, 본관 2층 `5 / 3 / 2`, 체육관 `4 / 2 / 1`이며 상세의 Stall 목록과 일치했다.
- 실제 HTTP로 거리·정렬, 없는 ID `404`, 누락·비유한 좌표 `422`, 기존 health 정상도 확인했다. DB 장애 `503`은 테스트에서 DB 예외를 주입해 확인했다.
- seed 데이터는 그대로 유지되며 임시 테스트 스키마는 남아 있지 않다. 남아 있는 실행 오류 없음.

## Sensor Update API 검증 기록 (2026-10-24)

- Sensor 라우터·요청/응답 스키마·잠금 조회 repository·트랜잭션 service와 통합 테스트를 추가했다.
  `app/main.py`에 라우터를 등록하고 기존 조회 테스트의 OpenAPI 경로 기대값을 갱신했다.
- 신규 Sensor API 테스트 12개를 포함한 전체 33개 테스트가 한 번에 통과했다.
  미등록·inactive·연결 누락·소속 불일치·잘못된 payload·DB 장애를 검증했다.
- 실제 독립 DB 연결에서 상태·이벤트 commit을 확인했다. 이벤트 INSERT 실패 및 commit 전 실패를 주입하여
  이미 실행된 Stall UPDATE까지 롤백되는 것을 검증했다.
- 서로 다른 센서 두 개가 같은 칸을 동시에 true로 바꿀 때 하나만 `changed=true`이고 이벤트는 1건 생성됐다.
- Docker Backend를 갱신하고 개발용 `stall-a-01`에 실제 HTTP로 아래 순서를 전송했다.

| 요청 occupied | HTTP | changed | 이번 검증에서 추가된 누적 이벤트 |
| --- | --- | --- | --- |
| false | 200 | false | 0 |
| true | 200 | true | 1 |
| true | 200 | false | 1 |
| false | 200 | true | 2 |

- 반복 요청의 `updated_at`이 유지되고 상세 조회에도 각 상태가 반영되는 것을 확인했다.
- 개발 DB에는 이번 HTTP 시뮬레이션의 `occupancy_changed` 이벤트 2건(`true`, `false`)을 남겼다.
  최종 Stall 상태는 false다. 실제 Arduino 관측이 아닌 개발 테스트 이력이다.
- 실제 HTTP의 미등록 기기 `404`와 문자열 boolean `422`도 상태·이벤트를 변경하지 않았다.
- 임시 테스트 스키마는 모두 정리했다. 모델·migration·공통 API 계약 변경, WebSocket 추가는 없으며 남은 실행 오류는 없다.

## WebSocket 검증 및 인계 기록 (2026-10-24)

- 신규 파일: `app/api/websocket.py`, `app/schemas/realtime.py`, `app/realtime/__init__.py`,
  `app/realtime/manager.py`, `tests/test_websocket_api.py`, `tests/test_connection_manager.py`.
- 수정 파일: `app/main.py`, `app/api/sensors.py`, `app/services/sensors.py`, `app/repositories/restrooms.py`,
  `requirements.txt`, `tests/test_sensors_api.py`, 이 README와 `database/README.md`.
  Uvicorn의 실제 WebSocket 지원을 위해 `websockets==17.3`을 추가했다.
- 신규 테스트 10개를 포함한 전체 43개 테스트가 통과했다. 회귀 suite는 총 1회 실행했다.
  다중 연결, 순차 전송, 클라이언트 전송 실패·지연·큐 초과, 정상 정리,
  중복 요청 방송 생략, commit 실패 시 방송 생략, commit 후 방송 실패 시 성공 유지,
  같은 화장실의 동시 변경과 집계 순서를 검증했다.
- Docker 이미지를 다시 빌드하고 두 실제 WebSocket 클라이언트의 `101` 연결을 확인했다.
  Sensor HTTP 요청 → PostgreSQL 상태·SensorEvent commit → 두 클라이언트의 동일한 7필드 이벤트 수신을 확인했다.
  한 클라이언트를 종료한 뒤 남은 연결의 수신, 최초 연결·재연결의 snapshot/replay 없음도 확인했다.
- `stall-a-01`에 `false → true → true → false`를 요청하여 실제 변경 두 번만 방송되는 것을 확인했다.
  개발 DB에 시뮬레이션 이벤트 2건을 추가했다(해당 센서 누적 4건). 최종 `occupied=false`이며
  본관 1층 집계는 전체 3 / 빈칸 2 / 빈 비데 칸 1이다. 실제 센서 관측 통계로 취급하지 않는다.
- `pip check` 통과, 임시 테스트 스키마 잔여 없음, Backend·PostgreSQL healthcheck 정상.
  남은 실행 오류는 없다. DB 모델·migration·공통 계약·Flutter·IoT 파일은 변경하지 않았다.
- Flutter는 기존 계약의 7필드를 적용하고 재연결 시 REST로 동기화한다.
  현재 운영 범위는 Backend 프로세스 1개/worker 1개다. 추천·통계는 아직 구현하지 않았다.

## 기본 추천 검증 및 인계 기록 (2026-10-24)

- 신규 파일: `app/services/recommendation.py`, `app/schemas/recommendation.py`,
  `tests/test_recommendation_api.py`, `tests/test_location.py`.
- 수정 파일: `app/api/restrooms.py`, `tests/test_restrooms_api.py`, `tests/test_websocket_api.py`, 이 README.
  기존 `app/services/location.py`와 공통 빈칸 집계 repository를 재사용했다.
- `GET /api/restrooms/recommend`를 상세 경로보다 먼저 등록했다. 빈칸·비데 조건으로 후보를 고른 뒤
  반올림하지 않은 거리와 ID 순으로 한 곳을 반환한다. 모든 성공 응답의 `statistics_used=false`, 두 통계 비율은 `null`이다.
- 신규 검증 17개를 포함한 전체 60개 테스트가 통과했다. 회귀 suite는 총 2회 실행했다.
  첫 실행에서 큰 거리의 부동소수점 값에 대한 테스트의 완전 일치 비교를 상대 오차 비교로 수정했다.
  거리 계산 로직을 바꿀 필요는 없었으며 남은 실패는 없다.
- 실제 PostgreSQL 임시 스키마에서 가까운 만석 제외·더 먼 빈칸 선택, 비데 필수, 전체 만석,
  단일 화장실, 화장실 없음, 빈 비데 후보 없음, 칸 없는 화장실, 거리 동률, 좌표 이동·입력 오류,
  정확한 응답 필드·null·DB 장애 처리를 검증했다. 추천은 집계 SELECT 한 번만 실행하고 이력 조회·쓰기 없이 동작한다.
- 독립 DB 세션으로 commit하는 Sensor API 테스트에서 마지막 빈칸의 사용 시작 → WebSocket 수신 →
  추천 재요청 시 다른 화장실 선택, 사용 종료 후 원래 화장실 재선택을 확인했다.
- Docker Backend를 다시 빌드했다. 세 seed 화장실 좌표에서 기본·일반·비데 요청 모두 `200`,
  음수 사용자 좌표에서 실제 직선거리 `50m`, 잘못된 입력 `422`, 기존 health·상세·OpenAPI 정상을 확인했다.
  개발 DB의 모든 행과 기존 SensorEvent 4건은 그대로 유지했고 임시 스키마는 남아 있지 않다.
- Flutter는 `x`, `y`를 필수로 보내고 WebSocket 수신 후 추천을 재요청한다.
  빈 비데가 없지만 일반 빈칸은 있는 상황의 `404`와 전체 만석의 `200`을 구분한다.
- 추가 의존성·환경변수·migration·공통 계약 변경은 없다. 과거 통계와 통계 기반 추천 보정은 다음 단계이며,
  현재 기본 추천에 남아 있는 실행 오류는 없다.

## 통계 데이터 구조 검증 및 인계 기록 (2026-10-24)

- 기존 SensorEvent는 초기 상태·당시 비데 구성·관측 가능 기간의 이력을 충분히 보존하지 않아,
  빈칸 존재 비율의 단독 원본으로 사용하지 않기로 했다. 단순 잠금 해제 이벤트 수 비율은 구현하지 않았다.
  상세 근거와 후속 수집 기준은 `database/README.md`에 기록했다.
- 신규 파일: `app/models/restroom_snapshot.py`, `alembic/versions/0002_restroom_snapshots.py`,
  `tests/test_restroom_snapshots.py`.
- 수정 파일: `app/models/__init__.py`, `app/models/restroom.py`, `tests/test_database.py`,
  이 README와 `database/README.md`. 새 의존성·환경변수·API 계약 변경은 없다.
- 화장실별 당시 전체 칸·빈칸·빈 비데 칸, 실제 관측 시각, 테스트 데이터 여부를 저장한다.
  유효 범위, FK, 동일 화장실·시각 중복 방지, timezone 처리를 구현했다.
- 신규 테스트 10개를 포함한 전체 70개 테스트가 통과했다. 회귀 suite는 총 1회 실행했다.
  임시 PostgreSQL 스키마에서 migration 왕복·기존 데이터 보존·ORM metadata 일치,
  집계·필수 필드·중복·삭제 제약, UTC/서울 요일·시간대 조회, 이후 칸·비데 변경과 과거 집계의 독립성을 검증했다.
  스냅샷이 있어도 추천 결과와 `statistics_used=false`, 두 통계 비율 `null`이 유지되는 것을 확인했다.
- Docker 이미지를 갱신하고 개발 DB에 `0002` migration을 적용했다. `alembic current`는 `0002 (head)`,
  `alembic check`는 추가 변경 없음이다. `/api/health`와 일반·비데 추천 API도 정상이다.
- 기존 4개 테이블의 모든 행을 적용 전후 hash로 비교해 동일함을 확인했다.
  화장실 3개·칸 12개·센서 12개·개발 이벤트 4건을 보존했으며 스냅샷은 0건이다. 임시 테스트 스키마도 남아 있지 않다.
- 추천·거리·Sensor 처리 service와 API route·응답 모델·앱 시작 파일도 적용 전후 hash가 동일하다.
  Flutter/IoT 작업이나 호출 계약 변경은 필요하지 않다.
- 이번 단계는 데이터 구조만 제공한다. 정기 수집, 센서 신선도·관측 범위 판단, 통계 계산·추천 연결은 후속 단계다.
  수집 전 간격·조회 기간·최소 표본 수를 정하고 개발·데모 관측은 `is_test_data=true`로 명시한다.
  남은 실행 오류는 없다.

## 통계 계산 검증 및 인계 기록 (2026-10-24)

- 신규 파일: `app/services/statistics.py`, `app/repositories/statistics.py`, `tests/test_statistics.py`.
- 수정 파일: `app/config.py`, `.env.example`, `database/docker-compose.yml`, 이 README와 `database/README.md`.
  새로운 의존성·migration·API 경로·응답 필드는 추가하지 않았다.
- 서울 기준 같은 요일·1시간 구간, 최근 56일의 실사용 스냅샷으로 일반·비데 빈칸 존재 비율과 표본 수를 계산한다.
  최소 표본 수는 `MIN_STAT_SAMPLE_COUNT=30`, 조회 기간은 `STAT_LOOKBACK_DAYS=56`이 기본값이다.
  부족하면 두 비율은 `None`, `is_usable=False`이고 표본 수는 그대로 반환한다.
- 신규 테스트 15개를 포함한 전체 85개 테스트가 통과했다. 회귀 suite는 총 1회 실행했다.
  별도 PostgreSQL 스키마의 과거 표본 4개에서 일반 `0.5`, 비데 `0.25`, 표본 수 `4`를 확인했다.
  최소 표본 4개에서는 사용 가능하고 5개에서는 비율이 `None`이 된다.
- 0/1 비율·비데가 없는 표본·빈 데이터, 화장실/테스트 데이터 필터, UTC/서울 요일 전환,
  시간·조회 기간 경계, 미래 제외, 서버 기본 시각, 설정 변경·입력 검증·DB 오류 전파,
  단일 SELECT·쓰기 없음·캐시 없음, 통계가 충분해도 추천은 그대로인 것을 검증했다.
- Docker Backend를 다시 빌드하고 설정 전달과 service 호출을 확인했다.
  현재 개발 DB는 스냅샷 0개로 두 비율 `None`, 표본 수 `0`, `is_usable=False`를 반환한다.
  일반·비데 추천 API는 모두 기존 `statistics_used=false`와 두 비율 `null`을 유지한다.
- 기존 다섯 테이블의 모든 행과 추천/Sensor 처리·API·응답 모델·앱 시작·스냅샷 모델 파일을 hash로 비교해 동일함을 확인했다.
  DB revision은 `0002`, 개발 이벤트는 4개, 스냅샷은 0개이며 임시 테스트 스키마는 남아 있지 않다.
- 호출은 위 통계 service 예시를 사용한다. 새 환경변수는 필요에 맞게 `backend/.env`에 설정하고 Backend를 재시작한다.
  `is_usable`은 정기 수집된 유효 관측에 대한 최소 표본 수 판정이다. 자동 수집·센서 신선도 판단과 추천 연결은 후속 단계다.
  남은 실행 오류는 없다.

## 통계 기반 추천 검증 및 인계 기록 (2026-10-24)

- 신규 파일: `tests/test_recommendation_statistics.py`.
- 수정 파일: `app/services/recommendation.py`, `app/services/statistics.py`, `app/repositories/statistics.py`,
  `app/config.py`, `.env.example`, `database/docker-compose.yml`,
  `tests/test_recommendation_api.py`, `tests/test_restroom_snapshots.py`, `tests/test_statistics.py`,
  `tests/test_websocket_api.py`, 이 README와 `database/README.md`.
- 실시간 빈칸·비데 조건을 먼저 적용하고, 가장 가까운 후보와 거리 차이가 기본 10m 이내인 후보만 통계로 비교한다.
  `RECOMMENDATION_DISTANCE_TOLERANCE`를 환경변수로 조정할 수 있다.
  가까운 후보 중 하나라도 관련 통계가 부족하면 거리 기반 선택을 유지한다. 전체 만석도 최단 거리로 선택한다.
- 두 비율은 최종 추천된 화장실의 값이다. `statistics_used`는 후보 비교에 실제 통계를 썼을 때만 true다.
  단일 후보·만석·fallback에서는 false여도 조회 가능한 통계를 반환한다. API 경로·필드 계약은 그대로다.
- 통계 service를 일괄 조회로 확장했다. 후보들의 통계는 한 기준 시각·한 SELECT로 읽는다.
  기존 단일 화장실 조회도 같은 계산을 사용하며, 성공한 추천은 실시간 집계와 통계 조회 총 두 SELECT를 수행한다.
- 신규 검증 19개를 포함한 전체 104개 테스트가 통과했다. 회귀 suite는 총 1회 실행했다.
  충분·부족·부분 누락, 50m/60m 후보 비교, 거리 범위의 경계·0·확장 방지, 비데별 통계,
  현재 만석 제외, 전체 만석 fallback, 통계 동률, nullable 비율, 테스트 관측 제외, DB 오류를 확인했다.
- 실제 commit을 수행하는 Sensor/WebSocket 통합 테스트에서 통계로 선택된 화장실의 마지막 빈칸 사용 시작 →
  DB·WebSocket 갱신 → 해당 화장실 추천 제외 → 사용 종료 후 다시 통계 비교로 선택되는 것을 확인했다.
- Docker Backend를 다시 빌드하고 기본 허용 거리 10m와 통계 일괄 조회를 확인했다.
  실제 HTTP 일반·비데 요청에서 같은 거리의 후보 두 곳에 통계가 없을 때 ID 순 fallback과 false/null 응답을 확인했다.
- 개발 DB의 다섯 테이블 모든 행은 변경 전후 hash가 같다. 스냅샷 0개·개발 이벤트 4개를 보존했고 임시 스키마는 남아 있지 않다.
  API route·응답 모델·Sensor 처리·거리 계산·앱 시작·스냅샷 모델도 변경하지 않았다.
- 추가 의존성·migration은 없고 DB revision은 `0002`다. 실행·설정·호출법은 위 추천 API 절차를 사용한다.
  Flutter는 기존 세 통계 필드를 그대로 읽고 `statistics_used`를 설명 기준으로 사용한다.
  자동 스냅샷 수집·센서 신선도 판단은 후속 단계다. 남은 실행 오류는 없다.

## Docker 실행환경 검증 및 인계 기록 (2026-10-24)

- 구현: 루트 `docker compose up`, DB healthcheck 대기 후 자동 migration·단일 Uvicorn 시작,
  환경변수 기반 개발 CORS, migration·seed·종료·기기 접속 절차 정리.
- 추가 파일: 루트 `docker-compose.yml`, `backend/docker-start.sh`, `backend/tests/test_cors.py`.
- 수정 파일: 루트 `README.md`, `backend/Dockerfile`, `backend/app/config.py`, `backend/app/main.py`,
  `backend/.env.example`, `backend/README.md`, `database/docker-compose.yml`, `database/README.md`.
- 실행: `backend/.env` 준비 후 루트에서 `docker compose up`.
  별도 터미널에서 `docker compose exec backend python -m app.seed`로 개발 데이터 생성.
  기존 `.env`와 `catchy-toilet_postgres_data` 볼륨을 그대로 사용한다.
- 테스트: CORS 5개를 포함한 전체 **109개 통과**, 회귀 suite는 **1회** 실행.
  `docker compose config`, Docker 빌드·두 서비스 healthcheck, Alembic `0002 (head)`와 metadata 일치 확인.
- 빈 DB 검증: 별도 임시 checkout·Compose project·빈 볼륨에서 실제 `docker compose up`으로
  최초 빌드와 자동 migration을 확인했다. seed 전 목록은 `[]`, seed 후 화장실 3개·Stall 12개·Sensor 12개다.
  두 번째 seed에서 모든 행이 동일하고 이벤트·스냅샷은 0개다.
- 종료·재실행 검증: 임시 프로젝트에서 `down` → `up` 후 모든 행이 보존되었다.
  DB 접속이 실패하는 별도 실행은 migration 단계에서 종료되어 Uvicorn이 시작되지 않았다.
  컨테이너는 non-root이며 이미지에 `.env`가 없다. 임시 프로젝트·볼륨·자격증명은 정리했다.
- 실제 HTTP `/api/health`, `/docs`, `/openapi.json`, 목록·추천은 모두 200이다.
  Chrome에서도 Swagger UI와 다섯 REST 작업이 정상 표시되었다.
  기본 origin 및 `.env`로 변경한 origin의 JSON POST preflight를 확인했고 미허용 origin은 400이다.
- 인계: 새 환경변수는 `CORS_ALLOWED_ORIGINS`다. origin을 바꾸면 `docker compose up -d --wait backend`로 반영한다.
  소스·migration 변경 후에는 `--build`를 사용한다. 루트 include는 Compose 2.20.3 이상이 필요하다.
  WebSocket manager가 메모리를 사용하므로 Backend worker/replica는 하나로 유지한다.
- 데이터 보존: 기존 개발 DB의 화장실 3개·Stall 12개·Sensor 12개·개발 이벤트 4개·스냅샷 0개의
  모든 행을 실행 전후 비교해 동일함을 확인했다. API 계약·모델·migration·의존성·Flutter/IoT 파일 변경은 없다.
- 남은 사항: 이번 실행환경 정리 범위의 미완료 작업·실행 오류는 없다.
  기존 통계 스냅샷 자동 수집과 실제 하드웨어·Flutter 연결 검증은 별도 후속 작업이다.

## 최종 Backend 통합 점검 (2026-10-24)

Flutter 담당자 전달 정보는 [FLUTTER_HANDOFF.md](FLUTTER_HANDOFF.md)에 모았다.

- 새 기능·architecture 변경 없음. Health OpenAPI에서 `status`가 선택 필드로 표시되던 부분을
  기존 계약의 필수 필드에 맞췄다. 실제 JSON 응답과 상태 코드는 동일하다.
- 수정: `app/api/health.py`, `tests/test_restrooms_api.py`, `tests/test_websocket_api.py`, 이 README.
  추가: `FLUTTER_HANDOFF.md`. 루트·API 계약·Flutter·DB 모델·migration·의존성 변경 없음.
- 기존 WebSocket 통합 테스트를 보강하여 변경된 Stall과 SensorEvent를 별도 DB 세션에서 확인한 뒤
  목록·상세·일반 추천·비데 추천 결과를 함께 검증한다. 필수/nullable 응답 필드도 계약과 비교한다.
- 전체 109개 테스트 통과. 회귀 suite는 총 2회 실행했으며 migration 왕복, seed 재실행,
  실패 시 rollback, WebSocket 실패·disconnect 격리, 통계 부족 fallback과 비데 분기를 포함한다.
- 별도 Docker project/빈 DB에서 빌드, 자동 migration `0002`, Alembic metadata 일치, seed 최초/재실행을 확인했다.
  두 실제 WebSocket 클라이언트와 HTTP 요청으로 Sensor → commit → 방송 → 목록·상세·추천 변경을 검증했다.
  테스트 fixture에서 a-01 점유 시 일반 추천 1층·비데 추천 2층, a-03도 점유 시 두 추천 모두 2층으로 바뀌었다.
  중복 요청은 DB·방송 변화가 없었고 disconnect 후 다른 클라이언트와 재연결 클라이언트가 정상 수신했다.
- 임시 DB에서 404·409·422, 비데 빈칸 없음 404, 전체 만석 200 fallback을 확인했다.
  DB 중지 시 다섯 REST 작업 모두 503이고, 복구 후 Backend 재시작 없이 정상 연결되며 실패한 쓰기는 반영되지 않았다.
- 모든 Backend 설정이 `.env.example`에 있고 비밀번호 기본값·하드코딩은 없다. `.env`는 Git에서 제외된다.
- 실제 하드웨어·Flutter 실행과 통계 스냅샷 자동 수집은 기존 후속 범위다. 최종 연동 안내의 알려진 제약을 참고한다.
- 최종 이미지에서 모든 응답 모델의 필수 필드 표시와 health·docs·목록·상세·비데 추천 200을 재확인했다.
  기존 업무 테이블 모든 행과 `.env`·공통 계약·루트 파일은 점검 전후 동일하며 임시 스키마·컨테이너·볼륨은 남기지 않았다.
