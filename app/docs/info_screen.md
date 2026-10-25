# 정보 화면 인계

목록은 `5.png`, 본문 영역은 `6.png`를 기준으로 구현합니다. 상단·하단 바를 유지하고 가운데 내용만 전환합니다.

## 동작

- `전체`에서는 원본 이미지를 사용한 카드 4장을 보여줍니다.
- 카드 또는 상단 변비·치질·변모·변색 버튼을 누르면 정보 탭 안의 가운데 영역이 해당 본문으로 바뀝니다. 별도 화면을 push하지 않습니다.
- 상단 제목·주제 선택과 하단 앱 탭은 같은 위치에 계속 유지합니다. 가운데에는 파란 제목 배지와 둥근 흰색 본문 영역을 표시합니다.
- 본문은 스크롤·텍스트 선택이 가능합니다. 주제를 바꾸면 새 글의 처음부터 표시합니다.
- 본문의 `전체`, 상단 뒤로 가기, 시스템 뒤로 가기는 가운데 영역을 카드 목록으로 바꿉니다. 원래 목록의 스크롤 위치를 유지합니다.
- 하단 지도·목록·추천 탭은 본문을 읽는 중에도 사용할 수 있습니다. 정보 탭으로 돌아오면 읽던 주제·본문 스크롤을 유지합니다.
- 카드 목록 상태에서 상단 뒤로 가기는 직전에 열었던 하단 탭으로 돌아갑니다.
- 큰 글자에서는 카드가 1열로 바뀌며 긴 제목도 줄바꿈합니다.

## 원본 이미지와 본문

원본 PNG는 수정하지 않았으며 `BoxFit.cover`와 정렬값으로 카드 영역에서만 잘라 표시합니다.

| 주제 | 카드 원본 | 본문 제공 자료 |
| --- | --- | --- |
| 변비 | `정보3.png` | 사용자 제공 전문, 원인 1~5와 인용문·정책브리핑 출처 포함 |
| 치질 | `정보4.png` | 사용자 제공 3개 문단 |
| 변모 | `정보2.png` | `변모양.png`의 7개 항목을 수동 추출·대조 |
| 변색 | `정보1.png` | `변색.png`의 도입문과 6개 색상 항목을 수동 추출·대조 |

사용자가 제공한 내용을 앱의 문단·소제목으로 나눠 표시합니다. 별도 의료 자료를 추가하거나 새 진단 내용을 작성하지 않았습니다.
본문과 출처는 `lib/data/health_articles.dart`, 본문 구조는 `lib/models/health_article.dart`에서 관리합니다.
이미지·본문은 모두 앱에 포함되어 정보 화면을 읽는 데 네트워크가 필요하지 않습니다.

## 변경 파일

이번 수정: `lib/app.dart`, `lib/screens/info_screen.dart`, `test/info_screen_test.dart`,
`README.md`, 이 문서.

추가:

- `lib/widgets/health_article_body.dart`: 제목 배지와 스크롤 가능한 본문만 담당하는 위젯

제거: 별도 라우트용 `lib/screens/health_article_screen.dart`.
기존 `lib/widgets/health_category_tabs.dart`, 원본 이미지, 사용자 제공 본문은 유지합니다.

## 실행·빌드

사용자 요청에 따라 **재빌드 시 반드시 `--dart-define-from-file=.env.local`을 사용합니다.**
아래 명령은 `app/`에서 실행합니다. `.env.local`은 기존 로컬 설정을 사용하며 내용을 출력하거나 Git에 추가하지 않습니다.

```bash
cd app
.tools/flutter/bin/flutter run -d <device-id> --dart-define-from-file=.env.local
.tools/flutter/bin/flutter build ios --simulator --debug --no-pub --dart-define-from-file=.env.local
```

시작하기 → 정보 → 카드 또는 상단 주제로 본문을 확인합니다.

## 검증

- `flutter analyze --no-pub`: 통과, 발견된 문제 없음.
- `flutter test --no-pub test/widget_test.dart test/info_screen_test.dart`: 8개 통과, 회귀 테스트 1회.
- 위젯 테스트에서 상하단 바의 요소·위치 유지, 새 라우트 없이 본문 전환, 주제 변경 시 스크롤 초기화, 하단 탭 왕복 시 읽던 위치 복원, 뒤로 가기와 작은 화면·큰 글자를 확인했습니다.
- `flutter build ios --simulator --debug --no-pub --dart-define-from-file=.env.local`: 통과.
- iPhone 18 Pro / iOS 27.0 시뮬레이터에 설치·실행하고, 변비 본문을 읽는 동안 상단 제목·주제 버튼과 하단 탭이 표시되는 것을 확인했습니다.
- Dart 포맷 검사와 `git diff --check`: 통과.

실제 iPhone·Android 기기는 이번 작업에서 검증하지 않았습니다. 확인된 미해결 코드 오류는 없습니다.

## 협업 참고

변경은 `app/` 내부 정보 기능에 한정합니다. API 계약·Backend·DB·센서·추천 로직은 변경하지 않았습니다.
새 패키지·환경변수·원격 콘텐츠 API는 추가하지 않았습니다. 실제 기기의 확인 여부는 위 검증 기록을 참고하세요.
