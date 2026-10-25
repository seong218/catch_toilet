# 추천 화면 인계

2026-10-25. `7.png`의 화면 구성과 `7_.png`의 반짝임 아이콘을 적용했습니다.
하단 네 번째 탭은 `추천`이며, 뒤로 가기는 지도로 이동합니다.

## 동작

- 성별과 비데 필수 설정을 기존 `AppController`와 공유합니다. 목록의 성별 선택도 동기화됩니다.
- `비데 설치 화장실` 스위치는 단순 설치 여부가 아니라 **사용 가능한 비데 칸 필수** 조건입니다.
- `추천 받기`를 누르면 GPS로 현재 위치를 먼저 확인하고, 확인된 위도·경도와 `gender`, `bidet_required`로 기존 추천 API를 호출합니다.
  처음에는 안내 문구를 표시하고, 요청 후 로딩·결과·오류를 표시합니다. 연속 요청은 로딩 중 막습니다.
- 한 번 추천을 받은 뒤에는 센서 이벤트와 성별·비데·위치 변경에 따른 기존 재조회 결과를 자동 반영합니다.
  최신 요청보다 늦게 도착한 이전 응답은 기존 Controller의 요청 번호로 무시합니다.
- 결과에 이름·층·빈칸·빈 비데 칸·직선거리·추천 근거를 표시합니다. `칸별 상태 보기`로 반환된 ID의 약도를 엽니다.
- 결과 아래에서 현재 기준 위치를 확인·변경합니다. 기본 안내는 `현재 GPS 위치로 추천`입니다.
  추천 버튼이나 위치 변경 화면에서 GPS를 요청하면 필요한 경우 OS 위치 권한을 요청합니다.
  GPS 모드에서 추천 버튼을 다시 누르면 새 위치를 읽고, 센서·조건 변경에 따른 자동 재조회는 마지막으로 확인된 좌표를 사용합니다.
- 권한 거부·위치 서비스 꺼짐·GPS 시간 초과에는 추천을 보류하고 오류·재시도·필요시 기기 설정 버튼을 표시합니다.
  실패한 요청을 이전 GPS나 본관 좌표로 대신 처리하지 않습니다. GPS 성공 또는 사용자의 명시적인 기준 위치 선택 후 재개합니다.
- `위치 변경 → 본관 기준 위치 사용 → 적용`을 직접 선택한 경우에만 본관 기준으로 추천합니다.
  초기 지도·시설 목록용 학교 좌표는 추천에 자동 사용하지 않으며, 위치 미선택 상태에서는 `적용` 버튼을 비활성화합니다.
  늦게 도착한 GPS 응답은 이후 수동 위치 선택이나 앱 종료를 덮어쓰지 않습니다.
- Mock 데이터는 데모임을 표시합니다. 실시간 연결이 확인되지 않으면 마지막 확인 정보라는 안내를 표시합니다.
- 작은 화면과 큰 글자는 스크롤·줄바꿈으로 처리합니다.

## 추천 기준과 API

추천은 `backend/app/services/recommendation.py`가 계산합니다. Flutter에 순위 계산을 추가하지 않았습니다.

1. 일반 요청은 현재 빈칸이 있는 곳을 후보로 선택합니다.
2. 비데 필수는 현재 빈 비데 칸이 있는 곳을 후보로 선택합니다.
3. 가까운 후보를 우선하며, 서버의 거리 허용 범위 안에서 통계가 충분할 때만 과거 이용 통계로 보정합니다.
4. 통계가 없거나 부족하면 빈칸과 거리만 사용합니다.
5. 모두 사용 중으로 관측된 경우 서버가 반환한 가까운 화장실을 표시하고 만석임을 안내합니다.
6. 센서 미관측으로 빈칸을 확인할 수 없거나 빈 비데 칸이 없는 경우, 서버의 404 사유를 구분해서 안내합니다.

`statistics_used=true`일 때만 통계 근거와 비율을 표시합니다. 비데 필수일 때는
`historical_bidet_availability_rate`, 일반 요청은 `historical_availability_rate`를 사용합니다.
이 값은 과거의 빈칸 존재 비율이며 미래 이용 가능성으로 표시하지 않습니다.

API 계약·Backend·데이터 모델·패키지·환경변수는 변경하지 않았습니다.
현재 조건을 만족하는 실측 데이터가 없을 때 임의의 추천이나 통계를 만들지 않습니다.

## 파일

추가:

- `lib/screens/recommendation_screen.dart`: 조건 입력, 추천 요청, 위치 변경 진입
- `lib/widgets/recommendation_result.dart`: 결과·로딩·오류·통계 표시와 상세 진입
- `lib/widgets/recommendation_tab_icon.dart`: `7_.png` 방향에 맞춘 반짝임 아이콘
- `test/recommendation_screen_test.dart`: 조건·결과·오류 복구·센서 갱신 검증
- 이 문서

수정: `lib/app.dart`, `lib/state/app_controller.dart`(미관측 안내 문구),
`test/widget_test.dart`, `test/info_screen_test.dart`, `README.md`, `docs/info_screen.md`.

## 실행과 빌드

기존 `app/.env.local`을 사용합니다. 재빌드에는 반드시 `--dart-define-from-file=.env.local`을 전달합니다.
환경 파일의 내용을 출력하거나 Git에 추가하지 않습니다.

```bash
cd app
BYPASS_PERMISSION_LOCATION_ALWAYS=1 .tools/flutter/bin/flutter run \
  -d <device-id> --dart-define-from-file=.env.local

BYPASS_PERMISSION_LOCATION_ALWAYS=1 .tools/flutter/bin/flutter build ios \
  --simulator --debug --no-pub --dart-define-from-file=.env.local
```

## GPS 기본 추천 변경 (2026-10-25)

수정: `lib/services/location_service.dart`, `lib/state/app_controller.dart`,
`lib/screens/recommendation_screen.dart`, `lib/widgets/recommendation_result.dart`, `lib/widgets/location_editor.dart`,
기존 위치·추천·Controller·WebSocket·위젯 테스트, `README.md`, 이 문서.
추가: `test/recommendation_location_test.dart`.

초기 위치는 지도 표시용이며 사용자 확인 상태와 별도로 관리합니다. 성별 변경은 위치를 선택한 것으로 취급하지 않습니다.
Backend 담당자가 변경할 API나 추천 계산은 없습니다. 새 패키지·환경변수는 추가하지 않았습니다.

검증: 정적 분석 통과, 위치·추천·Controller·HTTP/WebSocket·기존 탐색·지도 테스트 **52개 통과**(회귀 2회).
처음에는 수동 위치 선택 후 버튼 활성화를 기다리지 않던 기존 위젯 테스트 1개가 실패했으며, 다음 프레임을 기다리도록 수정했습니다.
새 검증은 GPS 대기 중 API 요청 차단·중복 탭 방지·좌표 전달·권한/서비스/시간 초과 오류·재시도·새 GPS 재조회,
필터/이벤트 자동 갱신, 수동 선택 우선, 과거 추천 응답 무시, 종료 후 GPS 응답 무시를 포함합니다.
위 명령의 `.env.local` 포함 iOS 시뮬레이터 빌드·설치·실행도 성공했습니다.
iPhone 18 Pro에서 첫 안내 `현재 GPS 위치로 추천`, 추천 버튼 후 `현재 GPS 위치` 적용과 실제 서버의 추천 결과 표시를 확인했습니다.
시뮬레이터 위치를 사용한 검증이며 실제 기기의 GPS 수신·Android 실행은 이번 범위에서 검증하지 않았습니다.
요청 범위에서 남은 구현이나 발견된 미해결 오류는 없습니다.

## 기존 추천 화면 검증

- 정적 분석: 통과.
- 기존 `.env.local`을 전달한 iOS 시뮬레이터 Debug 빌드: 성공.
- 추천 화면·기존 탐색·정보 화면·Controller·HTTP/WebSocket 테스트: **30개 통과**.
- 회귀 실행: 총 3회. 초기 실패는 이전 더보기 화면의 테스트 기대 문구와 스크롤 후 레이아웃 대기를 수정해 해결했습니다.
- 추천 전용 테스트 7개에서 성별·비데·좌표 전달, 로딩, 결과 ID, 404·503 복구, 만석,
  통계 플래그·비데 전용 지표, 센서 이벤트 후 목록 재조회 없는 추천 변경, 320px·1.6배 글자를 검증했습니다.
- HTTP/WebSocket 자동 테스트는 로컬 계약 fixture이며 실제 Arduino 센서 흐름의 검증은 아닙니다.
- iPhone 18 Pro 시뮬레이터에서 추천 폼·비데 스위치·실제 API 요청을 확인했습니다.
  현재 서버의 센서 미관측 응답에 따라 추천 대신 미확인 안내가 표시되는 것도 확인했습니다.

남은 검증은 실제 iPhone·Android 기기와 Arduino 센서 전체 흐름입니다.
기존 범위대로 GPS 직선거리를 사용하며 보행 시간·예약·새로운 예측 모델은 제공하지 않습니다.
