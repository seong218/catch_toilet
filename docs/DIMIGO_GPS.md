# 디미고 시설·GPS 인계 (2026-10-24)

현재 센서 미수신 칸을 테스트하려면 [PC 상태 시뮬레이션](SIMULATION.md)을 사용한다.
실제 상태와 시설 정보를 유지하면서 임의 상태를 적용·해제할 수 있다.

## 반영한 시설 정보

사용자가 확인한 본관 8개 화장실, 총 39칸이다. 장애인 칸은 전체 칸 수에 포함한다.

| 구분 | 층 | 전체 | 비데 칸 번호 | 장애인 칸 번호 |
| --- | --- | ---: | --- | --- |
| 남자 | 지하 1층 | 5 | 1 | 없음 |
| 남자 | 1층 | 4 | 2, 3, 4 | 1 (비데 없음) |
| 남자 | 2층 | 5 | 1, 2 | 없음 |
| 남자 | 3층 | 5 | 1, 2 | 없음 |
| 여자 | 지하 1층 | 5 | 미확인 | 없음 |
| 여자 | 1층 | 4 | 1번은 없음, 2~4번 미확인 | 1 |
| 여자 | 2층 | 6 | 미확인 | 없음 |
| 여자 | 3층 | 5 | 미확인 | 없음 |

여자 화장실의 `bidet_stalls`는 0이 아닌 null이다. 사용 상태는 실제 센서가 관측하기 전까지
`occupied=null`, `unknown_stalls=total_stalls`로 표시한다. 관측되지 않은 칸을 빈칸이나 만석으로 간주하지 않는다.
설치된 비데 수와 현재 빈 비데 수는 별개다. 첫 센서 관측부터 이벤트 저장·WebSocket 갱신·추천을 처리한다.

## GPS와 앱

- 설정의 Backend/WebSocket 연결 정보, x/y 입력, 현재 층 입력을 제거했다.
- GPS는 사용자가 위치 버튼을 눌렀을 때 가져온다. 권한 거부·시간 초과 시 기존 기준 위치를 유지한다.
- 새 앱은 `latitude`, `longitude`와 목록·추천의 `gender=male|female`을 보낸다. 센서 키는 앱에 넣지 않는다.
- 서버는 GPS 직선거리를 미터로 계산한다. 현재 층·층 차이·계단·보행 경로는 추천에 사용하지 않는다.
- 화장실의 층은 상세·층별 안내에서 위치 정보로만 표시한다.
- 위치는 세션 메모리에서 사용하고 DB에 저장하지 않는다. 기본 Uvicorn 요청 로그도 꺼서 위치 Query가 기록되지 않게 했다.
  배포 시 별도 프록시 로그에도 위치 Query를 남기지 않아야 한다.
- 기본 실행은 실제 API 모드다. 가상 데이터가 필요할 때만 `--dart-define=USE_MOCK=true`를 지정한다.

