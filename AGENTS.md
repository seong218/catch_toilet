# Catch Toilet — Common Development Context

너는 `Catch Toilet` 프로젝트를 함께 개발하는 소프트웨어 엔지니어다.

이 프로젝트는 IoT 센서를 이용해 화장실 칸의 사용 여부를 실시간으로 감지하고, 사용자에게 화장실별 빈칸 및 비데 정보를 보여주며, 현재 위치와 실시간 상태, 과거 이용 통계를 기반으로 가장 적절한 화장실을 추천하는 모바일 서비스다.

---

## 1. 프로젝트 목표

사용자는 모바일 앱에서 다음 정보를 확인할 수 있어야 한다.

- 주변 화장실 목록
- 화장실별 실시간 빈칸 수
- 개별 칸 사용 여부
- 개별 칸 비데 유무
- 현재 위치와 화장실 간 거리
- 비데 필수 여부 설정
- 조건에 맞는 추천 화장실
- 과거 이용 데이터를 활용한 통계 기반 추천

핵심 컨셉은 다음과 같다.

> 가장 가까운 화장실만 찾는 것이 아니라, 실제로 사용할 수 있는 빈칸과 과거 이용 패턴까지 고려하여 적절한 화장실을 추천한다.

---

## 2. 전체 기술 스택

### Mobile

- Flutter
- Dart
- Android / iOS

### Backend

- Python
- FastAPI
- REST API
- WebSocket

### Database

- PostgreSQL
- SQLAlchemy
- Alembic

### IoT

- Arduino UNO R4 WiFi
- Arduino C++
- SW-520D Tilt Sensor

### IoT Communication

- Wi-Fi
- HTTP

### Infrastructure

- Docker
- Docker Compose

---

## 3. 전체 시스템 구조

기본 데이터 흐름은 다음과 같다.

```text
SW-520D Tilt Sensor
        ↓
Arduino UNO R4 WiFi
        ↓
     Wi-Fi / HTTP
        ↓
FastAPI Backend
        ↓
PostgreSQL
        ↓
WebSocket
        ↓
Flutter App
```

화장실 잠금장치의 움직임을 SW-520D 기울기 센서로 감지한다.

Arduino UNO R4 WiFi는 센서 값을 읽고 칸의 사용 상태가 변경되면 FastAPI 서버에 HTTP 요청을 전송한다.

FastAPI 서버는 다음을 수행한다.

1. 센서 데이터를 검증한다.
2. 해당 센서와 연결된 화장실 칸을 찾는다.
3. PostgreSQL의 칸 상태를 업데이트한다.
4. 센서 상태 변경 이벤트를 기록한다.
5. 누적된 이벤트를 통계 데이터에 활용한다.
6. 연결된 Flutter 클라이언트에 WebSocket 이벤트를 전달한다.

Flutter 앱은 WebSocket 이벤트를 받아 화면을 실시간으로 갱신한다.

---

## 4. Repository 구조

기본적으로 다음 구조를 사용한다.

```text
catch_toilet/
├── app/
│   └── Flutter application
│
├── backend/
│   └── FastAPI application
│
├── database/
│   └── Database related files
│
├── firmware/
│   └── Arduino UNO R4 WiFi firmware
│
├── docs/
│   └── api.md
│
├── docker-compose.yml
├── .env.example
├── .gitignore
└── README.md
```

기존 repository에 이미 다른 구조가 존재한다면 무조건 새로 만들지 말고 기존 구조를 먼저 분석한 후 가능한 한 기존 구조를 유지한다.

---

## 5. 담당 영역 규칙

프로젝트는 여러 명과 여러 Codex 세션이 동시에 개발한다.

따라서 자신의 담당 영역 밖의 코드는 임의로 변경하지 않는다.

### Flutter 담당

```text
app/
```

### Backend / Database 담당

```text
backend/
database/
```

### IoT 담당

```text
firmware/
```

Backend 담당자가 IoT까지 맡는 경우에는 다음 영역을 담당한다.

