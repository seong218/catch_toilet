# 서버 배포와 iPhone 실행

실제 서버 주소, SSH 별칭, 배포 경로, 기기 ID, Apple Team ID는 저장소에 기록하지 않는다.
서버 접속은 각자의 SSH 설정을 사용하고, 아래 명령은 서버의 저장소 루트에서 실행한다.

## 서버 실행

`backend/.env.example`을 참고해 서버 전용 `backend/.env`를 준비한다.
DB 관리자·앱 계정 비밀번호와 시뮬레이션 키는 서버에서 별도로 생성하고 파일 권한을 600으로 제한한다.
외부 연결을 허용할 인터페이스와 포트는 이 파일의 `API_BIND_HOST`, `API_PORT`로 지정한다.
`.env`는 Git에서 제외된다.

Docker Compose 2.24.4 이상에서 다음 명령을 실행한다.

```bash
docker compose --env-file backend/.env \
  -f database/docker-compose.yml -f database/docker-compose.server.yml \
  up -d --build --wait
```

서버용 override는 PostgreSQL 호스트 포트 공개를 제거하고 DB/API에 `unless-stopped` 재시작 정책을 적용한다.
DB는 기존 named volume에 저장된다. `down -v`는 데이터를 삭제하므로 사용하지 않는다.
시설 최초 등록 및 갱신:

```bash
docker compose --env-file backend/.env \
  -f database/docker-compose.yml -f database/docker-compose.server.yml \
  run --rm migrate python -m app.seed
```

설정한 API 주소의 `/api/health`, `/api/restrooms`, `/docs`와 WebSocket `/ws`로 연결을 확인한다.
루트 `/`에는 웹페이지를 제공하지 않으므로 404가 정상이다.

## PC에서 서버의 칸 상태 지정

SSH로 서버에 접속한 뒤 저장소 루트에서 실행한다. 시뮬레이션을 사용할 때는 서버의
`backend/.env`에 `ENABLE_SIMULATION=true`와 별도 `SIMULATION_API_KEY`를 설정한다.
인증 키는 컨테이너 환경에서 읽으며, 외부 HTTP로 관리 키를 보내지 않는다.

```bash
ct() {
  docker compose --env-file backend/.env \
    -f database/docker-compose.yml -f database/docker-compose.server.yml "$@"
}

ct exec -T backend python -m app.simulate list
ct exec -T backend python -m app.simulate random
# list에서 확인한 화장실 ID와 해당 칸 번호로 지정한다.
ct exec -T backend python -m app.simulate set --restroom 1 --stall 1 --state free
ct exec -T backend python -m app.simulate reset
```

화장실 ID는 서버마다 다를 수 있으므로 `list` 결과를 기준으로 한다.
시뮬레이션 상태는 메모리에만 보관하며 API 재시작 시 해제된다.
사용 이벤트·과거 통계에는 가짜 데이터를 넣지 않는다.

## iPhone

`app/.env.example`을 참고해 Git 제외 파일 `app/.env.local`을 준비하고
`API_BASE_URL`, `USE_MOCK=false`, 카카오 네이티브 앱 키를 설정한다.
실기기용 서명은 Xcode에 Apple 계정을 등록한 뒤 로컬 설정 파일에 지정한다.
아래 명령은 `app` 디렉터리에서 실행하며, 기존 로컬 설정 파일은 덮어쓰지 않는다.

```bash
cp -n ios/Flutter/Local.xcconfig.example ios/Flutter/Local.xcconfig
```

Git에서 제외되는 `ios/Flutter/Local.xcconfig`에 다음 값을 입력한다.

- `DEVELOPMENT_TEAM`: 자신의 Apple 개발 팀 ID.
- `CT_HTTP_SERVER_HOST`: HTTP로 테스트할 API 호스트. 프로토콜·포트·경로 없이 입력한다.
  Release/Profile의 ATS 예외는 이 호스트에만 적용한다. 기본값은 `localhost`다.
  IP별 ATS 예외는 iOS 17 이상에서 지원된다.
  [Apple 문서](https://developer.apple.com/documentation/BundleResources/Information-Property-List/NSAppTransportSecurity/NSExceptionDomains)

개인 Team ID를 `project.pbxproj`에 저장하지 않는다. Xcode에서 서명을 변경했으면 커밋 전에 diff를 확인한다.
기기 ID는 `flutter devices`로 확인한 뒤 로컬 셸 변수 `IOS_DEVICE_ID`에 지정한다.

```bash
BYPASS_PERMISSION_LOCATION_ALWAYS=1 flutter build ios \
  --release --dart-define-from-file=.env.local
xcrun devicectl device install app --device "$IOS_DEVICE_ID" \
  build/ios/iphoneos/Runner.app
```

설치 후 아이폰 홈 화면에서 앱을 연다. 앱 실행에 USB 연결은 필요하지 않다.
종료 후 독립 실행하려면 **Release 빌드**를 사용한다. Debug 빌드는 Flutter/Xcode 디버거 연결이 필요하다.
프로비저닝 프로파일이 만료되면 같은 계정으로 다시 빌드·설치한다.
Bundle ID를 변경하면 카카오 개발자 콘솔의 iOS Bundle ID 등록도 맞춰야 한다.

처음 연결할 때 필요한 Device Support는 USB로 준비한다.
Xcode에서 Metal Toolchain 설치를 요구하면 공식 구성 요소를 설치한다.

```bash
xcodebuild -downloadComponent MetalToolchain
```
