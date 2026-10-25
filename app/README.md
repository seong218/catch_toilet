# Catchy Toilet · Flutter

지도 탭은 카카오맵을 사용합니다. 실제 지도 표시 전 [네이티브 앱 키 및 무료 사용 설정](docs/KAKAO_MAP_SETUP.md)을 완료하세요. 설정이 없으면 층별 목록을 안내합니다.

iOS Runner 종료 충돌 수정본을 `third_party/kakao_map_sdk`에 포함합니다. 다른 PC에서도 이 폴더와 `pubspec.yaml`/lock을 함께 사용하세요. [원인·수정·검증 기록](docs/IOS_CRASH_FIX.md)을 참고하세요.

하단 `지도 · 목록 · 정보 · 추천` 탭과 화장실 상세 화면을 갖춘 Flutter MVP입니다.
앱 시작 시 `1.png`를 기준으로 한 시작 화면을 표시합니다.
연한 파란 배경, `logo.png` 위치 핀과 원형 그래픽, `CATCH TOILET` 제목, 소개 문구와 `시작하기 →` 버튼으로 구성됩니다.
로고 원본은 `assets/images/branding/logo.png`로 포함하며, 원본 비율로 그립니다. 흰 바탕은 화면에서 multiply 방식으로 원형 배경과 합성합니다.
`시작하기`를 누르면 디미고 지도 탭으로 이동하고 REST 조회와 WebSocket 연결을 시작합니다.
백그라운드 복귀 시 현재 화면을 유지하며, 앱을 새로 시작하면 시작 화면부터 표시합니다.
목록은 화장실별 카드와 시설 필터를,
정보는 `5.png`를 기준으로 원본 `정보1~4.png`를 잘라 표시한 카드·주제 필터를, `추천`은 성별·비데 조건에 맞는 화장실과 추천 근거를 제공합니다.
정보 카드 또는 상단 주제를 누르면 상단 제목·주제 버튼과 하단 탭을 유지한 채 가운데 영역만 `6.png` 형태의 본문으로 바뀝니다. `전체`·뒤로 가기로 카드 목록에 돌아오며, 다른 하단 탭을 이용한 뒤에도 읽던 주제·스크롤 위치를 유지합니다.
[정보 화면 구현·검증·콘텐츠 인계](docs/info_screen.md)를 참고하세요.
기본 실행은 실제 REST/WebSocket 모드입니다. 디미고 본관 시설 데이터와 GPS 위치를 사용합니다.
현재 층 입력은 없고, 설정의 연결 정보도 제거했습니다. [시설·GPS·iPhone 실행 인계](../docs/DIMIGO_GPS.md)를 먼저 확인하세요.
데이터 계약은 [docs/api.md](../docs/api.md)를 따릅니다.

## 추천 화면

`7.png`에 맞춰 하단 네 번째 탭을 `추천`으로 변경했습니다. 성별 선택, 비데 필수 스위치,
검정 `추천 받기` 버튼과 둥근 흰색 결과 영역을 제공합니다. 결과의 `칸별 상태 보기`를 누르면 해당 화장실 약도를 엽니다.
추천 탭에는 `7_.png`의 반짝임 모양 아이콘을 적용했습니다.
추천 버튼을 누르면 기본적으로 GPS로 현재 위치를 먼저 가져옵니다. GPS 확인 전이나 실패 시에는 본관 좌표로 추천하지 않습니다.
현재 기준 위치는 결과 아래에서 확인·변경할 수 있으며, 본관 기준은 사용자가 직접 선택하고 적용했을 때만 사용합니다.