```text
backend/
database/
firmware/
```

---

## 6. 반드시 지켜야 할 협업 규칙

1. 작업 전에 repository 전체 구조와 기존 코드를 먼저 확인한다.

2. 자신의 담당 디렉터리 외 파일은 사용자의 명시적인 요청 없이는 수정하지 않는다.

3. 다른 사람이 작성한 코드를 이유 없이 재작성하거나 삭제하지 않는다.

4. 기존에 정상적으로 동작하는 기능을 깨뜨리지 않는다.

5. Frontend와 Backend 사이의 데이터 계약은 `docs/api.md`를 기준으로 한다.

6. API 구조나 response schema를 임의로 변경하지 않는다.

7. API 계약 변경이 반드시 필요한 경우 코드를 먼저 변경하지 말고 어떤 변경이 필요한지 먼저 정리한다.

8. password, token, API key, database credential 등의 secret을 코드에 하드코딩하지 않는다.

9. `.env` 파일은 Git에 커밋하지 않는다.

10. 필요한 환경변수는 `.env.example`에 작성한다.

11. 하나의 파일에 모든 기능을 몰아넣지 않는다.

12. UI, API, business logic, database logic, recommendation logic, hardware communication logic을 적절히 분리한다.

13. 임시 hardcoding은 최소화한다.

14. 예외 및 오류 상황을 반드시 처리한다.

15. 실행할 수 없는 pseudo-code나 TODO만 작성하고 작업을 끝내지 않는다.

16. 구현 후 가능한 범위에서 build, lint, test 또는 실행 검증을 수행하되 과도한 회귀 테스트는 진행하지 않는다. 회귀 테스트는 최대 4번으로 제한한다.

17. 테스트 또는 실행 과정에서 발견된 오류는 가능한 경우 직접 수정한다.

18. 필요하지 않은 dependency는 추가하지 않는다.

19. 과도하게 복잡한 architecture나 abstraction을 만들지 않는다.

20. 해커톤 MVP의 실제 동작 완성을 최우선으로 한다.

21. 이미 동작하는 기능을 코드 스타일이나 개인적인 선호만으로 대규모 리팩터링하지 않는다.

22. 다른 담당자가 작업하고 있을 가능성이 있는 파일을 임의로 수정하지 않는다.

23. 작업 종료 시 다른 담당자가 알아야 할 변경 사항을 명확하게 기록한다.

---

## 7. MVP 핵심 기능

### 사용자 앱

- 화장실 목록
- 화장실 상세 정보
- 실시간 빈칸 수
- 개별 칸 사용 여부
- 비데 여부
- 현재 위치 또는 기준 위치
- 화장실까지의 거리
- 비데 필수 옵션
- 추천 화장실
- REST API 연결
- WebSocket 실시간 업데이트

### Backend

- 화장실 조회 API
- 화장실 상세 API
- Sensor API
- PostgreSQL 연동
- 센서 이벤트 저장
- 이용 통계 계산
- WebSocket broadcast
- 화장실 추천 알고리즘

### IoT

- SW-520D 센서 상태 읽기
- 센서 상태 변화 감지
- Wi-Fi 연결
- FastAPI로 HTTP 요청
- 네트워크 오류 처리
- 센서 값 안정화 처리

---

## 8. 데이터 모델

최소 다음 데이터를 관리한다.

### Restroom

```text
id
name
building
floor
x
y
created_at
```

`x`, `y`는 MVP에서 사용자의 위치와 화장실 간 거리를 계산하기 위한 좌표로 사용한다.

향후 GPS, 지도 API 또는 실내 위치 시스템으로 교체할 수 있도록 위치 계산 로직은 별도로 분리한다.

### Stall

```text
id
restroom_id
stall_number
occupied
has_bidet
updated_at
```

### Sensor

```text
id
device_id
restroom_id
stall_id
sensor_type
active
```

### SensorEvent

```text
id
sensor_id
event_type
value
created_at
```

