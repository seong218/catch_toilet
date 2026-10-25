# Flutter 연동 인계 — 2026-10-24

## REST API Base URL / WebSocket URL

Base URL에는 `/api`를 포함하지 않는다. 아래 Endpoint 경로를 이어 붙인다.

| 실행 위치 | REST Base URL | WebSocket URL |
| --- | --- | --- |
| 개발 PC | `http://localhost:8000` | `ws://localhost:8000/ws` |
| Android 기본 에뮬레이터 | `http://10.0.2.2:8000` | `ws://10.0.2.2:8000/ws` |
| 같은 네트워크의 실제 기기 | `http://172.16.8.195:8000` | `ws://172.16.8.195:8000/ws` |

`172.16.8.195`는 점검 당시 개발 PC의 LAN IP다. 네트워크가 바뀌면 다시 확인한다.
LAN 주소의 HTTP 200·WebSocket 101은 개발 PC에서 확인했으며 실제 모바일 기기에서의 접근은 별도 확인이 필요하다.
기본 공개 주소는 이제 `127.0.0.1`이다. 실제 기기 연결 시 `API_BIND_HOST`를 PC LAN IP로 설정하고 Backend를 재생성한다.
iPhone 시뮬레이터에서는 `localhost`를 그대로 사용할 수 있다.
`API_PORT`를 바꾸면 위 포트도 변경한다. Swagger UI: <http://localhost:8000/docs>.

## 실행 방법

Docker Compose 2.20.3 이상. 모든 명령은 저장소 루트에서 실행한다.
최초 한 번 `backend/.env.example`을 `backend/.env`로 복사하고 `POSTGRES_PASSWORD`와 별도의 `APP_DB_PASSWORD`를 설정한다.
기존 `backend/.env`는 덮어쓰지 않는다.

```bash
docker compose up -d --build --wait
docker compose run --rm migrate python -m app.seed
```

`docker compose up`으로 foreground 실행도 가능하다.
DB healthcheck 통과 후 migration이 자동 적용된다. 현재 revision은 `0003`다. migration 작업만 관리자 계정으로 실행하며 API는 제한된 계정을 쓴다.

```bash
docker compose run --rm migrate alembic current
docker compose run --rm migrate alembic upgrade head
docker compose down
```

일반 종료는 DB 볼륨을 유지한다. 설정 변경은 `docker compose up -d --wait backend`,
코드·migration 변경은 `--build`를 포함해 실행한다.

## 디미고·GPS 변경

현재 데이터는 본관 남녀 각 4곳, 총 39칸이다. 상세 시설 표·좌표 출처·GPS 실행·미관측 처리·센서 ID는
[디미고 인계](../docs/DIMIGO_GPS.md)를 따른다. 남녀 1층 장애인 1번은 총 4칸에 포함하며 비데가 없다.
여자 화장실 비데 수는 미확인이다. 이전 개발 fixture 3곳은 이력 보존을 위해 비활성화했다.

모바일은 latitude/longitude와 gender를 사용한다. 현재 층 입력·가중치는 없다. x/y는 구형 호환용이다.
occupied/has_bidet의 null은 false와 다르며 unknown_stalls를 반영한다. 미관측 칸만 있을 때는 추천하지 않는다.

## 구현된 Endpoint

| Method | 경로 | 입력 / 결과 |
| --- | --- | --- |
| GET | `/api/health` | `{"status":"ok"}` |
| GET | `/api/restrooms` | `latitude`, `longitude` 함께 생략 가능, 선택 gender. 화장실 배열 |
| GET | `/api/restrooms/{restroom_id}` | 선택 좌표와 `stalls`가 포함된 상세 |
| GET | `/api/restrooms/recommend` | `latitude`, `longitude` 필수, 선택 gender, `bidet_required=false` 기본값. 추천 한 곳 |
| POST | `/api/sensors/stall` | 기기별 Bearer 인증 필수. `{"device_id":"stall-a-01","occupied":true,"sequence":1}` → `{"success":true,"changed":true}` |
| WS | `/ws` | 별도 구독 메시지 없이 이후 `stall.updated` 수신 |