현재 등록 좌표는 교육부 [HIFIVE 학교 지도](https://www.hifive.go.kr/search/schoolMap.do?sch_seq=653)의
학교 대표점 `37.34156740773243, 126.83126714636612`다. `location_source=school_reference`로 구분하며
본관 출입구나 칸을 실측한 위치가 아니다. 본관의 모든 층은 같은 위치를 사용한다.
신관·체육관 시설 수와 건물별 실측 좌표는 제공되지 않아 등록하지 않았다. 데이터가 준비되면
Restroom의 `building`, `latitude`, `longitude`, `location_source`를 등록하면 같은 GPS 추천 로직을 사용할 수 있다.

## DB·센서 연결

- `0004`: GPS·성별·시설 집계·활성화 정보와 미관측 상태 추가.
- `0005`: `is_accessible`를 기본 false인 필수 boolean으로 정리. seed에서 확인된 1층 1번을 true로 설정한다.
- `python -m app.seed`: 실제 본관 시설을 동기화한다. 알려진 시설 매핑은 갱신하되 실시간 상태·상태 변경 시각·센서 순번·이력은 보존한다.
  여자 비데의 미확인 값 때문에 나중에 현장 확인한 칸별 값을 지우지 않는다.
- 이전 개발용 3곳은 `is_active=false`, 해당 센서는 `active=false`로 보관한다. 기존 12칸과 이벤트를 삭제하지 않는다.
- 센서 ID: `dimigo-main-{m|f}-{b1|1|2|3}-{01..칸수}`. 예: `dimigo-main-m-1-02`는 남자 1층 2번 비데 칸이다.
- 기기별 Bearer 키와 본문의 `device_id`, `occupied`가 필요하다. `sequence`는 보내지 않아도 된다.
  키는 서버 `.env`와 해당 기기 또는 USB 중계 PC에만 보관한다.
  현재 PC에서는 39개 새 센서 키를 Git에서 제외된 `backend/.env`에 생성했다. 다른 PC에서는 별도로 발급해야 한다.
  상세 인증·재시도·속도 제한 규칙은 [보안 인계](../backend/SECURITY.md)를 따른다.
- 시설 seed는 사용 이벤트나 과거 통계를 생성하지 않는다. 실제 Arduino 연결 및 통계 정기 수집은 별도 작업이다.

## 실행

주요 수정 파일: `backend/app/seed.py`, `api/restrooms.py`, `services/location.py`, `services/recommendation.py`,
모델·응답 스키마, `app/lib/services/location_service.dart`, 설정·상세·위치 편집 화면, `docs/api.md`.
추가 파일: `backend/app/dimigo_data.py`, migration `0004`·`0005`, `backend/tests/test_dimigo_gps.py`,
`app/test/location_service_test.dart`, 이 인계 문서. 기존 가상 x/y 지도 투영 파일은 제거했다.

기존 `backend/.env`를 유지하고 저장소 루트에서 실행한다.

```bash
docker compose up -d --build --wait
docker compose run --rm migrate python -m app.seed
cd app
BYPASS_PERMISSION_LOCATION_ALWAYS=1 .tools/flutter/bin/flutter run \
  -d <iPhone-simulator-id> \
  --dart-define=USE_MOCK=false \
  --dart-define=API_BASE_URL=http://localhost:8000
```

`BYPASS_PERMISSION_LOCATION_ALWAYS=1`은 geolocator Apple의 Swift Package Manager 빌드에서
항상 위치 권한을 제외한다. 앱은 사용 중 위치 권한만 요청하며 백그라운드 추적을 하지 않는다.
SDK를 PATH에 설치한 PC에서는 `.tools/flutter/bin/flutter` 대신 `flutter`를 사용한다.
iPhone 시뮬레이터 실행에 웹 서버 8080은 필요 없다.

예시 조회:

```bash
curl 'http://localhost:8000/api/restrooms?latitude=37.3415674&longitude=126.8312671&gender=male'
```

전체 칸이 미관측이면 추천은 `404 / Live availability unavailable`이고 앱은 센서 연결 대기 안내를 표시한다.
구형 x/y Query는 호환용으로만 유지하며 GPS와 혼합해서 보내면 422다. 전체 계약은 [api.md](api.md)를 따른다.

## 검증

- Flutter: 33개 테스트 통과, 최종 analyze 오류·경고 없음, iPhone 18 Pro 시뮬레이터 빌드·실행 성공.
- Backend: 최초 139개 통과. 최종 141개 중 139개 통과, `is_accessible`가 null이라는 이전 기대값 2곳이 실패했다.
  해당 기대값을 필수 boolean/false로 수정했다. 프로젝트의 전체 회귀 최대 4회 제한에 따라 수정 후 전체 suite는 재실행하지 않았다.
  새 칸별 시설 매핑·기존 관측 시각 보존 테스트는 최종 실행에서 통과했다.
- 실제 API: 남녀 각 4곳·전체 39칸, 칸별 비데·장애인 배치, boolean OpenAPI 계약, 기존 이력 보존 확인.
- iPhone: 1층 1번 장애인·비데 없음, 2~4번 비데 있음 표시 확인. 학교 대표점을 시뮬레이터 테스트 위치로 주입하여 GPS 가져오기·적용 확인.
- `git diff --check` 및 실제 로컬 비밀값의 커밋 후보 파일 유출 검사 통과. 웹 서버 8080은 중지 상태.

실기기의 GPS 정확도나 Arduino 실측 검증은 아직 수행하지 않았다.