추천은 기존 Backend API에서 실시간 빈칸 → 거리 → 가까운 후보 간 과거 통계 순으로 계산합니다.
통계가 부족하면 실시간 빈칸·거리만 사용하며, 비데 필수는 빈 비데 칸을 요구합니다.
모두 사용 중이면 가까운 화장실과 만석 안내를 표시하고, 센서 미확인·빈 비데 없음·서버 오류는 각각 안내합니다.
센서 이벤트, 위치·성별·비데 변경에 따라 추천을 다시 요청합니다. 결과 영역은 `추천 받기`를 누른 뒤 표시됩니다.
실행·변경 파일·검증 범위는 [추천 화면 인계](docs/recommendation.md)를 참고하세요.

## 화장실 목록 화면

`3_.png`를 기준으로 연한 파란 배경, 가운데 두 줄 필터(남자·여자 / 비데·장애인),
테두리 없는 흰색 카드, 상태 배지와 이동 화살표를 표시합니다. 목록 탭의 하단 바 높이도 시안에 맞췄습니다.
목록의 뒤로 가기는 지도 탭으로 이동합니다. 목록 하단의 `지금 추천하는 화장실`, 추천 카드·설정·로딩·오류 영역은 제거했습니다.
위치 변경은 지도와 추천에서 사용할 수 있습니다.

- 남자·여자: 기존 `gender` 조회 조건과 추천의 성별 설정을 공유합니다.
- 비데: `available_bidet_stalls > 0`인 화장실만 표시합니다. 일반 빈칸이 있어도 비데 칸이 모두 사용 중이면 제외합니다.
- 장애인: `occupied == false && is_accessible == true`인 칸이 있는 화장실만 표시합니다.
  목록의 `accessible_stalls`는 설치 수이므로 필터를 켜면 해당 시설의 기존 상세 API를 조회해 칸별 상태를 확인합니다.
  이후에는 캐시된 상세를 WebSocket 이벤트로 갱신하며, 새로고침·재연결·성별/위치 변경 시 상세도 다시 동기화합니다.
- 두 필터를 함께 켜면 **같은 빈칸**이 장애인 칸이면서 비데가 있어야 합니다. 상태나 해당 시설 여부가 미확인인 칸은 제외합니다.
  조회 중에는 진행 표시, 실패 시 재시도를 제공하며 조회 실패를 빈 결과로 표시하지 않습니다.
  목록 필터는 추천의 `bidet_required`와 별개이며 추천 알고리즘은 Backend에 유지합니다.
- 상태: 빈칸 비율 20% 이하는 빨강 `혼잡`, 70% 이상은 초록 `여유`, 그 사이는 주황 `보통`으로 표시합니다.
  혼잡 카드의 보조 문구는 시안처럼 사용 중인 칸 수이며, 나머지 관측된 카드는 사용 가능한 칸 수입니다.
  미관측 칸이 있으면 회색 `미확인`, 등록된 칸이 없으면 회색 `미등록`이며, 일부 미관측 칸도 수를 따로 안내합니다.
  이 색상은 화면 표현 기준으로만 사용합니다.
- 시안의 도보 시간은 API에서 제공하지 않아 서버의 직선거리로 표시합니다. 거리가 null이면 `거리 미확인`입니다.
- 기존 WebSocket 집계값으로 카드가 갱신됩니다. 로딩, 연결 단절, 재시도, 빈 목록과 필터 결과 없음도 처리합니다.
- 카드 선택은 해당 화장실 ID의 약도를 엽니다. `4_.png`를 기준으로 층별 실제 칸·비데·장애인 정보와 실시간 사용 상태를 표시합니다. [약도 구현·검증·실행 안내](docs/restroom_detail.md)를 참고하세요.

이번 빈칸 필터 수정(2026-10-25): `lib/screens/home_screen.dart`, `lib/state/app_controller.dart`,
`test/restroom_list_test.dart`, 이 문서. 추가 파일은 없습니다.
API 계약, Backend, 추천 로직, 패키지와 환경변수는 변경하지 않았습니다.

