# Catchy Toilet API Contract — MVP

Flutter, Backend, IoT 담당자가 병렬 개발할 때 사용하는 공통 계약이다. 추천 정책은 [`AGENTS.md`](../AGENTS.md)를 따르며, 이 문서는 HTTP 및 WebSocket에서 주고받는 데이터와 경계 상황을 정의한다. 아래 예시는 설명용 데이터이며 실제 이용 통계가 아니다.

## 1. 공통 규칙

### 주소와 데이터 형식

- 개발 REST 주소 예시: `http://localhost:8000`. 실제 호스트는 실행 환경에서 설정한다. 모바일 기기의 `localhost`는 개발 PC를 가리키지 않는다.
- WebSocket 주소 예시: `ws://localhost:8000/ws`. HTTPS 환경에서는 `wss://`를 사용한다.
- REST의 정상 응답과 이 문서에서 정의한 오류 응답은 UTF-8 JSON이다. Sensor 요청은 `Content-Type: application/json`을 사용한다.
- JSON 필드 이름은 `snake_case`다. `stall.updated`는 필드 이름이 아닌 이벤트 종류 값이다.
- 성공 응답은 아래에 정의한 객체 또는 배열 자체를 반환한다. `data`, `result` 등의 공통 wrapper를 추가하지 않는다.
- 별도로 선택이라고 명시한 검증 오류 부가 필드를 제외하고, 응답 표에 정의한 필드는 모두 필수다. Nullable 필드도 키를 생략하지 않고 값이 없으면 JSON `null`을 반환한다. 배열은 `null` 대신 `[]`를 사용한다.
- `integer`는 JSON 정수, `number`는 유한한 JSON 숫자, `boolean`은 JSON `true`/`false`다. `NaN`, 무한대는 허용하지 않는다. Flutter에서 `number`는 정수 표기로 올 수도 있으므로 `num`으로 읽어 `double`로 변환한다.
- Path/Query 값은 URL 문자열로 전송하되 각 표의 타입으로 검증한다. 선택 Query는 값이 없으면 생략한다. 빈 문자열이나 문자열 `null`은 값 없음으로 취급하지 않는다.
- MVP에는 페이지네이션, 사용자 로그인, 인증 헤더, WebSocket 구독 메시지를 요구하지 않는다.
- 응답의 알 수 없는 추가 필드는 무시할 수 있어야 한다. 기존 필드의 삭제·타입·의미 변경은 Flutter와 Backend가 합의한 뒤 이 문서를 먼저 갱신한다.

### 좌표와 거리

- `x`, `y`는 서버에 등록된 화장실과 사용자가 공유하는 평면 좌표이며 단위는 미터(`m`)다. GPS 위도·경도가 아니다. 음수와 `0`도 유효하다.
- `distance`는 요청한 사용자 좌표에서 화장실까지의 미터 단위 직선거리다. MVP에서는 Backend의 Location Service가 `sqrt((restroom.x - x)^2 + (restroom.y - y)^2)`로 계산한다.
- 층간 이동, 계단, 엘리베이터, 실제 보행 경로는 이 거리 계산에 포함하지 않는다. `floor`는 표시 정보다.
- 응답 숫자의 소수 자릿수는 고정하지 않는다. 표시용 반올림은 Flutter에서 수행한다.
- 목록·상세의 선택 Query `x`, `y`는 둘 다 보내거나 둘 다 생략한다. 둘 다 생략하면 `distance: null`, 하나만 보내면 `422`다. 추천 API는 둘 다 필수다.

### Endpoint 요약

| Method | Path | 정상 응답 | 목적 |
| --- | --- | --- | --- |
| GET | `/api/health` | `200 HealthResponse` | API 및 DB 연결 확인 |
| GET | `/api/restrooms` | `200 Restroom[]` | 화장실 목록과 현재 빈칸 조회 |
| GET | `/api/restrooms/{restroom_id}` | `200 RestroomDetail` | 화장실 및 개별 칸 조회 |
| GET | `/api/restrooms/recommend` | `200 Recommendation` | 조건에 맞는 화장실 한 곳 추천 |
| POST | `/api/sensors/stall` | `200 SensorUpdateResponse` | 센서의 현재 사용 상태 반영 |
| WS | `/ws` | `101` 연결 전환 후 JSON 이벤트 | 전체 화장실 상태 변경 수신 |

