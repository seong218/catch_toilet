# Catchy toilet

for 급똥

## Backend · PostgreSQL 개발 실행

Docker Compose 2.20.3 이상을 사용한다. 최초 한 번, 저장소 루트에서 환경 파일을 준비한다.
이미 `backend/.env`가 있으면 그대로 사용한다.

```bash
cp backend/.env.example backend/.env
```

`backend/.env`의 빈 `POSTGRES_PASSWORD`에 직접 생성한 비밀번호를 입력한다.
예: `python3 -c 'import secrets; print(secrets.token_urlsafe(32))'`.
환경 파일은 Git에서 제외하며 루트 `.env`는 필요 없다.

```bash
docker compose up
```

DB healthcheck가 통과하면 migration을 적용한 뒤 FastAPI를 시작한다.
다른 터미널에서 개발용 화장실 3개·칸 12개·센서 12개를 준비한다.

```bash
docker compose exec backend python -m app.seed
```

Seed는 기존 상태·이력을 유지하며 재실행할 수 있다. 과거 통계 데이터는 만들지 않는다.

- API 문서: <http://localhost:8000/docs>
- 상태 확인: <http://localhost:8000/api/health>
- 화장실 목록: <http://localhost:8000/api/restrooms>
- 백그라운드 실행 및 변경한 코드 반영: `docker compose up -d --build --wait`
- 종료: `docker compose down` (DB 볼륨 유지)

[환경변수·CORS·migration·테스트·기기 접속](backend/README.md),
[DB 모델·seed 데이터](database/README.md), [API 계약](docs/api.md)을 참고한다.