검증: 정적 분석 및 전체 Flutter 테스트 68개 통과(회귀 1회), iOS 시뮬레이터 Debug 빌드 성공.
목록 테스트에서는 일반 칸만 비어 있는 경우의 비데 제외, 장애인 칸의 사용 중·미확인 제외,
두 조건을 같은 칸에서 충족하는지, 실시간 제외/복귀, 조회 지연·오류 재시도, 누락 이벤트 후 새로고침을 확인했습니다.
기존 실행 명령과 환경 설정을 그대로 사용합니다. 실제 센서·Arduino 및 실기기 검증은 이번 작업에 포함되지 않습니다.

## PC 테스트 데이터

실제 API 모드에서 PC의 랜덤·수동 상태를 받아 지도·목록·약도·추천을 갱신한다.
[시뮬레이션 명령](../docs/SIMULATION.md)을 사용한다. 추천은 계속 Backend가 계산한다.
2026-10-25 사용자 요청으로 지도·목록·상세·층별 목록·추천의 상시 상태 안내 영역과 전용 여백을 제거했다.
`실시간 상태를 반영하고 있어요` 등 연결·데모·테스트 안내가 표시되던 공용 `ConnectionStatus` 위젯도 삭제했다.
조회 오류·재시도 및 로딩 표시는 유지한다.
데이터의 시뮬레이션 구분과 PC 제어 기능은 유지한다.
수정: `home_screen.dart`, `map_screen.dart`, `restroom_detail_screen.dart`, `map_restroom_sheet.dart`,
`recommendation_result.dart`, `widget_test.dart`, 이 문서. 추가 파일 없음. 실행 방법은 동일하다.
검증: 관련 화면·시뮬레이션 테스트 28개, 정적 분석 통과(회귀 1회). 실행 중인 iPhone 시뮬레이터에 hot reload 반영.

## 실행

현재 작업 PC에는 Flutter 3.47.8 / Dart 3.13.7을 app/.tools/flutter에 준비했습니다.
SDK·빌드 산출물은 Git에서 제외됩니다. 시스템 PATH는 변경하지 않았습니다.

```powershell
cd C:\Users\user\git\app
# 이 PowerShell 세션에서만 SDK 경로 적용
$env:Path = "$PWD\.tools\flutter\bin;$env:Path"
flutter pub get
flutter devices
# 지도 설정을 마친 .env.local을 함께 전달합니다.
flutter run -d <device-id> --dart-define-from-file=.env.local
```

Flutter SDK가 이미 PATH에 있는 다른 PC에서는 경로 추가를 생략합니다.
Android/iOS/Web 플랫폼 파일과 pubspec.lock은 생성되어 있으므로 다시 프로젝트를 만들 필요가 없습니다.
tool/bootstrap.dart는 없는 플랫폼 폴더만 공식 템플릿으로 생성하는 초기화 도구입니다.
일반 실행에는 필요하지 않습니다.

`.env.local`은 Git에 포함되지 않으므로 새 환경에서는 위의 지도 설정 안내에 따라 준비합니다.
`학교 지도를 준비 중이에요`는 지도 키 없이 실행됐다는 뜻이며 사용량 한도 초과가 아닙니다.
이 경우 `.env.local`을 전달해 앱을 완전히 다시 실행합니다. Hot reload만으로 실행 옵션은 바뀌지 않습니다.

`--dart-define=USE_MOCK=true`로 선택한 Mock 모드는 Backend 없이 실행됩니다. 일반 추천은 본관 1층, 비데 필수 추천은 본관 2층으로
정해진 예시 응답입니다. 실제 추천 알고리즘이나 과거 통계를 Flutter에서 계산하지 않습니다.
기준 위치 변경 시 데모 표시 거리만 갱신되며 추천 ID는 고정됩니다. 화면에 데모임을 표시합니다.

## 실제 Backend 연결