Backend는 정적 경로 `/api/restrooms/recommend`를 `/{restroom_id}`보다 먼저 매칭해야 한다. `recommend`를 정수 ID로 해석하여 `422`를 반환해서는 안 된다.

## 2. 공통 응답 모델

### Stall

| 필드 | Type | Nullable | 의미 / 제약 |
| --- | --- | --- | --- |
| `id` | integer | 아니오 | 전체 서비스에서 유일한 칸 ID, `> 0` |
| `stall_number` | integer | 아니오 | 화장실 내부 표시 번호, `> 0`, 해당 화장실 안에서 유일 |
| `occupied` | boolean | 아니오 | `true`: 사용 중, `false`: 빈칸 |
| `has_bidet` | boolean | 아니오 | 비데 설치 여부 |

```json
{
  "id": 1,
  "stall_number": 1,
  "occupied": false,
  "has_bidet": true
}
```

`stall_number`는 배열 인덱스가 아니다. WebSocket의 `stall_id`는 이 모델의 `id`와 대응한다.

### Restroom

| 필드 | Type | Nullable | 의미 / 제약 |
| --- | --- | --- | --- |
| `id` | integer | 아니오 | 화장실 ID, `> 0` |
| `name` | string | 아니오 | 표시 이름, 빈 문자열 불가 |
| `building` | string | 아니오 | 건물 이름, 빈 문자열 불가 |
| `floor` | integer | 아니오 | 층. 예: `1`은 지상 1층, `-1`은 지하 1층 |
| `x` | number | 아니오 | 화장실의 X 좌표, 미터 |
| `y` | number | 아니오 | 화장실의 Y 좌표, 미터 |
| `distance` | number | 예 | 사용자와의 거리, `>= 0`. 목록·상세에서 사용자 좌표 생략 시 `null` |
| `total_stalls` | integer | 아니오 | 화장실에 등록된 모든 칸 수, `>= 0` |
| `available_stalls` | integer | 아니오 | `occupied == false`인 칸 수 |
| `available_bidet_stalls` | integer | 아니오 | `occupied == false && has_bidet == true`인 칸 수 |

항상 `0 <= available_bidet_stalls <= available_stalls <= total_stalls`를 만족한다. 집계값은 동일한 현재 칸 상태에서 계산하며 API마다 다른 기준을 적용하지 않는다. 등록된 칸이 없는 화장실은 세 집계값 모두 `0`이다.

```json
{
  "id": 1,
  "name": "본관 1층",
  "building": "본관",
  "floor": 1,
  "x": 10.0,
  "y": 20.0,
  "distance": null,
  "total_stalls": 3,
  "available_stalls": 2,
  "available_bidet_stalls": 1
}
```

### RestroomDetail

`Restroom`의 모든 필드와 다음 필드를 **하나의 평평한 객체**로 반환한다. 별도의 `restroom` wrapper는 없다.

| 추가 필드 | Type | Nullable | 의미 / 제약 |
| --- | --- | --- | --- |
| `stalls` | Stall[] | 아니오 | 해당 화장실의 전체 칸, `stall_number` 오름차순. 칸이 없으면 `[]` |

`total_stalls == stalls.length`이며 두 빈칸 집계값은 반환된 `stalls`와 일치해야 한다. 전체 JSON 예시는 상세 API에 있다.

### Recommendation

`Restroom`의 모든 필드를 포함하는 평평한 객체다. `distance`는 아래 정의로 강화하며 통계 필드를 추가한다. `stalls`는 포함하지 않는다.

| 추가 / 재정의 필드 | Type | Nullable | 의미 / 제약 |
| --- | --- | --- | --- |
| `distance` | number | 아니오 | 요청 좌표에서 추천 화장실까지의 거리, 미터, `>= 0` |
| `statistics_used` | boolean | 아니오 | 이번 추천에서 과거 통계를 후보 비교의 보조 기준으로 실제 사용했는지 여부 |
| `historical_availability_rate` | number | 예 | 추천된 화장실에서 같은 요일·해당 시간대에 하나 이상의 빈칸이 존재했던 비율, `0.0`~`1.0` |
| `historical_bidet_availability_rate` | number | 예 | 같은 기준으로 하나 이상의 빈 비데 칸이 존재했던 비율, `0.0`~`1.0` |

