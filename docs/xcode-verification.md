# 실제 Xcode 검증

검증일: 2026-11-24.

## 환경과 수정

- Xcode 26.2 (`17C52`), `/Users/yanghojoon/Downloads/Xcode.app`.
- 전역 `xcode-select`는 `/Library/Developer/CommandLineTools`였지만, Xcode는 설치되어 실행 중이었다. 이전 문서의 “전체 Xcode 없음” 판단을 정정한다.
- 시스템 전역 설정 대신 `DEVELOPER_DIR`를 지정했다. Supabase SDK는 기존 고정 버전 2.36.0을 사용했다.
- 별도로 만든 iPhone 16 / iOS 18.6 시뮬레이터에서 실행하여 기존 시뮬레이터·로그인 세션을 변경하지 않았다.
- 첫 실제 테스트 빌드는 앱 최소 iOS 18.0과 단위 테스트 타깃의 17.0 설정 불일치로 실패했다. `OurLeagueTests`의 Debug·Release를 18.0으로 맞춘 뒤 다시 실행했다. 앱의 기존 최소 버전은 변경하지 않았다.

## 결과

| 항목 | 결과 | 범위 |
| --- | --- | --- |
| Debug 앱·테스트 빌드 | 통과 | 실제 iOS SDK와 Supabase SDK 포함 |
| XCTest | 63개 통과, 실패 0개 | 설정·모델·인증 상태·프로필·동호회 계약 및 mock 서비스 |
| 로그인 UI 검사 | 1개 통과, 실패 0개 | 새 시뮬레이터 첫 실행·재실행, Apple 버튼 표시와 탭 가능한 상태, 인증 오류 미표시, 동호회 생성 버튼 미노출 |
| 로그인 화면 확인 | 통과 | XCTest 첨부 스크린샷에서 잘림 없는 레이아웃 확인 |
| Supabase Auth 연결 | HTTP 200 | 로컬 공개 키로 `/auth/v1/settings` 읽기 |
| Apple 공급자 설정 | 활성 확인 | `external.apple = true`; 실제 Apple 인증 성공을 뜻하지 않음 |

`xcresulttool` 요약: **전체 64개, 통과 64개, 실패 0개, 건너뜀 0개**. AppIntents 의존성이 없어 메타데이터 추출을 생략한다는 Xcode 경고는 있었으며 테스트 실패는 아니었다.

## 재현

```sh
export DEVELOPER_DIR=/Users/yanghojoon/Downloads/Xcode.app/Contents/Developer
xcodebuild test \
  -project OurLeague.xcodeproj \
  -scheme OurLeague \
  -configuration Debug \
  -destination 'platform=iOS Simulator,name=OurLeague Verification,OS=18.6' \
  -parallel-testing-enabled NO \
  -only-testing:OurLeagueTests \
  -only-testing:OurLeagueUITests/OurLeagueUITests/testLoginScreenAppearsWithoutSession \
  CODE_SIGNING_ALLOWED=NO
```

UI 검사는 로그인 세션이 없는 검증 전용 시뮬레이터에서 실행한다. 이미 로그인한 사용자 기기에서 같은 초기 상태를 기대해서는 안 된다. 로컬 Supabase 설정이 필요하다. 빌드 중 설정값이 포함될 수 있으므로 전체 빌드 로그를 외부에 그대로 공유하지 않는다.

검증 당시 결과 번들: `/private/tmp/OurLeague-Verification-20261124.xcresult`. 임시 경로이므로 영구 보관을 보장하지 않으며 저장소에는 추가하지 않았다.

## 미검증

실제 Apple ID의 사용자 동의를 완료하지 않았다. Apple → Supabase 인증, 인증된 세션 복구·로그아웃·계정 전환, 실제 프로필 및 동호회 생성·조회·전환의 서버 왕복, 로그인 이후 화면의 시각 검증은 남아 있다. 자동 검사를 위해 실제 사용자·동호회를 생성하거나 인증을 우회하지 않았다. Release 빌드와 실기기 서명·실행도 이번 검증 범위가 아니다.

## 후속 명단 기능 검증

같은 Xcode·시뮬레이터에서 참가자 명단 기능을 포함해 다시 실행했다. **단위 테스트 81개(명단 회귀 검사 18개 포함)와 비로그인 UI 검사 1개, 총 82개가 통과하고 실패는 0개**다. 결과 번들은 `/private/tmp/OurLeague-Roster-20261124.xcresult`다. 기존 64개 결과는 위에 초기 검증 이력으로 유지한다.

실제 프로젝트의 명단 이름 제약과 RLS·저장 RPC 본문도 읽기 전용으로 확인했다. 실제 로그인 후 명단 생성·수정·비활성화의 서버 왕복과 해당 화면의 시각·조작 검증은 하지 않았다. 서버 검증을 위해 임의 사용자나 참가자를 만들지 않았다. [명단 기능의 계약과 한계](supabase-roster.md)를 참고한다.