```powershell
# Android emulator에서 개발 PC의 Backend 사용
flutter run -d <android-device-id> --dart-define-from-file=.env.local --dart-define=USE_MOCK=false --dart-define=API_BASE_URL=http://10.0.2.2:8000

# 같은 Wi-Fi의 실제 스마트폰: PC의 실제 LAN 주소로 바꿉니다.
flutter run -d <device-id> --dart-define-from-file=.env.local --dart-define=USE_MOCK=false --dart-define=API_BASE_URL=http://192.168.0.10:8000

# 로컬 Web 개발
flutter run -d chrome --web-port=8787 --dart-define=USE_MOCK=false --dart-define=API_BASE_URL=http://localhost:8000
```

API_BASE_URL은 lib/config/app_config.dart 한 곳에서 읽으며 /ws 주소와 ws/wss를 자동으로 만듭니다.
.env.example은 참고용입니다. Flutter가 .env 파일을 자동 로딩하지 않습니다.
실제 모드에서 서버 연결이 실패해도 Mock으로 자동 전환하지 않습니다.

사용 API:

| API | 사용 |
| --- | --- |
| GET /api/health | Backend/DB 상태 확인 |
| GET /api/restrooms?latitude=…&longitude=…&gender=male | 화장실 목록, 서버 거리와 집계값 |
| GET /api/restrooms/{id}?latitude=…&longitude=… | 칸별 사용·비데 상태 |
| GET /api/restrooms/recommend?latitude=…&longitude=…&gender=male&bidet_required=… | Backend가 선택한 추천과 통계 사용 여부 |
| WS /ws | 전체 화장실의 stall.updated 수신 |

GPS·성별·미관측 상태·시설 정보 계약을 Backend와 함께 반영했습니다.
Web에서는 Backend가 Flutter 개발 origin에 대한 CORS를 허용해야 합니다.

## 동작과 복구

- 추천·목록·상세·지도는 같은 ChangeNotifier 상태를 사용합니다.
- 비데 조건과 기준 위치를 바꾸면 서버에 추천을 다시 요청합니다.
- 현재 추천 이외의 화장실 이벤트도 추천에 반영합니다. 연속 이벤트는 250ms 모아 재요청합니다.
- 이벤트 집계값을 대입하고, 캐시된 상세의 해당 칸만 갱신합니다. 같은 이벤트로 중복 증감하지 않습니다.
- 알 수 없는 화장실·칸, 캐시 집계 불일치는 해당 상세를 재조회합니다.
- REST 조회 중 이벤트가 겹친 화장실은 이전 응답을 덮어쓰지 않고 상세를 다시 조회합니다.
- 늦게 도착한 이전 위치·설정·이벤트 이전 추천 응답은 무시합니다.
- WebSocket 연결을 시작한 후 목록·추천·열린 상세를 동기화합니다.
- 연결 실패 시 1~30초 간격으로 재연결합니다. 앱이 백그라운드로 가면 중단하고 복귀 시 재연결·동기화합니다.
- 알 수 없는 이벤트 type은 무시합니다. 잘못된 stall.updated는 연결 복구와 REST 동기화를 유도합니다.
- 비데 조건 불충족 404에서는 조건을 유지하고 안내합니다. 이후 이벤트 수신도 계속합니다.
- 전체 만석의 추천 200은 서버 결과를 그대로 표시하고 즉시 사용할 수 없음을 안내합니다.
- 서버 오류 시 기존 목록을 유지하고 재시도 버튼을 제공합니다. 단절·동기화 중에는 실시간이라고 표시하지 않습니다.

MVP 계약에는 이벤트 버전/cursor가 없으므로 화면과 DB의 원자적 일치는 보장할 수 없습니다.
이벤트가 계속 발생하면 해당 상세의 재조회가 이어질 수 있습니다.

## 플랫폼 설정