통계 계약:

- 두 비율은 **추천된 화장실**의 값이며, `0.82`는 `82%`다. 실제 빈칸 존재 여부를 과거 관측 기간에 걸쳐 집계한 값으로, 단순 센서 이벤트 중 `occupied == false`의 비율이나 평균 사용률의 역수가 아니다.
- 통계가 없거나 `MIN_STAT_SAMPLE_COUNT` 미만이거나 신뢰할 수 없으면 해당 비율은 `null`이다. 두 필드는 각각 독립적으로 `null`일 수 있다. `0.0`은 충분한 관측에서 빈칸이 없었다는 유효한 값이다.
- Backend의 현재 시각을 기준으로 요일과 시간대를 선택한다. MVP의 기준 시간대는 `Asia/Seoul`이다. 클라이언트는 시각이나 과거 통계를 요청에 보내지 않는다.
- `statistics_used: true`이면 일반 요청에서는 `historical_availability_rate`, 비데 필수 요청에서는 `historical_bidet_availability_rate`가 반드시 non-null이다. 통계가 실제 후보 비교에 쓰였다면 결과가 가장 가까운 화장실과 같아도 `true`일 수 있다.
- `statistics_used: false`여도 조회 가능한 통계는 non-null로 반환할 수 있다. 예를 들어 후보가 한 곳뿐이거나 전체 만석으로 거리만 사용한 경우다. 통계 필드의 존재만으로 통계 추천이라고 표시하지 않는다.
- 거리 허용 범위, 최소 표본 수 등은 Backend 설정으로 관리한다. Flutter는 이 값이나 추천 알고리즘을 재구현하지 않는다.

## 3. 오류 응답

### 처리 가능한 오류

FastAPI의 기본 `HTTPException` 응답 형태를 사용한다.

| 필드 | Type | Nullable | 의미 |
| --- | --- | --- | --- |
| `detail` | string | 아니오 | 오류 설명 |

예: `404 Not Found`.

```json
{
  "detail": "Restroom not found"
}
```

예: DB에 접근할 수 없을 때 `503 Service Unavailable`.

```json
{
  "detail": "Database unavailable"
}
```

### 입력 검증 오류

Path, Query, JSON body의 누락·타입·범위 오류 및 잘못된 JSON은 `422 Unprocessable Entity`로 응답한다. FastAPI 기본 검증 오류 배열을 유지한다.

| 필드 | Type | Nullable | 필수 여부 / 의미 |
| --- | --- | --- | --- |
| `detail` | ValidationError[] | 아니오 | 필수, 하나 이상의 검증 오류 |
| `detail[].loc` | (string 또는 integer)[] | 아니오 | 필수, 오류 위치. 예: `["query", "x"]`, `["body", "occupied"]` |
| `detail[].msg` | string | 아니오 | 필수, 검증 오류 설명 |
| `detail[].type` | string | 아니오 | 필수, 검증 오류 종류 |
| `detail[].input` | JSON value | 예 | 선택, 검증에 실패한 입력값 |
| `detail[].ctx` | object | 아니오 | 선택, 추가 검증 정보 |

Query `x` 누락 예시:

```json
{
  "detail": [
    {
      "type": "missing",
      "loc": ["query", "x"],
      "msg": "Field required",
      "input": null
    }
  ]
}
```

검증 오류의 `msg`, `type`, 선택 부가 필드는 FastAPI/Pydantic 버전에 따라 달라질 수 있다. Flutter는 문자열 `detail`과 배열 `detail`을 모두 처리하고 검증 메시지의 정확한 문구에 의존하지 않는다. `x`, `y` 중 하나만 보낸 오류도 위 배열 형식으로 누락된 Query를 가리킨다.

