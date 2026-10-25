# 카카오맵 연결 및 무료 사용 설정

2026-10-24. 지도 탭은 `kakao_map_sdk 1.3.1`을 통해 카카오 Android/iOS 지도 SDK를 사용한다.
Flutter 플러그인은 커뮤니티 패키지이며, 네이티브 지도는 카카오 SDK다.
`KAKAO_NATIVE_APP_KEY`가 비어 있으면 지도 SDK를 호출하지 않고 층별 목록을 안내한다.
검색·층별 목록·상세·REST/WebSocket은 키 없이도 동작한다.

## 카카오 디벨로퍼스 설정

1. [카카오 디벨로퍼스](https://developers.kakao.com/console/app)에 가입·로그인한다.
2. `Catchy Toilet` 앱을 생성한다. 이미 무료 지도를 쓰는 앱이 있다면 먼저 확인한다.
   무료 쿼터는 개발자 계정에서 **처음 카카오맵 API를 활성화한 앱 하나**에 적용된다.
3. 해당 앱의 **카카오맵 > 사용 설정 > 상태**를 ON으로 설정한다.
4. 앱 키의 **네이티브 앱 키**에 플랫폼 정보를 등록한다.
   - Android 패키지: `dev.catchytoilet.catchy_toilet`
   - Android 키 해시: 실행 APK를 서명한 인증서의 SHA-1을 Base64로 인코딩한 값
   - iOS Bundle ID: `dev.catchytoilet.catchyToilet`
5. **비즈월렛을 연결하거나 유료 API 사용을 활성화하지 않는다.**
   무료 적용 앱인지와 유료 사용 설정을 콘솔에서 확인한다.
6. 네이티브 앱 키만 Git에서 제외된 `app/.env.local`에 넣는다.
   JavaScript/REST API/Admin 키나 Client Secret을 대신 넣지 않는다.

일반적인 Android debug 키 해시는 macOS/Linux에서 다음 명령으로 확인한다.
실제 사용한 서명 키가 다른 경우 해당 인증서로 확인해야 한다.
배포 시에는 Play 앱 서명 인증서의 키 해시도 별도로 등록한다.

```bash
keytool -exportcert -alias androiddebugkey \
  -keystore ~/.android/debug.keystore -storepass android \
  | openssl sha1 -binary | openssl base64
```

### 비용

현재 무료 지도 Android/iOS SDK 쿼터는 일 300,000건이며, 전체 API 월간 무료 쿼터는 3,000,000건이다.
지도 무료 적용 앱에서 **유료 API가 비활성화된 상태**라면 무료량 소진 시 요청이 429로 제한된다.
두 번째 지도 앱이나 무료 초과 사용에는 별도의 유료 설정이 필요하다.
코드나 환경변수는 계정의 과금 설정을 변경하지 않는다. 기존 유료 계정의 설정은 반드시 콘솔에서 확인한다.

공식 근거:

- [지도 활성화·첫 앱 무료·429 제한](https://developers.kakao.com/docs/ko/kakaomap/common)
- [무료 쿼터](https://developers.kakao.com/docs/ko/getting-started/quota)
- [지도 SDK](https://apis.map.kakao.com/)
- [Flutter 플러그인 설치·플랫폼 제약](https://pub.dev/packages/kakao_map_sdk)

## 실행

```dotenv
USE_MOCK=false
API_BASE_URL=http://localhost:8000
KAKAO_NATIVE_APP_KEY=발급받은_네이티브_앱_키
```

`app/`에서 실행한다. Flutter는 `.env.local`을 자동으로 읽지 않는다.
실제 휴대폰에서는 `API_BASE_URL`에 개발 PC의 LAN 주소를 사용한다.

```bash
BYPASS_PERMISSION_LOCATION_ALWAYS=1 .tools/flutter/bin/flutter run \
  -d <device-id> --dart-define-from-file=.env.local
```

키 변경 후 hot reload 대신 앱을 종료하고 다시 실행한다.
Android는 ARM 기기/ARM64 에뮬레이터를 사용한다. 카카오 Android 지도 SDK는 x86/x64를 지원하지 않는다.
iOS는 Swift Package Manager로 설치되며, Android release에 필요한 ProGuard 규칙을 포함한다.
이 앱의 웹·데스크톱에서는 지도 대신 목록을 제공한다.

## 구현 및 인계

- 네이버 지도 의존성·초기화·`NAVER_MAP_CLIENT_ID`를 제거하고 카카오 SDK로 교체했다.
- 지도는 디미고 대표 좌표에서 시작하며 카카오 로고가 하단 탭에 가려지지 않도록 배치한다.
- 검색은 이미 받은 화장실 이름·건물·층을 사용한다. 외부 장소 검색 API는 호출하지 않는다.
- 본관·신관·우정학사·학봉관·체육관에 각각 하나씩, 총 5개 건물 마커를 표시한다.
  서버 화장실은 건물명으로 묶고 마커를 누르면 해당 건물의 층별 목록을 연다.
  미등록 건물은 회색 마커와 준비 중 안내를 표시하며 가짜 칸/빈칸 데이터를 만들지 않는다.
  신관의 `정보기술문화센터`, `정보기술문화센터 (신관)` 명칭도 같은 건물로 연결한다.
- 녹색은 관측된 빈칸, 빨강은 확인된 만석, 회색은 미관측/연결 미확인이다.
- 실제 GPS 위치만 작은 파란 점(지름 8), 흰 테두리, 옅은 파란 원(지름 22)으로 표시한다.
  위치 권한·오류 처리와 추천은 기존 서비스를 사용한다.
- 검색·센서 이벤트·탭 전환 때 지도와 기존 POI를 재사용한다.
- 400/401/403 인증 설정 오류, 429 한도 초과, 네트워크 오류를 구분한다.
  앱은 인증/한도 오류를 자동 재시도하지 않는다. 연결 오류에는 수동 재시도와 목록 진입을 제공한다.
- Backend/DB/API 계약은 변경하지 않았다.

### 건물 위치 데이터

`lib/data/campus_buildings.dart`는 `wleh.png`의 배치와 대조한 건물 안내용 좌표다.
건물 도형의 대표점이며 화장실 입구의 실측 좌표가 아니다. 화장실 응답의 `latitude`,
`longitude`, `distance`, `location_source`를 덮어쓰거나 추천 계산에 사용하지 않는다.
현재 Backend에는 본관만 등록되어 있으므로 다른 건물의 실제 화장실·칸 정보는 별도 등록이 필요하다.
미등록 이름의 화장실은 전체 층별 목록/검색에 남지만 캠퍼스 5개 외의 마커를 임의로 추가하지 않는다.

건물 위치 출처: © OpenStreetMap 기여자, [ODbL](https://www.openstreetmap.org/copyright).
2026-10-24 OpenStreetMap 도형의 대표점을 사용했다. 실행 중 OSM 요청은 하지 않는다.

| 건물 | 출처 도형 | 위도 | 경도 |
| --- | --- | --- | --- |
| 본관 | [way 417274017](https://www.openstreetmap.org/way/417274017) | 37.341886 | 126.831469 |
| 신관 | [way 417274019](https://www.openstreetmap.org/way/417274019) | 37.341374 | 126.831241 |
| 우정학사 | [way 1022994781](https://www.openstreetmap.org/way/1022994781) | 37.340460 | 126.831022 |
| 학봉관 | [way 417274015](https://www.openstreetmap.org/way/417274015) | 37.342363 | 126.830931 |
| 체육관 | [옥상 축구장 way 417286756](https://www.openstreetmap.org/way/417286756) | 37.341820 | 126.830704 |

수정: `lib/models/restroom_map_group.dart`, `lib/widgets/kakao_map_markers.dart`,
`lib/widgets/map_restroom_sheet.dart`, `test/map_test.dart`, `README.md`, 이 문서.
추가: `lib/data/campus_buildings.dart`.
건물 마커 변경 후 `flutter analyze --no-pub` 통과, `flutter test --no-pub` 47개 통과.
시각 조정 후 지도 테스트 9개 추가 통과(회귀 총 2회).
iPhone 18 Pro 시뮬레이터에서 debug 빌드/실행 및 5개 건물이 한 화면에 표시됨을 확인했다.
핀은 28×36, GPS 외곽 원은 22×22 기준이며 iOS SDK의 이미지 배율을 보정했다.
건물 이름은 핀 위에 배치했다. GPS 표시는 플랫폼 채널 테스트로 검증했고 실기기 수신 검증은 남아 있다.
검수 화면: `app/.tools/artifacts/campus-five-markers.png` (Git 제외).

수정: `lib/config/app_config.dart`, `lib/widgets/location_map.dart`,
`pubspec.yaml`/lock, `.env.example`, `README.md`, `android/app/build.gradle.kts`, `test/map_test.dart`.
추가: `lib/services/kakao_map_service.dart`, `lib/widgets/kakao_map_markers.dart`,
`android/app/proguard-rules.pro`, 이 문서.
제거: `lib/services/naver_map_service.dart`, 기존 네이버 설정 안내.

## 검증 상태

- `flutter analyze --no-pub`: 통과.
- `flutter test --no-pub`: 46개 통과. 카카오 전환 후 회귀 실행 1회.
- 실제 SDK 컨트롤러의 플랫폼 채널을 대체한 테스트로 마커 생성·상태 변경·선택·제거와 GPS 표시를 검증했다.
- iPhone 18 Pro 시뮬레이터 debug 빌드·실행 성공. 키 미설정 안내와 실제 API의 층별 화장실 목록을 화면에서 확인했다.
- Android ARM64 빌드는 이 개발 PC에 Android SDK가 없어 실행하지 못했다.
- 카카오 앱 `Catchy Toilet` (ID `1620917`) 생성 및 지도 ON 완료.
- 콘솔의 `카카오맵 무료 쿼터` 배지와 첫 지도 앱 무료 적용 안내를 확인했다.
- 유료 API > 일반에서 카카오맵 `사용 안 함`, 비즈월렛 미연결을 확인했다.
- iOS Bundle ID `dev.catchytoilet.catchyToilet` 등록 완료. 네이티브 앱 키는 Git에서 제외된 `.env.local`에만 저장했다.
- 유효한 키로 시뮬레이터 빌드·실행 성공. 실제 카카오 타일, 디미고 마커, 상태 미확인 문구와 로고 표시를 확인했다.
- 지도 → 층별 화장실 → 본관 2층 상세 → 지도 복귀를 실제 API로 확인했다.
- iOS에서 마커 상태 문구가 작게 보이는 문제를 조정하고 hot restart 후 시각 검증했다.
- Android는 SDK와 debug 서명 키가 아직 없어 플랫폼 등록/키 해시 등록/실행 검증이 남아 있다.

콘솔: [지도 설정](https://developers.kakao.com/console/app/1620917/product/kakao-map),
[유료 API 설정](https://developers.kakao.com/console/app/1620917/config/billing).
다른 개발 환경에서 실행하려면 해당 환경의 `.env.local`에 네이티브 앱 키를 별도로 설정해야 한다.