- Android: INTERNET·COARSE/FINE_LOCATION 권한을 선언했습니다. 로컬 HTTP는 Debug/Profile에서 허용합니다.
- iOS: 사용 중 위치 권한과 로컬 네트워크 목적 설명을 추가했습니다. Swift Package Manager 빌드 시 `BYPASS_PERMISSION_LOCATION_ALWAYS=1`을 지정합니다. Debug에만 Info-Debug.plist를 사용해 개발 HTTP를 허용합니다.
- Release: HTTPS/WSS 서버를 사용합니다. 배포 서명·Bundle ID는 배포 담당자가 준비합니다.
- Android release는 현재 Flutter 템플릿의 데모용 debug 서명 설정입니다. 스토어 배포 전 교체해야 합니다.
- 지도 탭은 카카오맵·등록 화장실 검색·GPS 이동·건물별 층별 안내를 제공합니다. 본관·신관·우정학사·학봉관·체육관에 마커를 하나씩 표시하며, 미등록 건물에는 준비 중 안내를 제공합니다. 현위치는 작은 파란 점과 옅은 원으로 표시합니다. 실내 층간/보행 경로는 제공하지 않습니다.
- 기준 위치와 비데 옵션은 세션 메모리에 보관합니다.

## 구조와 의존성

```text
lib/
  app.dart           앱·로케일·navigation·lifecycle
  config/            공통 테마와 실행 설정
  models/            snake_case 변환, 계약 검증, 이벤트 대입
  repositories/      Mock / API 데이터 소스
  services/          HTTP, WebSocket, GPS 위치
  state/             상태 관리, 응답 순서, 실시간 동기화
  screens/           시작, 지도, 목록(Home), 정보, 추천, 상세
  widgets/           카드, 칸 상태, 연결 표시, 위치 입력
test/                모델·상태·위젯·HTTP·WebSocket 검증
```

런타임 패키지: http 1.6.0, web_socket_channel 3.0.3, geolocator 14.1.2, cupertino_icons 1.0.9.
Cupertino 아이콘은 iOS adaptive UI가 사용하는 폰트입니다.
Flutter SDK의 flutter_localizations를 사용합니다.
개발 의존성은 flutter_test와 flutter_lints이며 별도 상태 관리 패키지는 없습니다.

## 앱 아이콘

2026-10-25: `assets/images/branding/logo.png`를 기준으로 iOS AppIcon 15개,
Android `mipmap-*/ic_launcher.png` 5개, 웹 아이콘·favicon 5개를 교체했습니다.
원본 비율을 유지해 흰 정사각형 배경 중앙에 배치했으며, 웹 maskable 아이콘에는 여백을 더 두었습니다.
기존 플랫폼 설정과 파일명은 유지했습니다.

재생성 도구 `tool/generate_app_icons.py`를 추가했습니다. macOS 기본 `sips`와 Python 표준 라이브러리만 사용합니다.
`app/`에서 다음과 같이 실행합니다.

```bash
python3 tool/generate_app_icons.py
BYPASS_PERMISSION_LOCATION_ALWAYS=1 .tools/flutter/bin/flutter build ios --simulator --debug --no-pub --dart-define-from-file=.env.local
```

25개 이미지의 규격·불투명 여부와 원본 보존을 확인했고, 위 iOS 빌드와 설치·실행이 성공했습니다.
iPhone 18 Pro 시뮬레이터 홈 화면에서 새 앱 아이콘을 확인했습니다.
이미지 변경이므로 회귀 테스트는 추가 실행하지 않았습니다. Android는 SDK 미설치로 빌드하지 않았으며 웹 설치·실제 기기는 미검증입니다.
API·추천 로직·환경변수·패키지 변경은 없습니다. 요청 범위의 미구현 사항이나 남은 오류는 없습니다.

## 시작 화면 검증 기록