센서 상태 변경은 반드시 `SensorEvent`에 기록한다.

이 데이터는 이후 시간대별 화장실 이용 통계를 계산하는 원본 데이터로 사용한다.

---

## 9. 빈칸 계산

### 전체 칸

```text
total_stalls
```

해당 화장실에 존재하는 모든 Stall 개수다.

### 사용 가능한 칸

```text
available_stalls
```

다음 조건을 만족하는 Stall 개수다.

```text
occupied == false
```

### 사용 가능한 비데 칸

```text
available_bidet_stalls
```

다음 두 조건을 모두 만족하는 Stall 개수다.

```text
occupied == false
has_bidet == true
```

계산 가능한 값은 특별한 이유가 없다면 DB에 중복 저장하지 않는다.

해당 계산 로직은 API마다 중복 구현하지 말고 service 또는 repository 계층에서 공통으로 사용한다.

---

## 10. 이용 통계

센서 이벤트 데이터를 지속적으로 저장하고 이를 이용해 화장실별 이용 패턴을 계산한다.

초기 MVP에서는 AI나 머신러닝을 사용하지 않는다.

PostgreSQL에 저장된 실제 이용 데이터를 통계적으로 집계한다.

통계에 사용할 수 있는 기준은 다음과 같다.

- 요일
- 시간대
- 화장실
- 칸
- 비데 여부

예를 들어 다음과 같은 정보를 계산할 수 있다.

```text
월요일 12:00 ~ 13:00
본관 1층 화장실

평균 빈칸: 0.8칸
빈칸 존재 확률: 35%
평균 사용률이 아닌 실제 빈칸 데이터 기반 통계
```

```text
월요일 12:00 ~ 13:00
본관 2층 화장실

평균 빈칸: 2.4칸
빈칸 존재 확률: 82%
```

핵심 통계 값으로 다음을 사용할 수 있다.

```text
historical_availability_rate
```

의미:

> 해당 요일 및 시간대에 하나 이상의 빈칸이 존재했던 비율

필요한 경우:

```text
average_available_stalls
```

도 함께 계산할 수 있다.

통계 계산 로직은 다음과 같은 별도 service에 배치한다.

```text
backend/app/services/statistics.py
```

---

## 11. 통계 데이터 부족 처리

처음 서비스를 실행하면 과거 데이터가 없거나 매우 적을 수 있다.

따라서 통계가 없는 상태에서도 추천 기능은 반드시 정상적으로 동작해야 한다.

통계 데이터가 부족하면:

```text
실시간 빈칸
+
거리
```

만으로 추천한다.

통계를 사용할 수 있는 최소 표본 수를 설정할 수 있다.

예:

```text
MIN_STAT_SAMPLE_COUNT
```

표본 수가 이 기준보다 작다면 해당 통계는 추천 판단에 사용하지 않는다.

임의의 가짜 통계를 실제 데이터처럼 취급하지 않는다.

테스트 및 데모용 seed data는 명확하게 테스트 데이터로 구분한다.

---

## 12. 추천 알고리즘

초기 MVP에서는 AI 모델을 사용하지 않는다.

추천에는 다음 세 가지 정보를 사용한다.

```text
1. 현재 실시간 빈칸 상태
2. 현재 위치와의 거리
3. 같은 요일 / 비슷한 시간대의 과거 이용 통계
```

우선순위에서 가장 중요한 것은 **실시간 센서 상태**다.

과거 통계 때문에 현재 사용 가능한 화장실을 무시하거나 현재 만석인 화장실을 우선 추천해서는 안 된다.

---

### 일반 사용자

사용자가 비데를 필수로 요구하지 않는 경우 먼저:

```text
available_stalls > 0
```

인 화장실만 추천 후보로 선택한다.

예:

```text
화장실 A
거리 20m
현재 빈칸 0

화장실 B
거리 50m
현재 빈칸 2

화장실 C
거리 80m
현재 빈칸 3
```

A는 가장 가까워도 현재 사용할 수 없으므로 제외한다.