예상하지 못한 서버 오류는 `500`, 미지원 HTTP 메서드는 `405`가 될 수 있다. 처리되지 않은 예외나 프록시·네트워크 오류에서는 이 JSON 형태를 보장하지 않으므로 클라이언트는 상태 코드와 일반 오류 메시지로 처리한다. 불필요한 custom error wrapper는 추가하지 않는다.

## 4. GET /api/health

목적: API가 요청을 처리하고 PostgreSQL에 접근할 수 있는지 확인한다. 개별 센서나 WebSocket 클라이언트 연결 상태까지 검사한다는 의미는 아니다.

- Path parameter: 없음.
- Query parameter: 없음.
- Request body: 없음.

```http
GET /api/health
```

성공: `200 OK`, `HealthResponse` 객체.

| 필드 | Type | Nullable | 의미 |
| --- | --- | --- | --- |
| `status` | string | 아니오 | 고정값 `"ok"` |

```json
{
  "status": "ok"
}
```

주요 오류: `503`, `{"detail":"Database unavailable"}`. 공통 오류 형식을 따른다.

## 5. GET /api/restrooms

목적: 등록된 전체 화장실의 현재 빈칸, 비데 빈칸 및 선택적으로 사용자와의 거리를 조회한다. MVP에는 검색 반경·건물 필터·페이지네이션이 없다.

- Path parameter: 없음.
- Request body: 없음.

| Query | Type | 필수 | Nullable | 기본값 / 제약 |
| --- | --- | --- | --- | --- |
| `x` | number | 아니오 | 아니오 | 생략 가능. 사용자 X 좌표. `y`와 함께 제공 |
| `y` | number | 아니오 | 아니오 | 생략 가능. 사용자 Y 좌표. `x`와 함께 제공 |

성공: `200 OK`, `Restroom[]`. 좌표를 보내면 `distance`, `id` 순으로 오름차순 정렬하고, 생략하면 `id` 오름차순으로 정렬한다. 사용 중인 화장실도 목록에 포함한다. 각 항목은 `stalls`나 통계 필드를 포함하지 않는다.

```http
GET /api/restrooms?x=10&y=20
```

```json
[
  {
    "id": 1,
    "name": "본관 1층",
    "building": "본관",
    "floor": 1,
    "x": 10.0,
    "y": 20.0,
    "distance": 0.0,
    "total_stalls": 3,
    "available_stalls": 2,
    "available_bidet_stalls": 1
  },
  {
    "id": 2,
    "name": "본관 2층",
    "building": "본관",
    "floor": 2,
    "x": 40.0,
    "y": 60.0,
    "distance": 50.0,
    "total_stalls": 5,
    "available_stalls": 2,
    "available_bidet_stalls": 1
  }
]
```

등록된 화장실이 없으면 `404`가 아닌 `200 OK`와 다음 body를 반환한다.

```json
[]
```

| 주요 오류 | 조건 | Body |
| --- | --- | --- |
| `422` | 좌표 타입·유한성 오류 또는 `x`, `y` 중 하나만 제공 | 공통 검증 오류 배열 |
| `503` | DB 접근 불가 | `{"detail":"Database unavailable"}` |

## 6. GET /api/restrooms/{restroom_id}

목적: 화장실 정보와 모든 칸의 사용 상태 및 비데 설치 여부를 조회한다.

| Path | Type | 필수 | Nullable | 제약 |
| --- | --- | --- | --- | --- |
| `restroom_id` | integer | 예 | 아니오 | `> 0` |

| Query | Type | 필수 | Nullable | 기본값 / 제약 |
| --- | --- | --- | --- | --- |
| `x` | number | 아니오 | 아니오 | 생략 가능. 사용자 X 좌표. `y`와 함께 제공 |
| `y` | number | 아니오 | 아니오 | 생략 가능. 사용자 Y 좌표. `x`와 함께 제공 |

Request body: 없음. 성공: `200 OK`, `RestroomDetail` 객체.

```http
GET /api/restrooms/1
```

