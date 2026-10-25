# 화장실 약도 화면 인계

`4_.png`를 기준으로 목록에서 선택한 화장실의 상세 화면을 약도와 하단 현황 카드로 구현했습니다.

## 동작과 데이터

- 기존 목록·지도·추천의 상세 경로를 그대로 사용하고, 선택한 `restroomId`로 상세 API를 조회합니다.
- `stalls`의 실제 칸 수와 `stall_number`로 약도를 만듭니다. 층별 칸 수나 비데 수를 UI에 고정하지 않습니다.
- 사용 중은 빨강, 사용 가능은 초록, 센서 미관측은 회색입니다. 장애인 칸은 휠체어 아이콘으로 표시합니다.
- 칸별 비데 있음/미확인을 표시하고, 길게 누르기 안내와 화면 읽기에 칸 번호·사용 상태·비데·장애인 여부를 제공합니다.
- 요약은 전체 칸 수, 사용 중, 설치 비데 수, 사용 가능한 칸, 미확인 칸입니다.
  사용 중은 `total_stalls - available_stalls - unknown_stalls`이며 전체 미관측이면 `미확인`으로 표시합니다.
  비데 설치 수는 `bidet_stalls`를 사용하고 null이면 `미확인`입니다.
- 기존 `AppController`의 WebSocket 이벤트 적용으로 약도와 집계가 함께 바뀝니다. 추천 재요청 정책도 기존 컨트롤러를 따릅니다.
- 최초 로딩, 빈 칸 목록, 실패 후 재시도, 아래로 당겨 새로고침, 캐시된 정보의 갱신 실패 안내를 제공합니다.
- 기존 뒤로 가기 동작으로 목록과 필터 상태를 유지합니다. 작은 화면과 큰 글자에서는 전체 화면을 스크롤합니다.

## 범위와 미구현 사항

- API에 실제 실내 배치 좌표가 없으므로 약도는 개념 배치입니다. 장애인 칸을 아래쪽에 두되 원래 칸 번호를 유지합니다.
  공용 공간은 상징적으로 표현하며 세면대·소변기의 실제 개수를 임의로 만들지 않습니다.
- 시안의 도보 시간 대신 기존 API 직선거리를 사용합니다. 인원 수는 API에 없어 빈칸·미확인 칸으로 대체했습니다.
- Backend, API 계약, 상태 관리, 추천 알고리즘, 패키지, 환경변수는 변경하지 않았습니다.

## 파일

- 수정: `lib/screens/restroom_detail_screen.dart`, `test/restroom_list_test.dart`, `test/widget_test.dart`, `README.md`의 약도 안내.
- 추가: `lib/widgets/restroom_floor_plan.dart`, `lib/widgets/restroom_detail_summary.dart`, `test/restroom_detail_test.dart`, 이 문서.
- 그림은 Flutter Canvas로 그립니다. 새 이미지 자산이나 패키지가 필요하지 않습니다.

## 실행

```bash
cd app
.tools/flutter/bin/flutter run -d <device-id> --dart-define-from-file=.env.local
# Backend 없이 기존 데모 데이터로 확인
.tools/flutter/bin/flutter run -d <device-id> --dart-define=USE_MOCK=true
```

앱에서 `시작하기 → 목록 → 화장실 카드`를 누릅니다. 실제 실행에는 기존 Backend 접속 설정을 사용합니다.

## 검증 (2026-10-24)

- `flutter analyze --no-pub`: 통과.
- Flutter 전체 테스트 52개 + 임시 화면 렌더 검증 1개 통과. 회귀 실행 총 3회로 제한 준수.
- 층별 상세 ID, 4칸/6칸 구성, 비연속 칸 번호, 미관측 상태, 비데 null, 장애인 칸, 중복 이벤트, 실시간 집계, 재시도, 빈 상세, 320px·글자 1.6배를 검증했습니다.
- iOS 시뮬레이터 Debug 빌드 통과. 기존 `.env.local`을 사용했고 내용은 변경하지 않았습니다.
- 실제 로컬 API 본관 1층 응답(4칸, 비데 3개, 장애인 1칸, 모두 미관측)을 Flutter 테스트 렌더러로 시각 검수했습니다.
  미리보기는 Git 제외 경로 `build/restroom-detail-preview.png`에 있습니다.
- 큰 글자에서 비데 문구가 넘치는 문제와 칸별 접근성 병합 문제를 수정했습니다. 최종 검증에 남은 오류는 없습니다.
- 실제 iPhone/Android 기기, Arduino 센서 연결은 이번 작업에서 검증하지 않았습니다.
