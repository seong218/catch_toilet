# 검증 기록

날짜: 2026-10-24

## 환경과 범위

- Windows 11 / PowerShell
- Flutter 3.47.8 stable, Dart 3.13.7
- SDK: app/.tools/flutter (Git 제외), 시스템 PATH 변경 없음
- 공식 템플릿으로 Android/iOS/Web 플랫폼 파일 생성, pubspec.lock 생성
- 모든 프로젝트 변경은 app/ 안에 한정, docs/api.md 및 기존 루트 파일 변경 없음

## 실행 결과

| 확인 | 결과 |
| --- | --- |
| dart format lib test tool | 완료 |
| flutter analyze | No issues found |
| flutter test --reporter expanded | 최종 30개 전부 통과 |
| Flutter Web debug 서버 | main.dart 컴파일 및 로컬 서버 기동 성공, 확인 후 종료 |
| flutter build web --dart-define=USE_MOCK=false | 성공, build/web 생성 |
| flutter build apk --debug | No Android SDK found로 중단 |
| iOS build/실기기 | Windows 환경으로 미수행 |
| 브라우저 시각 검수 | 도구의 localhost 접근 승인 거절로 미수행 |

회귀 테스트는 다음 **4회**만 실행했습니다.

| 회차 | 결과와 조치 |
| --- | --- |
| 1 | 16개 중 15개 통과. 화면 밖 추천 카드 tap을 수정. 별도 analyze에서 상세 Stall의 빈 배열 타입 오류를 수정 |
| 2 | 16개 중 15개 통과. 한국어 BackButton을 영문 tooltip으로 찾던 테스트를 수정 |
| 3 | 30개 중 26개 통과. 테스트 UTF-8 응답, Mock의 추천 내부 상세 호출 집계, 복귀 시 중복 refresh 경쟁 조건을 수정 |
| 4 | 30개 전부 통과 |

Web 첫 빌드에서 iOS adaptive UI의 Cupertino 아이콘 폰트 누락 경고가 발견되어
cupertino_icons를 추가했습니다. 이 변경은 아이콘 자산 의존성이며 애플리케이션 로직은
최종 통과한 테스트 이후 변경하지 않았습니다.
재빌드에서 CupertinoIcons.ttf 포함을 확인했고 누락 경고 없이 Web 빌드가 성공했습니다.
최종 format 확인은 36개 파일 변경 없음이며 Android manifest/iOS plist는 XML 구문 검증을 통과했습니다.

## 테스트 범위

| 파일 | 수 | 핵심 검증 |
| --- | ---: | --- |
| test/models_test.dart | 6 | 계약 숫자/null, 상세 집계, 잘못된 필드, 추가 필드, 통계 플래그, 이벤트 중복 대입 |
| test/controller_test.dart | 8 | REST/이벤트 경합, 늦은 응답, Mock·비데, 404, 실패·재시도, 위치 변경, dispose |
| test/api_service_test.dart | 5 | HTTP 경로·query·UTF-8, 404 사유, 잘못된 응답, timeout/503, URL 검증 |
| test/realtime_test.dart | 7 | 실제 loopback HTTP·WebSocket, 부분 갱신, 추천 재요청, 재연결, handshake 실패, 잘못된 이벤트, 미등록 칸, 앱 복귀 |
| test/widget_test.dart | 4 | 홈·비데·상세·지도·설정 탐색, 320px/큰 글자, 통계 문구, 좌표 입력 |

realtime_test.dart는 임시 loopback HttpServer와 WebSocket을 테스트 프로세스 안에서
실행하고 종료합니다. 프로젝트 Backend를 만들거나 수정하지 않았습니다.
실제 FastAPI·PostgreSQL·Arduino 통합 결과로 해석하면 안 됩니다.

## 남은 검증

- Android SDK 준비 후 APK 빌드와 에뮬레이터/실제 기기 실행
- macOS/Xcode에서 iOS Debug HTTP 및 Release HTTPS, 로컬 네트워크 권한 검증
- 실제 Backend 주소와 공유 좌표 설정 후 Sensor API → WebSocket → Flutter 전체 흐름 확인
- 실제 브라우저/기기 화면 시각 검수