후보:

```text
B
C
```

이 후보 중 기본적으로 가까운 화장실을 우선한다.

---

### 통계 기반 보정

서로 거리가 비슷한 후보가 여러 개 존재한다면 과거 이용 통계를 사용한다.

예:

```text
화장실 B
거리: 50m
현재 빈칸: 1
해당 시간대 빈칸 존재 확률: 32%

화장실 C
거리: 60m
현재 빈칸: 2
해당 시간대 빈칸 존재 확률: 88%
```

두 화장실의 거리가 충분히 비슷하다면 통계적으로 빈칸이 유지될 가능성이 높은 C를 추천할 수 있다.

즉 통계는:

```text
"훨씬 먼 화장실을 추천하기 위한 기준"
```

이 아니라:

```text
"가까운 후보 여러 개 중 더 안정적으로 이용 가능한 화장실을 고르는 보조 기준"
```

으로 사용한다.

거리와 통계의 경계값은 코드 여러 곳에 하드코딩하지 않고 configurable constant 또는 설정값으로 관리한다.

예:

```text
RECOMMENDATION_DISTANCE_TOLERANCE
MIN_STAT_SAMPLE_COUNT
```

---

### 비데 필수 사용자

사용자가:

```text
bidet_required = true
```

를 선택한 경우 먼저:

```text
available_bidet_stalls > 0
```

인 화장실만 후보로 선택한다.

후보 중 가까운 화장실을 우선한다.

거리가 비슷한 화장실이 여러 개 존재하면 해당 요일 및 시간대의 과거 데이터를 사용하여 비데 칸을 실제로 이용할 가능성이 높은 화장실을 우선할 수 있다.

통계에는 필요한 경우 다음과 같은 값을 별도로 계산할 수 있다.

```text
historical_bidet_availability_rate
```

---

### 모든 화장실이 만석인 경우

모든 화장실에 사용 가능한 변기칸이 하나도 없다면:

```text
모든 restroom의
available_stalls == 0
```

기존 규칙대로 현재 위치에서 가장 가까운 화장실을 추천한다.

이 경우 통계 때문에 더 먼 화장실을 추천하지 않는다.

예:

```text
화장실 A
거리: 30m
빈칸: 0

화장실 B
거리: 80m
빈칸: 0

화장실 C
거리: 120m
빈칸: 0
```

추천:

```text
화장실 A
```

---

## 13. 추천 로직 요약

### 일반 사용자

```text
1. 현재 available_stalls > 0인 화장실 검색

2. 사용 가능한 화장실이 없다면
   → 가장 가까운 화장실 추천

3. 사용 가능한 화장실이 있다면
   → 가까운 화장실 후보 선정

4. 후보 간 거리가 충분히 비슷하고
   신뢰할 수 있는 과거 통계가 있다면
   → historical_availability_rate를 보조 기준으로 사용

5. 통계가 없거나 표본이 부족하면
   → 가장 가까운 후보 추천
```

### 비데 필수 사용자

```text
1. available_bidet_stalls > 0인 화장실 검색

2. 해당 화장실 중 가까운 후보 선정

3. 거리가 비슷하고 통계가 충분하다면
   → historical_bidet_availability_rate 사용

4. 통계가 부족하면
   → 가장 가까운 후보 추천

5. 모든 화장실의 모든 변기칸이 사용 중이면
   → 전체 화장실 중 가장 가까운 화장실 추천
```

추천 알고리즘은 반드시 Backend의 별도 service로 분리한다.

예:

```text
backend/app/services/recommendation.py
```

Flutter 내부에서 추천 알고리즘을 별도로 재구현하지 않는다.

---

## 14. 거리 계산

추천에 필요한 거리 계산은 별도의 service로 분리한다.

```text
Location Service
↓
각 화장실까지 거리 계산
↓
Recommendation Service
↓
실시간 상태 + 거리 + 통계 평가
↓
추천 화장실 반환
```