```json
{
  "id": 1,
  "name": "본관 1층",
  "building": "본관",
  "floor": 1,
  "x": 10.0,
  "y": 20.0,
  "distance": null,
  "total_stalls": 3,
  "available_stalls": 2,
  "available_bidet_stalls": 1,
  "stalls": [
    {"id": 1, "stall_number": 1, "occupied": false, "has_bidet": true},
    {"id": 2, "stall_number": 2, "occupied": true, "has_bidet": false},
    {"id": 3, "stall_number": 3, "occupied": false, "has_bidet": false}
  ]
}
```

| 주요 오류 | 조건 | Body |
| --- | --- | --- |
| `404` | 유효한 형식의 ID지만 해당 화장실 없음 | `{"detail":"Restroom not found"}` |
| `422` | ID가 양의 정수가 아님, 좌표 오류 또는 좌표 중 하나만 제공 | 공통 검증 오류 배열 |
| `503` | DB 접근 불가 | `{"detail":"Database unavailable"}` |

## 7. GET /api/restrooms/recommend

목적: 사용자 위치와 비데 필수 조건으로 추천 화장실 **한 곳**을 반환한다. Backend가 실시간 사용 가능 여부, 거리, 신뢰할 수 있는 과거 통계를 평가한다.

- Path parameter: 없음.
- Request body: 없음.

| Query | Type | 필수 | Nullable | 기본값 / 제약 |
| --- | --- | --- | --- | --- |
| `x` | number | 예 | 아니오 | 사용자 X 좌표, 기본값 없음 |
| `y` | number | 예 | 아니오 | 사용자 Y 좌표, 기본값 없음 |
| `bidet_required` | boolean | 아니오 | 아니오 | 기본값 `false`. 클라이언트는 `true` 또는 `false` 문자열로 전송 |

성공: `200 OK`, `Recommendation` 객체. 배열이나 nullable 최상위 응답을 사용하지 않는다. `id`는 추천된 화장실 ID다.

```http
GET /api/restrooms/recommend?x=10&y=20&bidet_required=false
```

충분한 통계를 보조 기준으로 사용한 응답 예시:

```json
{
  "id": 2,
  "name": "본관 2층",
  "building": "본관",
  "floor": 2,
  "x": 40.0,
  "y": 60.0,
  "distance": 50.0,
  "total_stalls": 5,
  "available_stalls": 2,
  "available_bidet_stalls": 1,
  "statistics_used": true,
  "historical_availability_rate": 0.82,
  "historical_bidet_availability_rate": 0.65
}
```

각 Endpoint 예시는 독립적인 시점의 응답이다. 위 예시는 이 화장실과 비슷한 거리에 다른 사용 가능한 후보가 있어 통계를 비교한 상황이다.

통계가 없거나 표본이 부족한 경우에도 성공하며, 실시간 상태와 거리로 선택한다.

```json
{
  "id": 1,
  "name": "본관 1층",
  "building": "본관",
  "floor": 1,
  "x": 10.0,
  "y": 20.0,
  "distance": 0.0,
  "total_stalls": 3,
  "available_stalls": 2,
  "available_bidet_stalls": 1,
  "statistics_used": false,
  "historical_availability_rate": null,
  "historical_bidet_availability_rate": null
}
```

### 후보가 없는 경우와 만석 처리

아래 순서로 분기한다. 세부 거리·통계 보정 정책은 `AGENTS.md`를 따른다.

| 조건 | 결과 |
| --- | --- |
| 등록된 화장실이 없음 | `404`, `{"detail":"No restrooms found"}` |
| 등록된 화장실은 있지만 모든 화장실의 `available_stalls == 0` | `bidet_required`와 관계없이 전체에서 가장 가까운 화장실을 `200`으로 반환. 통계는 사용하지 않으며 `statistics_used: false` |
| 일반 요청이고 빈칸이 있음 | `available_stalls > 0`인 후보에서 선택 |
| 비데 필수이고 빈 비데 칸이 있음 | `available_bidet_stalls > 0`인 후보에서 선택 |
| 비데 필수이고 일반 빈칸은 있지만 빈 비데 칸은 어디에도 없음 | `404`, `{"detail":"No available bidet stalls"}`. 비데 필수 조건을 임의로 해제하지 않음 |

가장 가까운 후보가 같은 거리이면 `id`가 작은 화장실을 선택한다. 통계로 비교한 뒤에도 우선순위가 같으면 거리, `id` 순서로 결정한다.

