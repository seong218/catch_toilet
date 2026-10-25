# iOS Runner 종료 충돌 수정

2026-10-25. 앱을 다시 열 때 보이던 `Runner 응용 프로그램이 예기치 않게 종료되었습니다` 알림을 조사했다.
로컬에 남아 있던 Runner 충돌 기록 6개 모두 카카오맵 네이티브 뷰를 해제하는 같은 경로에서 발생했다.

## 원인과 수정

Flutter 엔진 종료 중 `KakaoMapView.deinit`이 `onMapDestroy` 메시지를 보냈고,
이미 정지한 엔진의 `FlutterEngine.sendOnChannel` assertion으로 SIGABRT가 발생했다.
카카오맵 네이티브 뷰를 해제할 때에는 메시지를 보내지 않고 지도 자원만 정리하도록 수정했다.
앱이 명시적으로 `finish()`를 호출할 때의 Dart 알림과 중복 정리 방지는 유지한다.
네이티브 뷰 해제 자체에서 받던 Dart destroy 알림은 생략한다. 현재 앱은 이 알림을 사용하지 않는다.

전역 Pub 캐시 대신 공식 배포된 `kakao_map_sdk` 1.3.1 소스를 프로젝트에 포함했다.
출처, 원본 해시, 라이선스와 변경한 Swift 파일 2개는
[LOCAL_PATCH.md](../third_party/kakao_map_sdk/LOCAL_PATCH.md)에 기록했다.
Android 및 Dart 런타임 코드는 원본 그대로다.

수정 파일:

- `pubspec.yaml`, `pubspec.lock`: 같은 버전의 로컬 패치 의존성 사용.
- `analysis_options.yaml`: 앱의 엄격한 lint 대상에서 포함한 외부 패키지 제외.
- `README.md`: 적용 안내 링크 추가.

추가 파일:

- `third_party/kakao_map_sdk/`: 패키지 소스, 원본 라이선스 및 패치 기록.
- `docs/IOS_CRASH_FIX.md`: 이 인계 문서.

## 실행과 인계

`third_party/kakao_map_sdk/`를 의존성 설정과 함께 Git에 포함해야 한다.
`.env.local`, `.tools/`, `build/`, 생성된 SPM 폴더는 포함하지 않는다.
기존 카카오 키와 Backend 실행 설정은 그대로 사용하며 API 계약 변경은 없다.

`app/`에서 현재 PC의 iPhone 시뮬레이터로 실행:

```bash
.tools/flutter/bin/flutter pub get
BYPASS_PERMISSION_LOCATION_ALWAYS=1 .tools/flutter/bin/flutter run \
  -d D07AE7D6-FDAB-4632-BAE1-2A72E3F21A39 \
  --dart-define-from-file=.env.local \
  --dart-define=USE_MOCK=false \
  --dart-define=API_BASE_URL=http://localhost:8000
```

다른 PC에서는 `flutter devices`로 기기 ID를 확인하고 자신의 Flutter 경로를 사용한다.
Swift 수정은 hot reload로 적용되지 않으므로 기존 실행을 종료하고 새로 빌드한다.
패키지를 업데이트할 때는 이 패치가 포함되었는지 확인한 뒤 로컬 의존성을 제거한다.

## 검증 결과

- Flutter 전체 테스트 68개 통과(전체 회귀 실행 1회).
- `flutter analyze` 통과.
- iOS 시뮬레이터 Debug 빌드·설치 성공.
- iPhone 18 Pro / iOS 27.0에서 지도 진입 → 앱 전환 화면에서 종료 → 재실행을 3회 확인.
- 재실행마다 시작 화면과 지도 화면 진입 성공. 새 Runner 충돌 기록 0개.
- 생성된 iOS SPM 패키지가 프로젝트 내 수정본을 참조하는 것을 확인.

실기기 및 Android 빌드 검증은 이번 작업에 포함하지 않았다.
현재 시뮬레이터에는 수정 빌드가 설치되어 있다.
