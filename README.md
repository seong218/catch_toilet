# Catch Toilet

for 급똥

## 센서 없이 테스트

`./backend/simulate.sh random`으로 전체 임의 상태를 넣고, `set`으로 칸별 지정, `reset`으로 해제한다.
[PC 명령·직접 지정·JSON 파일 안내](docs/SIMULATION.md)를 참고한다.

## Backend · PostgreSQL 개발 실행

Docker Compose 2.20.3 이상을 사용한다. 최초 한 번, 저장소 루트에서 환경 파일을 준비한다.
이미 `backend/.env`가 있으면 그대로 사용한다.

```bash
cp backend/.env.example backend/.env
```

`backend/.env`의 `POSTGRES_PASSWORD`와 `APP_DB_PASSWORD`에 서로 다른 난수 비밀번호를 입력한다.
관리자 비밀번호는 DB·migration 작업에만 쓰고 API는 제한된 별도 계정을 사용한다.
예: `python3 -c 'import secrets; print(secrets.token_urlsafe(32))'`.
환경 파일은 Git에서 제외하며 루트 `.env`는 필요 없다.

```bash
docker compose up
```

DB healthcheck → 일회성 migration·런타임 계정 권한 설정 → FastAPI 순서로 시작한다.
다른 터미널에서 디미고 본관 화장실 8개·칸 39개·센서 39개를 준비한다.

```bash
docker compose run --rm migrate python -m app.seed
```

Seed는 확인된 시설 정보를 동기화하고 기존 사용 상태·이력을 유지한다. 센서 수신 전 사용 상태는 미확인이며 과거 통계를 만들지 않는다.

[실제 시설 표·GPS·iPhone 실행·담당자 인계](docs/DIMIGO_GPS.md)를 참고한다. 현재 층 입력은 없으며 GPS로 건물 간 거리를 비교한다.

- API 문서: <http://localhost:8000/docs>
- 상태 확인: <http://localhost:8000/api/health>
- 화장실 목록: <http://localhost:8000/api/restrooms>
- 백그라운드 실행 및 변경한 코드 반영: `docker compose up -d --build --wait`
- 종료: `docker compose down` (DB 볼륨 유지)

[환경변수·CORS·migration·테스트·기기 접속](backend/README.md),
[DB 모델·seed 데이터](database/README.md), [API 계약](docs/api.md)을 참고한다.

센서 쓰기에는 기기별 Bearer 키와 증가하는 `sequence`가 필요하다. 기본 API 공개 주소는 `127.0.0.1`이다.
[보안 설정·IoT 변경 사항](backend/SECURITY.md)을 참고한다.
