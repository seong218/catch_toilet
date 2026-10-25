# PC에서 화장실 테스트 상태 넣기

새 앱의 지도·목록·상세 약도·추천을 실제 본관 8곳, 39칸으로 확인한다.
현재 PC는 설정을 마쳤으므로 저장소 루트에서 아래 명령을 바로 실행할 수 있다.
별도 서버에 연결한 실제 휴대폰에서는 [서버용 실행 방법](SERVER_DEPLOYMENT.md#pc에서-서버의-칸-상태-지정)을 사용한다.
로컬 PC 명령으로 변경한 상태는 별도로 배포한 서버에는 적용되지 않는다.

## 자주 쓰는 명령

```bash
# 화장실 ID, 칸 번호, 현재 상태 확인
./backend/simulate.sh list

# 전체 랜덤 (기본 사용 중 확률 50%)
./backend/simulate.sh random

# 사용 중 확률 70%, 같은 결과를 재현할 난수 번호
./backend/simulate.sh random --occupied-rate 0.7 --seed 42

# 한 화장실만 랜덤
./backend/simulate.sh random --restroom 5

# 화장실 ID 5의 2번 칸 직접 지정
./backend/simulate.sh set --restroom 5 --stall 2 --state free
./backend/simulate.sh set --restroom 5 --stall 2 --state occupied
./backend/simulate.sh set --restroom 5 --stall 2 --state unknown

# 화장실 한 곳의 모든 칸을 번호 순서대로 지정
# 0=빈칸, 1=사용 중, ?=미확인. 칸 수와 정확히 맞춰 입력한다.
./backend/simulate.sh set --restroom 5 --pattern '0,1,0,1'

# 전체 빈칸 / 전체 사용 중 (추천 fallback 확인)
./backend/simulate.sh random --occupied-rate 0
./backend/simulate.sh random --occupied-rate 1

# 특정 화장실 또는 전체 테스트 상태 해제
./backend/simulate.sh reset --restroom 5
./backend/simulate.sh reset
```

화장실 ID는 PC마다 다를 수 있으므로 먼저 `list`로 확인한다. `--stall`은 DB의 칸 ID가 아닌 **화장실 내부 칸 번호**다.
현재 PC에서는 ID 4~7이 남자 B1·1·2·3층, 8~11이 여자 B1·1·2·3층이다. `list`의 `*`는 테스트 상태를 뜻한다.
랜덤은 각 칸을 독립적으로 뽑으므로 지정한 확률이 정확한 칸 비율로 맞춰지는 것은 아니다.

## 여러 칸을 파일로 편집·보관

```bash
./backend/simulate.sh export /tmp/toilet-scenario.json
# 파일의 occupied를 true(사용 중), false(빈칸), null(미확인)로 편집
./backend/simulate.sh apply /tmp/toilet-scenario.json
```

파일에는 `states: [{stall_id, occupied}, ...]`만 넣는다. `stall_id`는 `list`에 표시된 DB 칸 ID다.
export는 기존 파일을 덮어쓰지 않으므로 새 이름을 사용한다. 저장된 파일을 apply하면 서버 재시작 후에도 같은 상태를 재현할 수 있다.

## 앱에서 확인

- 앱은 실제 API 모드(`USE_MOCK=false`)로 실행한다. 기존 가상 Mock 3곳은 이 기능과 관계없다.
- PC 명령을 실행하면 WebSocket으로 빈칸 수·약도 색·추천이 갱신된다. 추천 탭에서 ‘추천 받기’를 누르면 결과를 볼 수 있다.
- 지도·목록·상세·추천에 **테스트 데이터** 표시가 붙는다. 개별 칸의 길게 누르기 설명에도 테스트 상태를 표시한다.
- 본관 시설 수·비데·장애인 칸 위치는 바꾸지 않는다. 여자 비데 미확인은 유지하므로 빈 비데 칸으로 추정하지 않는다.
- 웹 서버 8080을 실행할 필요는 없다. iPhone 시뮬레이터는 기존 `http://localhost:8000`에 연결한다.

## 데이터 보존과 실행 범위

실제 DB의 `Stall.occupied`, 변경 시각, 센서 순번, SensorEvent, RestroomSnapshot은 변경하지 않는다.
테스트 상태는 Backend 메모리에서 조회·추천 시에만 적용한다. 적용된 칸에도 실제 센서 수신·저장은 계속한다.
reset하면 저장된 최신 센서 상태로 돌아가고 센서 미수신 칸은 다시 미확인이 된다.
**서버 재시작 시 모든 테스트 상태가 해제된다.** 잘못된 ID가 섞인 요청은 일부만 적용하지 않고 전체 거부한다.

기본 서버 설정은 비활성화다. 한 요청 및 전체 테스트 상태는 최대 64칸이며 단일 Backend worker를 사용한다.
운영 환경에서는 `ENABLE_SIMULATION=false`를 유지한다. 키는 PC와 서버에만 두고 Flutter·Git에 넣지 않는다.
CLI는 localhost HTTP 또는 HTTPS만 허용하고, 인증 키가 다른 호스트로 전달되지 않도록 redirect를 따르지 않는다.

다른 PC 최초 설정:

1. 기존 Backend 실행 환경과 `backend/.venv`를 준비한다.
2. `backend/.env`에 `ENABLE_SIMULATION=true`와 별도의 `SIMULATION_API_KEY`를 설정한다.
   키는 `python3 -c 'import secrets; print(secrets.token_urlsafe(32))'`로 생성할 수 있다.
3. `docker compose up -d --build --wait`를 실행한다. 시설이 없으면 기존 시설 seed 명령을 실행한다.
4. 위 명령을 실행한다. 다른 주소를 쓰면 `./backend/simulate.sh --url https://서버주소 list`처럼 지정한다.

## 구현·검증 인계

추가: `backend/app/simulation_state.py`, `schemas/simulation.py`, `services/simulation.py`, `api/simulation.py`,
`backend/app/simulate.py`, `backend/simulate.sh`, Backend·Flutter 시뮬레이션 테스트, 이 문서.
수정: Backend 조회·센서 이벤트·응답 스키마·설정·Compose, Flutter 모델·상태 동기화·각 화면의 테스트 표시,
[API 계약](api.md). 새로운 DB migration이나 패키지는 없다. 새 UI 구성·카카오맵·정보 콘텐츠를 유지했다.

서버 150개, Flutter 64개 테스트 통과. 인증·입력 검증·전체 39칸·추천·해제·실제 센서와의 공존·DB 오류 시 원상 유지,
null 이벤트·테스트 표시만 바뀌는 이벤트·약도 표시를 검사했다. Flutter analyze 오류·경고 없음.
전체 회귀는 3회(Backend 1회, Flutter 2회) 실행했다. 첫 Flutter 실행의 테스트 종료 시 남은 타이머를 정리한 뒤 모두 통과했다.
iPhone 18 Pro 시뮬레이터 빌드·실행에서 랜덤 39칸, 수동 패턴·한 칸 지정, 해제, 추천 자동 변경과 지도 안내를 확인했다.
JSON export/apply도 실행했다. 전후 DB의 화장실 11개·칸 51개·센서 51개·이벤트 4개·스냅샷 0개를 비교하여 모두 동일했다.
실제 Arduino 연결과 센서 정확도는 이 테스트에 포함하지 않는다.