데이터 계약은 [docs/api.md](../docs/api.md)다. 조회·WebSocket은 로그인·인증 헤더가 필요 없다.
센서 쓰기에만 `Authorization: Bearer <해당 device_id의 키>`가 필수다. 이 키를 Flutter 앱에 넣지 않는다.
IoT는 재부팅에도 유지되는 단조 증가 `sequence`를 보내야 한다. `409`는 오래된 번호, `429`는 속도 제한이다.
키 설정·교체·철회는 [Backend 안내](README.md#기기별-키-설정과-교체)를 따른다.

- 목록·상세의 `distance`는 좌표 생략 시 `null`, 추천의 `distance`는 항상 숫자다.
- 추천의 두 `historical_*_availability_rate`는 각각 `null`일 수 있다. 키는 항상 존재하며 `0.0`과 `null`을 구분한다.
  통계 사용 표시는 `statistics_used`를 따른다. `false`여도 비율이 non-null일 수 있다.
- 일반 빈칸이 있지만 빈 비데 칸이 없으면 비데 요청은 `404 / No available bidet stalls`다.
  미관측 칸 없이 전체 만석이면 비데 설정과 관계없이 가장 가까운 화장실을 `200`으로 반환하므로 빈칸 0 안내가 필요하다.
- 미등록 화장실·인증된 미등록 센서는 `404`, 센서 인증 실패는 `401`, 비활성/잘못 연결된 센서는 `409`, 입력 오류는 `422`, DB 접근 불가는 `503`이다.
  센서 키 설정이 없으면 쓰기만 `503 / Sensor authentication unavailable`로 차단된다.
  `detail`은 일반 오류에서 문자열, `422`에서는 배열이다. 화장실 미등록 시 목록은 `200 []`, 추천은 `404`다.
- 같은 센서 상태를 재전송하면 `changed=false`이며 중복 이벤트·WebSocket 방송은 없다.

## 필요한 환경변수

Backend/Compose 설정 파일은 [`backend/.env.example`](.env.example)을 복사한 `backend/.env`다.
Flutter에는 위 REST·WebSocket 주소를 설정한다.

| 변수 | 기본 / 설정 |
| --- | --- |
| `POSTGRES_DB`, `POSTGRES_USER`, `POSTGRES_PASSWORD` | 필수. 예제의 비밀번호는 비어 있으므로 직접 설정 |
| `POSTGRES_HOST`, `POSTGRES_PORT` | 로컬 `localhost:5432`; Compose 내부는 `db:5432` |
| `APP_DB_USER`, `APP_DB_PASSWORD` | 제한된 API 실행 계정·별도 비밀번호 |
| `API_PORT` | `8000` |
| `API_BIND_HOST` | `127.0.0.1`; 실제 기기 연결 시 PC LAN IP를 명시 |
| `SENSOR_API_KEYS` | 기기별 비밀 키 JSON 객체. 기본 `{}`이면 센서 쓰기 차단. Flutter에 배포하지 않음 |
| `DB_CONNECT_TIMEOUT`, `DB_STATEMENT_TIMEOUT_MS` | `5`초, `5000`밀리초 |
| `MIN_STAT_SAMPLE_COUNT`, `STAT_LOOKBACK_DAYS` | `30`, `56`일 |
| `RECOMMENDATION_DISTANCE_TOLERANCE` | `10`m |
| `CORS_ALLOWED_ORIGINS` | JSON 배열. 기본 localhost·127.0.0.1의 3000·8080 포트 |

Flutter Web에서는 실제 브라우저 origin을 CORS 배열에 설정한다. 예: `CORS_ALLOWED_ORIGINS='["http://localhost:5173"]'`.
Native Flutter에는 브라우저 CORS가 적용되지 않는다.

## 알려진 문제 / 연동 시 처리할 사항

- 최종 점검에서 발견한 Health OpenAPI의 `status` 필수 표시를 수정했다. 현재 확인된 미해결 API 계약 불일치는 없다.
- 통계 스냅샷 자동 수집은 아직 없다. 현재 개발 DB에는 스냅샷이 없으므로 실시간 빈칸·거리로 추천하며
  `statistics_used=false`, 두 과거 비율은 `null`이다. 통계 계산·추천 보정은 준비되어 있다.
- WebSocket은 단절 중 이벤트나 초기 snapshot을 재전송하지 않는다. 최초 연결·재연결·앱 복귀 시
  REST 목록·열린 상세·추천을 동기화한다. 조회 중 이벤트가 겹친 화장실은 상세를 다시 조회한다.
- `stall.updated`의 `restroom_id`로 목록을 찾고 `total_stalls`, `available_stalls`, `available_bidet_stalls`를 **대입**한다.
  상세는 `stall_id`의 `occupied`를 바꾸고, 현재 좌표·비데 조건으로 추천을 재요청한다.
  알 수 없는 이벤트 type은 무시한다. 연결 종료/실패는 간격을 두고 재연결 후 REST로 복구한다.
- 현재 WebSocket은 단일 Backend 프로세스 구성이다. 실제 Flutter 앱·Arduino 하드웨어를 연결한 검증은 아직 하지 않았다.

점검 근거: PostgreSQL을 사용하는 109개 테스트 통과(회귀 2회), 별도 Docker 환경에서 실제 HTTP·WebSocket 연동,
disconnect/reconnect, 상태 코드·null 처리, migration·seed, DB 장애 및 복구를 확인했다.

추가 보안 정책(좌표 범위, Origin·연결 수, 속도·보관 제한)은 [SECURITY.md](SECURITY.md)를 따른다.