전체 만석 fallback 예시 (`bidet_required=true`여도 동일한 규칙):

```json
{
  "id": 1,
  "name": "본관 1층",
  "building": "본관",
  "floor": 1,
  "x": 10.0,
  "y": 20.0,
  "distance": 0.0,
  "total_stalls": 3,
  "available_stalls": 0,
  "available_bidet_stalls": 0,
  "statistics_used": false,
  "historical_availability_rate": null,
  "historical_bidet_availability_rate": null
}
```

`200`은 즉시 사용 가능하거나 예약되었다는 보장이 아니다. Flutter는 `available_stalls == 0`이면 만석 안내를 표시한다. 비데 조건 불충족 `404`에서는 비데 조건에 맞는 빈칸이 없다고 안내한다.

| 주요 오류 | 조건 | Body |
| --- | --- | --- |
| `404` | 화장실 미등록 | `{"detail":"No restrooms found"}` |
| `404` | 일반 빈칸은 있으나 빈 비데 칸이 없는 비데 필수 요청 | `{"detail":"No available bidet stalls"}` |
| `422` | 필수 좌표 누락, 좌표 타입·유한성 오류, 해석할 수 없는 boolean | 공통 검증 오류 배열 |
| `503` | DB 접근 불가 | `{"detail":"Database unavailable"}` |

## 8. POST /api/sensors/stall

목적: 등록된 센서가 보고한 현재 사용 상태를 연결된 칸에 반영한다. 새로운 센서나 칸을 생성하는 API가 아니다.

- Path parameter: 없음.
- Query parameter: 없음.
- Request body: 필수 JSON 객체.

| Body 필드 | Type | 필수 | Nullable | 제약 |
| --- | --- | --- | --- | --- |
| `device_id` | string | 예 | 아니오 | 사전 등록된 센서 식별자. 빈 문자열·공백만 있는 문자열 불가. 대소문자를 구분하며 등록값과 정확히 일치해야 함 |
| `occupied` | boolean | 예 | 아니오 | 안정화 및 센서 방향 변환을 마친 논리 상태. JSON boolean만 허용하며 `0`, `1`, `"true"` 등으로 대체하지 않음 |

```http
POST /api/sensors/stall
Content-Type: application/json
```

```json
{
  "device_id": "stall-a-01",
  "occupied": true
}
```

성공: `200 OK`, `SensorUpdateResponse` 객체. 신규 상태 적용과 같은 상태 재전송 모두 `200`이다.

| 응답 필드 | Type | Nullable | 의미 |
| --- | --- | --- | --- |
| `success` | boolean | 아니오 | 정상 처리 시 항상 `true`. 실패는 `success: false` 대신 오류 status와 공통 오류 body 사용 |
| `changed` | boolean | 아니오 | 요청 처리 직전 DB 상태와 비교하여 실제로 칸 상태가 변경되었으면 `true` |

실제 상태가 변경된 경우:

```json
{
  "success": true,
  "changed": true
}
```

이미 같은 상태인 경우:

```json
{
  "success": true,
  "changed": false
}
```

처리 및 재전송 계약:

1. `device_id`로 센서를 찾고 활성 여부, 화장실·칸 연결 관계를 검증한다.
2. 상태가 다르면 칸의 `occupied`와 `updated_at`을 갱신하고 해당 상태 변경의 `SensorEvent`를 같은 DB 트랜잭션에 저장한다. 동시 요청도 같은 칸의 변경 판단과 저장이 순차적으로 처리되어야 한다.
3. 커밋된 변경에 대해서만 `stall.updated`를 방송한다. 저장 실패 시 칸과 이벤트 모두 반영하지 않고 성공 응답이나 이벤트를 보내지 않는다.
4. 상태가 같으면 `changed: false`다. `updated_at`을 변경하거나 중복 `SensorEvent`를 추가하거나 WebSocket 이벤트를 보내지 않는다.
5. 성공은 DB 반영 여부를 뜻하며 모든 WebSocket 수신자의 수신 완료를 보장하지 않는다. 커밋 후 방송 실패 때문에 이미 저장한 변경을 롤백하지 않는다. 이벤트와 HTTP 응답 중 클라이언트에 먼저 도착하는 것은 보장하지 않는다.
6. 요청에는 발생 시각이나 순번이 없다. 상태는 서버에서 처리된 순서로 반영한다. IoT는 같은 기기의 요청을 겹쳐 보내지 않고, 재전송 시 이미 더 최신 상태가 있으면 오래된 상태 대신 현재 안정화된 상태를 보낸다. 동일 상태의 연속 재전송은 변경을 중복 생성하지 않지만 오래된 요청의 임의 재생까지 방지하는 계약은 아니다.