2026-10-25 로고 교체: 원본 `logo.png`를 `assets/images/branding/logo.png`로 추가하고
`lib/widgets/welcome_artwork.dart`, `pubspec.yaml`, 이 문서를 수정했습니다.
정적 분석·기존 위젯 테스트 4개(회귀 1회)와 `.env.local`을 전달한 iOS 시뮬레이터 빌드가 통과했습니다.
iPhone 18 Pro 시뮬레이터에서 새 로고와 기존 시작 화면 배치를 확인했습니다.
원본 파일과 앱 자산의 바이트가 동일함을 확인했습니다. API 변경·새 패키지·추가 환경변수는 없으며 요청 범위의 미구현 사항이나 발견된 오류는 없습니다.
실행은 위의 `flutter run ... --dart-define-from-file=.env.local` 명령을 사용합니다. 실제 기기는 이번에 검증하지 않았습니다.

이전 `1.png` 시작 화면으로 교체한 뒤 정적 분석이 통과했습니다.
`flutter test --no-pub test/widget_test.dart test/info_screen_test.dart test/restroom_list_test.dart`의 9개 테스트가 통과했습니다(회귀 1회).
시작 전 연결 보류, 연속 탭 시 중복 시작 방지, 시작 전후 백그라운드 복귀, 새 실행 시 시작 화면 표시,
기존 네 탭·비데·상세·위치·정보 글과 320px·1.6배 글자에서 버튼까지 스크롤할 수 있는 것을 확인했습니다.
기존 `.env.local` 설정을 유지한 iOS 시뮬레이터 Debug 빌드도 성공했습니다.
iPhone 18 Pro 시뮬레이터에서 배경·로고·문구·버튼을 시각 검수하고 `시작하기`를 눌러 기존 지도 화면으로 이동하는 것을 확인했습니다.
실제 iPhone·Android 기기는 이번 작업에서 검증하지 않았습니다.

시작 화면은 `lib/screens/welcome_screen.dart`, 배경과 로고 그래픽은 `lib/widgets/welcome_artwork.dart`에 분리했습니다.
이전 `school_selection_screen.dart`는 교체했습니다. `lib/app.dart`, 위 테스트 3개, 이 문서와 `docs/info_screen.md`의 진입 안내를 수정했습니다.
새 패키지·이미지 파일·환경변수 없이 구현했으며 API 계약과 추천 로직은 그대로입니다.
현재 디미고 한 곳을 사용하며, 시작 완료 상태의 영구 저장은 구현하지 않았습니다. 이번 테스트에서 발견된 앱 오류는 없습니다.

macOS에서 서버 없이 화면을 확인하려면 다음과 같이 실행합니다.

```bash
cd app
.tools/flutter/bin/flutter run -d <device-id> --dart-define=USE_MOCK=true
```

이전 작업에서는 Flutter 33개 테스트와 analyze가 통과했고, macOS에서 iPhone 18 Pro 시뮬레이터 빌드·실제 API 연결·GPS 위치 적용을 확인했습니다.
최신 시설 데이터는 [디미고 인계](../docs/DIMIGO_GPS.md)를 참고하세요.

## 초기 Flutter 작업 검증 기록 (이전 환경)

- dart format: 완료
- flutter analyze: 오류·경고 없음
- flutter test: 30개 통과, 회귀 테스트 총 4회(한도 준수)
- Web debug 서버: 컴파일·기동 확인
- flutter build web --dart-define=USE_MOCK=false: 성공
- Android APK: SDK 미설치로 빌드 중단
- iOS: Windows 환경으로 빌드·기기 실행 미검증
- 브라우저 시각 검수: localhost 접근 승인 거절로 미수행

HTTP/WebSocket 테스트는 test/realtime_test.dart의 loopback 계약 fixture를 사용합니다.
실제 FastAPI/PostgreSQL/Arduino와 연결한 검증은 아직 아닙니다.
검증 범위와 실행별 결과는 [VERIFICATION.md](VERIFICATION.md)에 기록했습니다.

```powershell
dart format lib test tool
flutter analyze
flutter test
flutter build web --dart-define=USE_MOCK=false
# Android SDK 준비 후
flutter build apk --debug
```