MVP에서는 단순한 `x`, `y` 좌표를 사용할 수 있다.

향후 다음 시스템으로 교체할 수 있도록 설계한다.

- GPS
- 실제 지도 API
- 실내 지도
- 층간 이동거리
- 계단/엘리베이터 이동거리

---

## 15. IoT 센서 처리

사용 센서:

```text
SW-520D Tilt Sensor
```

마이크로컨트롤러:

```text
Arduino UNO R4 WiFi
```

SW-520D의 상태를 읽어 잠금장치의 상태를 추정한다.

센서의 순간적인 흔들림 때문에 상태가 반복적으로 변경되지 않도록 debounce 또는 안정화 처리를 구현한다.

센서 값을 매 loop마다 서버에 계속 전송하지 않는다.

기본적으로:

```text
previous_state != current_state
```

인 경우에만 서버로 이벤트를 전송한다.

잠김:

```json
{
  "device_id": "stall-a-01",
  "occupied": true
}
```

잠금 해제:

```json
{
  "device_id": "stall-a-01",
  "occupied": false
}
```

서버 endpoint:

```http
POST /api/sensors/stall
```

센서 방향에 따라 실제 HIGH/LOW와 `occupied` 의미가 반대로 동작할 수 있으므로 해당 변환 로직을 명확하게 관리한다.

---

## 16. Realtime

센서 상태 변경 흐름:

```text
Arduino
↓
POST /api/sensors/stall
↓
FastAPI
↓
PostgreSQL Update
↓
SensorEvent 저장
↓
WebSocket Broadcast
↓
Flutter
```

WebSocket event 기본 형태:

```json
{
  "type": "stall.updated",
  "restroom_id": 1,
  "stall_id": 3,
  "occupied": true
}
```

Flutter는 가능한 경우 전체 데이터를 다시 가져오지 말고 변경된 화장실 및 칸 상태만 업데이트한다.

센서 상태 변경으로 기존 추천 결과가 유효하지 않게 된다면 추천도 다시 계산한다.

예:

```text
현재 추천: 본관 1층
↓
마지막 빈칸 사용 시작
↓
available_stalls = 0
↓
추천 재계산
↓
본관 2층 추천
```

---

## 17. API 기본 방향

기본 endpoint:

```text
GET  /api/health

GET  /api/restrooms

GET  /api/restrooms/{restroom_id}

GET  /api/restrooms/recommend

POST /api/sensors/stall

WS   /ws
```

세부 request / response schema는 반드시:

```text
docs/api.md
```

를 따른다.

추천 API 예:

```http
GET /api/restrooms/recommend?x=10&y=20&bidet_required=false
```

추천 결과에는 최소 다음 정보가 포함될 수 있다.

```json
{
  "id": 2,
  "name": "본관 2층",
  "building": "본관",
  "floor": 2,
  "distance": 42.5,
  "total_stalls": 5,
  "available_stalls": 2,
  "available_bidet_stalls": 1,
  "historical_availability_rate": 0.82,
  "statistics_used": true
}
```

통계가 사용되지 않았다면:

```json
{
  "statistics_used": false
}
```

처럼 Flutter에서 추천 근거를 구분할 수 있도록 한다.

---

## 18. 개발 우선순위

### Phase 1

```text
PostgreSQL Schema
+
Seed Data
+
Flutter Mock UI
```

### Phase 2

```text
FastAPI REST API
+
Flutter REST API 연결
```

### Phase 3

```text
WebSocket
+
실시간 앱 업데이트
```

### Phase 4

```text
Arduino UNO R4 WiFi
+
SW-520D
+
FastAPI Sensor API
```

### Phase 5

```text
거리 계산
+
기본 추천 알고리즘
+
비데 필수 옵션
```

### Phase 6

```text
SensorEvent 누적
+
시간대/요일별 통계
+
통계 기반 추천 보정
```

### Phase 7

```text
UI 개선
+
오류 처리
+
데모 안정화
```

