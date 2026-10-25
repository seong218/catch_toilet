# Catch Toilet

## 실행

Docker Compose 2.20.3 이상이 필요하다. 저장소 루트에서 실행한다.

```bash
test -f backend/.env || cp backend/.env.example backend/.env
```

`backend/.env`의 `POSTGRES_PASSWORD`, `APP_DB_PASSWORD`에 서로 다른 32자 이상 비밀번호를 입력한다.

```bash
docker compose up -d --wait db
docker compose run --rm --build migrate
docker compose up -d --build --no-deps --wait backend
```

최초 실행 시 시설 데이터를 등록한다.

```bash
docker compose run --rm --no-deps migrate python -m app.seed
```

API 문서: <http://localhost:8000/docs> · [Flutter 앱 실행](app/README.md)

## 종료

```bash
docker compose down
```
