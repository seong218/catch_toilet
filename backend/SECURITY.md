# Backend 보안 설정과 연동 변경

## 실행

`backend/.env.example`의 설정을 사용한다. 기존 `.env`를 덮어쓰지 않는다.
`POSTGRES_USER/PASSWORD`는 DB 초기 관리자·migration용이고,
`APP_DB_USER/PASSWORD`는 API 실행 전용이다. 비밀번호는 서로 다른 난수로 생성한다.
비밀은 `.env`(권한 0600)에만 저장하며 Git·Docker 이미지에 넣지 않는다.

```bash
docker compose up -d --build --wait backend
docker compose run --rm migrate python -m app.seed
```

DB healthcheck 후 일회성 `migrate` 작업이 최신 migration까지 적용하고 실행 계정을 설정한다.
API에는 관리자 자격 증명이 전달되지 않는다. 실행 계정은 superuser/createdb/createrole/replication/bypassrls가 아니다.
도메인 테이블 SELECT, Stall 상태·Sensor 순번/마지막 수신 시각 열 UPDATE,
SensorEvent INSERT/DELETE, RestroomSnapshot INSERT와 두 테이블의 ID sequence USAGE,
StatisticsTracking의 상태·시각 열 UPDATE만 허용한다.
테이블·역할 생성, 칸·센서 등록, migration·seed는 관리자 작업에서만 실행한다.
통계 수집은 같은 제한 계정으로 실행하며 기존 스냅샷의 UPDATE/DELETE 권한은 부여하지 않는다.
`0007` 적용 시 `docker compose run --rm --build migrate`로 런타임 권한까지 갱신한다.
추적 제어는 서버의 CLI로만 제공한다. 기본 중지이며 시작 전 관측은 새 추적에 사용하지 않는다.

Compose 밖에서 실행할 경우 먼저 위 migration 작업을 완료한다. 로컬 API에도 제한된 계정을 주입한다.
다음은 저장소 루트에서 실행하며 비밀번호를 출력하거나 프로세스 인자로 전달하지 않는다.

```bash
backend/.venv/bin/python - <<'PY'
import os
from pathlib import Path
from dotenv import dotenv_values
root = Path.cwd()
values = dotenv_values(root / 'backend/.env')
os.environ['POSTGRES_USER'] = values['APP_DB_USER']
os.environ['POSTGRES_PASSWORD'] = values['APP_DB_PASSWORD']
os.chdir(root / 'backend')
python = str(root / 'backend/.venv/bin/python')
os.execv(python, [python, '-m', 'uvicorn', 'app.main:app', '--host', '127.0.0.1',
                 '--port', '8000', '--workers', '1', '--no-proxy-headers',
                 '--ws-max-size', '4096', '--ws-max-queue', '4'])
PY
```

## 센서 인증·재전송·속도 제한

- `SENSOR_API_KEYS`는 `device_id`별로 다른 난수 키를 담은 JSON 객체다. 키가 없으면 쓰기를 차단한다.
- 센서 요청에 `Authorization: Bearer <해당 기기의 키>`를 보낸다. Flutter에는 이 키를 배포하지 않는다.
- 본문은 `{"device_id":"stall-a-01","occupied":true}`이다. 입력 ID는 ASCII 영숫자와 `._:-`만 허용하며 영숫자로 시작하고 최대 128자다.
- `sequence`는 API에서 제거했다. 기존 클라이언트가 보내면 무시한다. 기기는 순번을 생성·보존할 필요가 없다.
- 요청이 처리되는 순서대로 상태를 반영한다. 인증된 과거 요청의 재전송이나 요청 순서 뒤집기는 구분하지 않는다.
- 현재 상태와 같으면 200/changed=false이며 칸·이벤트·방송은 바뀌지 않는다. 정상 요청마다 마지막 보고 상태와
  `last_seen_at`을 갱신한다. 429 등 거부된 요청은 이 정보도 갱신하지 않는다.
- DB의 기존 `last_sequence` 값은 호환성을 위해 보존하되 API와 통계 판단에서는 사용하지 않는다.
- 기본 제한은 기기당 초당 0.2회(5초당 1회), burst 2회, 전체 초당 5회, burst 10회다.
  `SENSOR_RATE_PER_SECOND/BURST`, `SENSOR_GLOBAL_RATE_PER_SECOND/BURST`로 조정한다.
- 같은 칸의 실제 상태 변경은 `SENSOR_MIN_STATE_INTERVAL_SECONDS`(기본 1초) 이상 간격이 필요하다.
  429의 `Retry-After`초 뒤 센서의 최신 상태를 보고한다. 기기의 debounce도 유지한다.
