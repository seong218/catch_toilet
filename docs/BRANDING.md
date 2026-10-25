# Catch Toilet 이름 정리

2026-10-25. 서비스 이름은 **Catch Toilet**이다. 화면·문서·메타데이터의 이전 철자를 수정했다.

## 변경 범위

- 앱 제목·공통 설정·Android 런처 이름·iOS Debug/Release 표시명·웹 제목과 manifest
- Dart 패키지 `catch_toilet`, 루트 위젯 `CatchToiletApp`, 관련 테스트 import와 부트스트랩 기본 이름
- 루트/Flutter README, AGENTS, API 계약 문서 제목, Backend API 제목·모듈 설명, 카카오 설정 문서와 로컬 패치 문서 제목
- 새 인계 파일: 이 문서

API 경로·응답 형식·추천 계산은 변경하지 않았다. 새 패키지나 환경변수는 없다.
패키지 이름이 바뀌었으므로 기존 체크아웃에서도 `flutter pub get`을 실행한 뒤 개발한다.

## 호환 식별자

다음은 실제 등록·운영 중인 리소스 식별자이므로 이번 표시명 수정에서 유지했다.

- 카카오에 등록된 Android applicationId/namespace와 iOS Bundle ID
- Docker Compose 프로젝트 이름, 기존 PostgreSQL 볼륨과 계정 이름
- GitHub 저장소 이름과 원격 주소

이 식별자를 바꾸려면 카카오 등록·앱 서명·DB 데이터 이관 등 별도 이전 작업이 필요하다.
카카오 콘솔의 앱 관리 이름도 이번 코드 변경으로 자동 변경되지 않는다.
기존 플랫폼 폴더는 그대로 사용한다. 부트스트랩으로 새로 생성한 플랫폼은 새 기본 식별자를 쓰므로 카카오 등록을 확인해야 한다.

## 실행 및 검증

```bash
cd app
.tools/flutter/bin/flutter pub get --offline
BYPASS_PERMISSION_LOCATION_ALWAYS=1 .tools/flutter/bin/flutter build ios \
  --simulator --debug --no-pub --dart-define-from-file=.env.local
```

환경 파일은 Git에 추가하지 않는다. 기존 개발 중이던 iOS 서명 설정·서버 배포 변경은 이번 커밋에 포함하지 않는다.

- 정적 분석 통과, Flutter 전체 테스트 77개 통과(회귀 1회).
- Backend 수정 파일의 Python 문법과 Android/iOS/웹 표시명 검증 통과.
- `.env.local` 포함 iOS 시뮬레이터 빌드·설치·실행 성공. 빌드 결과의 표시명이 `Catch Toilet`임을 확인했다.
- Android SDK가 없어 Android 빌드는 수행하지 않았다. Backend 전체 회귀 및 웹 브라우저 실행은 이번 이름 수정에서 재실행하지 않았다.
- 이름 수정 범위의 남은 구현이나 발견된 오류는 없다. 운영 식별자 이전은 위 호환 범위에 따라 별도 작업이다.