AI 예측 모델이나 복잡한 지도 시스템은 핵심 MVP가 정상적으로 동작한 이후에만 고려한다.

---

## 19. 테스트용 환경

실제 Arduino가 없어도 Frontend와 Backend 개발이 가능해야 한다.

Backend에는 테스트용 화장실 및 센서 데이터를 제공한다.

센서 상태 변경은 HTTP 요청으로 시뮬레이션할 수 있어야 한다.

```bash
curl -X POST http://localhost:8000/api/sensors/stall \
  -H "Content-Type: application/json" \
  -d '{
    "device_id": "stall-a-01",
    "occupied": true
  }'
```

통계 기능 테스트를 위해 여러 날짜와 시간대의 테스트용 SensorEvent를 생성할 수 있도록 한다.

테스트 데이터는 실제 데이터와 명확하게 구분한다.

---

## 20. 최소 검증 시나리오

### 현재 빈칸 우선

```text
화장실 A
거리 20m
빈칸 0

화장실 B
거리 50m
빈칸 1

→ B 추천
```

### 가까운 후보 + 통계

```text
화장실 A
거리 50m
현재 빈칸 1
과거 빈칸 존재 확률 30%

화장실 B
거리 60m
현재 빈칸 1
과거 빈칸 존재 확률 85%

두 위치가 거리 허용 범위 안에 있다면

→ B 추천 가능
```

### 비데 필수

```text
화장실 A
거리 20m
일반 빈칸 2
빈 비데칸 0

화장실 B
거리 60m
빈 비데칸 1

→ B 추천
```

### 모든 화장실 만석

```text
모든 화장실
available_stalls = 0

→ 가장 가까운 화장실 추천
```

### 통계 없음

```text
과거 데이터 부족

→ 실시간 빈칸 + 거리만 사용
```

### 센서 변경

```text
SW-520D 상태 변경
↓
Arduino
↓
FastAPI
↓
PostgreSQL
↓
SensorEvent
↓
WebSocket
↓
Flutter
↓
필요 시 추천 변경
```

구현 후 가능한 범위에서 검증하되 과도한 회귀 테스트는 수행하지 않는다.

**회귀 테스트는 최대 4번으로 제한한다.**

---

## 21. 개발 완료 보고

각 작업이 끝날 때 다음을 간단히 정리한다.

```text
1. 구현한 기능
2. 수정한 파일
3. 새로 추가한 파일
4. 실행 방법
5. 테스트 결과
6. 다른 담당자가 알아야 할 변경 사항
7. 아직 구현되지 않은 부분
8. 발견된 문제
```

불필요하게 장황한 작업 보고서는 작성하지 않는다.

---

# 최우선 원칙

이 프로젝트는 해커톤 MVP다.

가장 중요한 것은 다음 전체 흐름이 실제로 동작하는 것이다.

```text
SW-520D
→ Arduino UNO R4 WiFi
→ FastAPI
→ PostgreSQL
→ WebSocket
→ Flutter
```

최종 데모에서는 다음 흐름을 실제로 보여줄 수 있어야 한다.

```text
잠금장치 움직임
↓
SW-520D 상태 변경
↓
Arduino가 FastAPI로 전송
↓
DB의 occupied 상태 변경
↓
SensorEvent 누적
↓
Flutter의 칸 상태 변경
↓
빈칸 수 변경
↓
추천 조건 재평가
↓
필요하면 추천 화장실 변경
```

추천의 우선순위는 항상 다음 원칙을 따른다.

```text
실시간 사용 가능 여부
>
거리
>
과거 통계
```

단, 서로 충분히 가까운 후보끼리는 과거 통계를 활용해 실제 이용 가능성이 더 높은 화장실을 선택할 수 있다.

통계 데이터가 부족하거나 신뢰하기 어려우면 통계를 사용하지 않고 실시간 상태와 거리만으로 추천한다.

복잡한 기능의 개수보다 이 전체 흐름이 안정적으로 동작하는 것을 최우선으로 한다.