| 주요 오류 | 조건 | Body |
| --- | --- | --- |
| `404` | 등록되지 않은 `device_id` | `{"detail":"Sensor not found"}` |
| `409` | 센서가 `active == false` | `{"detail":"Sensor is inactive"}` |
| `409` | 연결된 칸·화장실이 없거나 소속 관계가 불일치 | `{"detail":"Sensor mapping is invalid"}` |
| `422` | 필드 누락, null, 잘못된 타입, 비어 있는 식별자 또는 JSON 구문 오류 | 공통 검증 오류 배열 |
| `503` | DB 접근 불가 | `{"detail":"Database unavailable"}` |

위 표의 `404`·`409`·`422`·`503` 오류에서는 칸 상태 변경과 `SensorEvent` 추가가 없어야 한다. 응답을 받지 못한 네트워크 단절이나 타임아웃은 DB 미반영을 뜻하지 않는다. 이때는 현재 안정화된 상태를 재전송하고 성공 응답을 확인한다.

## 9. WS /ws

목적: 연결된 Flutter 클라이언트에 전체 화장실의 칸 상태 변경을 전달한다.

- 연결 주소: `ws://<host>:8000/ws` 또는 배포 환경의 `wss://<host>/ws`.
- Path/Query parameter: 없음.
- Request body 및 구독 메시지: 없음. 연결하면 모든 화장실의 이후 변경을 수신한다.
- 성공 연결: HTTP `101 Switching Protocols`.
- 메시지: 서버에서 클라이언트로 보내는 UTF-8 JSON text frame. 프레임 하나에 이벤트 객체 하나를 담는다.
- 연결 직후 목록 snapshot이나 과거 이벤트를 자동 전송하지 않는다. 초기 데이터는 REST로 조회한다.
- MVP에 클라이언트에서 보내야 할 application 메시지나 JSON ping/pong은 없다. 서버는 수신한 application 메시지를 상태 변경 명령으로 처리하지 않는다.

### stall.updated

다음 필드는 모두 필수이며 non-null이다. 최소 식별·상태 필드에 **변경 후 집계값**을 더해 목록을 추가 요청 없이 갱신할 수 있게 한다.

| 필드 | Type | Nullable | 의미 / 제약 |
| --- | --- | --- | --- |
| `type` | string | 아니오 | 고정값 `"stall.updated"` |
| `restroom_id` | integer | 아니오 | 변경된 칸이 속한 화장실 ID, `> 0` |
| `stall_id` | integer | 아니오 | 변경된 `Stall.id`, `> 0` |
| `occupied` | boolean | 아니오 | 변경 후 사용 상태 |
| `total_stalls` | integer | 아니오 | 변경 반영 후 해당 화장실의 전체 칸 수 |
| `available_stalls` | integer | 아니오 | 변경 반영 후 해당 화장실의 빈칸 수 |
| `available_bidet_stalls` | integer | 아니오 | 변경 반영 후 해당 화장실의 빈 비데 칸 수 |

집계값은 `Restroom`과 같은 제약을 따르며, 해당 변경을 반영한 동일한 DB 상태를 나타낸다. 예를 들어 상세 API 예시의 3번 칸이 사용 중으로 바뀌면:

```json
{
  "type": "stall.updated",
  "restroom_id": 1,
  "stall_id": 3,
  "occupied": true,
  "total_stalls": 3,
  "available_stalls": 1,
  "available_bidet_stalls": 1
}
```

### Flutter 동기화 및 추천 갱신

