# Catchy Toilet · Flutter

Home, 화장실 상세, 지도·기준 위치, 설정을 갖춘 Flutter MVP입니다.
기본 실행은 Mock 모드이며, 실행 옵션으로 실제 REST/WebSocket Repository를 선택합니다.
변경 범위는 app/입니다. 데이터 계약은 [docs/api.md](../docs/api.md)를 그대로 따릅니다.

## 실행

현재 작업 PC에는 Flutter 3.47.8 / Dart 3.13.7을 app/.tools/flutter에 준비했습니다.
SDK·빌드 산출물은 Git에서 제외됩니다. 시스템 PATH는 변경하지 않았습니다.

```powershell
cd C:\Users\user\git\app
# 이 PowerShell 세션에서만 SDK 경로 적용
$env:Path = "$PWD\.tools\flutter\bin;$env:Path"
flutter pub get
flutter devices
flutter run -d <device-id>
```

Flutter SDK가 이미 PATH에 있는 다른 PC에서는 경로 추가를 생략합니다.
Android/iOS/Web 플랫폼 파일과 pubspec.lock은 생성되어 있으므로 다시 프로젝트를 만들 필요가 없습니다.
tool/bootstrap.dart는 없는 플랫폼 폴더만 공식 템플릿으로 생성하는 초기화 도구입니다.
일반 실행에는 필요하지 않습니다.

기본 Mock 모드는 Backend 없이 실행됩니다. 일반 추천은 본관 1층, 비데 필수 추천은 본관 2층으로
정해진 예시 응답입니다. 실제 추천 알고리즘이나 과거 통계를 Flutter에서 계산하지 않습니다.
기준 위치 변경 시 데모 표시 거리만 갱신되며 추천 ID는 고정됩니다. 화면에 데모임을 표시합니다.

## 실제 Backend 연결

```powershell
# Android emulator에서 개발 PC의 Backend 사용
flutter run -d <android-device-id> --dart-define=USE_MOCK=false --dart-define=API_BASE_URL=http://10.0.2.2:8000

# 같은 Wi-Fi의 실제 스마트폰: PC의 실제 LAN 주소로 바꿉니다.
flutter run -d <device-id> --dart-define=USE_MOCK=false --dart-define=API_BASE_URL=http://192.168.0.10:8000

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
| GET /api/restrooms?x=…&y=… | 화장실 목록, 서버 거리와 집계값 |
| GET /api/restrooms/{id}?x=…&y=… | 칸별 사용·비데 상태 |
| GET /api/restrooms/recommend?x=…&y=…&bidet_required=… | Backend가 선택한 추천과 통계 사용 여부 |
| WS /ws | 전체 화장실의 stall.updated 수신 |

Backend schema 변경 요청은 없습니다. 서버 주소, 공유 좌표계 원점과 seed 좌표는 담당자끼리
맞춰야 합니다. Web에서는 Backend가 Flutter 개발 origin에 대한 CORS를 허용해야 합니다.
이 작업에서는 Backend·문서 계약을 변경하지 않았습니다.

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

- Android: INTERNET 권한을 선언했습니다. 로컬 HTTP는 Debug/Profile에서 허용합니다.
- iOS: 로컬 네트워크 목적 설명을 추가했습니다. Debug에만 Info-Debug.plist를 사용해 개발 HTTP를 허용합니다.
- Release: HTTPS/WSS 서버를 사용합니다. 배포 서명·Bundle ID·최종 아이콘은 배포 담당자가 준비합니다.
- Android release는 현재 Flutter 템플릿의 데모용 debug 서명 설정입니다. 스토어 배포 전 교체해야 합니다.
- 지도는 x/y 안내도이며 GPS와 실내 층간/보행 경로를 제공하지 않습니다.
- 기준 위치와 비데 옵션은 세션 메모리에 보관합니다.

## 구조와 의존성

```text
lib/
  app.dart           앱·로케일·navigation·lifecycle
  config/            공통 테마와 실행 설정
  models/            snake_case 변환, 계약 검증, 이벤트 대입
  repositories/      Mock / API 데이터 소스
  services/          HTTP, WebSocket, 기준 위치, 지도 투영
  state/             상태 관리, 응답 순서, 실시간 동기화
  screens/           Home, 상세, 지도, 설정
  widgets/           카드, 칸 상태, 연결 표시, 위치 입력
test/                모델·상태·위젯·HTTP·WebSocket 검증
```

런타임 패키지: http 1.6.0, web_socket_channel 3.0.3, cupertino_icons 1.0.9.
Cupertino 아이콘은 iOS adaptive UI가 사용하는 폰트입니다.
Flutter SDK의 flutter_localizations를 사용합니다.
개발 의존성은 flutter_test와 flutter_lints이며 별도 상태 관리 패키지는 없습니다.

## 검증 결과

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