- 요청 제한은 인증 후 DB 접근 전에 적용한다. 단일 worker의 메모리 제한이므로 재시작 시 bucket만 초기화된다.
  다중 worker/replica 배포에는 공유 limiter와 방송 계층이 필요하다.
- API 키는 전송 서명이 아니다. 로컬 개발 HTTP 이외에는 HTTPS를 사용한다. 키가 유출되면 폐기·교체한다.

## 검증과 WebSocket

- 요청 좌표는 각 축 ±1,000,000m 이내의 유한 수다. 계산 결과도 유한한지 확인하고 오류는 422로 처리한다.
- NaN/Infinity, surrogate, NUL 등 잘못된 센서 입력은 422다. 검증 응답은 `loc/msg/type`만 포함하고 원문 입력을 반사하지 않는다.
- WebSocket Origin은 `WS_ALLOWED_ORIGINS` JSON 목록을 사용한다. 기본 `[]`는 `CORS_ALLOWED_ORIGINS`를 사용한다.
  `null`, 다중 Origin, 미등록 origin은 accept 전에 거부한다. Origin 없는 native 앱은 허용한다.
- 스트림은 공개 읽기 기능이며 Origin 검증 자체는 사용자 인증이 아니다. 비브라우저 클라이언트의 신원을 증명하지 않는다.
- `WS_MAX_CONNECTIONS` 기본 100, `WS_MAX_CONNECTIONS_PER_IP` 기본 10을 연결 수락 전에 적용한다.
  수락 중인 연결·종료 중인 연결도 슬롯을 차지하며 실패·종료 후 반환한다. 전송 큐 64, 송신 timeout 2초를 유지한다.
- Uvicorn 수신 메시지는 4KiB, 수신 큐는 4개로 제한한다. 클라이언트 메시지는 상태 변경 명령으로 처리하지 않는다.
- 기본 실행은 전달된 proxy header를 신뢰하지 않고 실제 연결 IP를 사용한다. 프록시 배포 시 신뢰 경계를 별도로 설정한다.
- `API_BIND_HOST` 기본은 `127.0.0.1`이다. iPhone 시뮬레이터는 그대로 사용한다.
  실제 기기에 공개할 때만 PC LAN IP를 설정하고 Backend를 재생성한다.

## 이벤트 보관

`SENSOR_EVENT_RETENTION_DAYS` 기본 90일이다. API 프로세스가 60초마다 만료 SensorEvent를 최대 1,000개씩 삭제한다.
created_at 인덱스로 조회하며 DB statement timeout을 적용한다. 경계 시각과 더 최근 이벤트는 유지한다.
통계용 RestroomSnapshot은 삭제하지 않는다. 원본 장기 보관이 필요하면 보관기간 전에 별도 저장소로 아카이브한다.
비정상 종료 후 다음 실행에서 정리가 이어지며 한 번에 전체 이력을 삭제하지 않는다.

## 검증 범위

임시 PostgreSQL 스키마에서 인증, 순번 없는 요청·동시 중복 처리, 상태 변경 간격, 요청 제한,
좌표·JSON 검증, WebSocket Origin·전체/IP 한도와 슬롯 반환, 보관기간·배치 경계를 검사한다.
Flutter의 조회 응답·WebSocket 이벤트 필드는 유지한다. IoT 송신부는 Bearer 헤더와 현재 상태만 보내면 된다.

2026-10-24 검증: 전체 133개 테스트 통과(센서 인증 작업부터 합산 회귀 suite 3회 이내).
Docker 재빌드·기존 DB의 `0002 → 0003` 적용·제한 계정 실행·healthcheck를 확인했다.
실제 런타임 계정 `catchy_toilet_app`의 superuser/createdb/createrole/replication/bypassrls는 모두 false이며,
public schema 생성·DB 생성 권한·화장실 INSERT·Sensor 전체 열 UPDATE 권한이 없다.
실제 HTTP에서 읽기 200, 인증 누락/다른 기기 키 401, 인증된 동일 상태 200/changed=false를 확인했다.
실제 WebSocket은 native/허용 Origin 연결 성공, 미등록/null Origin handshake 403을 확인했다.
기존 화장실·칸 상태·센서 매핑·이벤트·스냅샷 행은 작업 전후 동일하다. 인증된 검증 요청으로 a-01의 새 순번만 1로 전진했다.
현재 Arduino firmware 디렉터리가 없어 실기기 송신부와 TLS 프록시 배포는 이번 검증에 포함하지 않았다.