- 목록은 `restroom_id`로 찾아 세 집계값을 **대입**한다. `occupied`를 보고 무조건 `+1`/`-1`하지 않는다. 같은 이벤트를 반복 적용해도 집계가 틀어지면 안 된다.
- 상세가 캐시되어 있으면 `stall_id`로 해당 칸의 `occupied`도 대입한다. `has_bidet`는 기존 값을 유지한다.
- 알 수 없는 화장실·칸을 받으면 해당 화장실의 상세 API로 재조회한다. 모든 이벤트마다 전체 목록을 재조회하지 않는다.
- 추천은 Backend에서 다시 계산한다. Flutter는 상태 변경 후 현재 좌표와 비데 설정으로 추천 API를 재요청한다. 다른 화장실이 비는 경우에도 더 적절한 추천이 생길 수 있으므로 현재 추천 화장실의 이벤트만 감시하지 않는다.
- 연속 이벤트는 추천 재요청을 짧게 모아서 처리할 수 있다. 이전 요청의 늦은 응답이 더 최신 위치·설정 또는 더 나중 요청의 결과를 덮지 않도록 한다. 추천 `404` 후에도 이벤트 수신은 계속한다.

### 연결 순서, 전달 범위와 복구

- 정상 연결 동안 Backend는 같은 화장실의 이벤트를 커밋 순서대로 방송한다. 집계값도 그 순서와 일치해야 한다.
- MVP 이벤트에는 버전·재개 cursor·수신 확인·영구 재전송 기능이 없다. 연결 단절 중의 이벤트 복구와 REST snapshot과 이벤트 사이의 원자적 경계는 보장하지 않는다.
- 초기 연결 및 재연결 시 WebSocket을 연결해 이벤트 수신을 시작하고 REST 목록, 현재 열린 상세, 추천을 동기화한다. 조회 중 이벤트가 겹친 화장실은 해당 상세를 다시 조회해 상태를 맞춘다. 경계를 판별할 버전이 없으므로 겹친 이벤트의 버퍼를 snapshot 뒤에 무조건 덧씌우지 않는다.
- 앱이 백그라운드에서 복귀하거나 상태 불일치를 감지하면 같은 방식으로 REST 재동기화를 수행한다. 연결되지 않은 동안의 화면 상태를 실시간이라고 보장하지 않는다.
- 클라이언트는 알 수 없는 이벤트 `type`을 무시하고 연결을 유지한다.
- 연결 전 서버 접근 불가, 네트워크 실패, handshake 실패를 처리한다. 연결 후 정상 종료는 `1000`, 서버 내부 오류 종료는 `1011`을 사용할 수 있다. 클라이언트가 관측하는 `1006`은 비정상 단절을 뜻하며 서버가 보내는 close frame이 아니다.
- 연결 후 실패에는 REST 오류 body나 HTTP status를 기대하지 않는다. close/disconnect를 처리하고 재시도 간격을 두어 재연결한 뒤 REST로 복구한다.

## 10. 구현 전 맞출 운영 값

위 요청·응답 스키마, null 처리, 후보 없음 처리와 Sensor 중복 처리 방식은 이 문서의 확정 계약이다. 다음 값은 데이터 준비 및 Backend 설정 시 정하고 담당자끼리 공유한다.

| 아직 결정할 값 | 영향 |
| --- | --- |
| 개발·데모 서버의 실제 호스트와 공유 좌표계 원점, 기준 위치 및 seed 좌표 | Flutter와 IoT의 접속 주소 및 올바른 거리 계산. 단위는 미터로 확정 |
| `RECOMMENDATION_DISTANCE_TOLERANCE`의 실제 값 | 서로 가까운 후보로 묶는 범위. 단위는 미터 |
| `MIN_STAT_SAMPLE_COUNT`, 표본의 정의, 시간대 구간 크기와 과거 집계 기간 | 통계 신뢰도 및 통계 사용 시점. 기준 시간대는 `Asia/Seoul`로 확정 |

통계 설정·데이터가 준비되지 않은 초기 구현은 두 비율을 `null`, `statistics_used`를 `false`로 반환하고 실시간 상태와 거리로 추천한다. 이 경우에도 나머지 API 계약은 동일하게 구현한다.
