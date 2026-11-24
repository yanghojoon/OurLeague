# Supabase 앱 연결 설정

대상 프로젝트: `dwvogajwqeodwkjppdyw` (서울). 설정 반영일: 2026-11-16.

## 설정 파일과 흐름

`Configuration/Supabase.xcconfig` → `Configuration/Supabase-Info.plist` → `SupabaseConfiguration` → `SupabaseEnvironment.client()` 순서다. 앱 타깃의 Debug와 Release 모두 같은 기본 설정을 사용한다.

| 파일 | 역할 |
| --- | --- |
| `Configuration/Supabase.xcconfig` | 프로젝트 주소, 선택적인 로컬 설정 include |
| `Configuration/Supabase.local.xcconfig.example` | 다른 개발 환경에서 복사할 설정 양식 |
| `Configuration/Supabase.local.xcconfig` | 실제 공개 키. Git 제외 |
| `Configuration/Supabase-Info.plist` | 빌드 설정을 앱 번들에 전달 |
| `OurLeague/App/Resource/SupabaseConfiguration.swift` | 누락·플레이스홀더·잘못된 주소·관리자 키 검사 |
| `OurLeague/App/Resource/Supabase.swift` | 검증된 설정으로 단일 클라이언트 생성 |

현재 작업 환경에는 기존 프로젝트의 활성 `anon` 키를 로컬 파일에 설정했다. 새 환경에서는 example을 `Supabase.local.xcconfig`로 복사한 뒤 Dashboard의 공개 키를 `SUPABASE_PUBLISHABLE_KEY`에 넣는다. CI에서도 빌드 전에 같은 파일을 안전하게 주입한다. 키 없이도 컴파일할 수 있지만 클라이언트 접근 시 설정 오류가 발생한다.

`SUPABASE_URL`의 `https:/$()/`는 xcconfig의 `//` 주석 처리를 피하기 위한 표기다. 빌드 설정 확장 후 정상적인 `https://` 주소가 된다.

## 사용

```swift
let client = try SupabaseEnvironment.client()
```

호출하는 기능에서 오류를 처리한다. 클라이언트 생성만으로 네트워크 요청이나 로그인이 실행되지는 않는다. 앱의 인증 진입점은 이 클라이언트를 사용한다. [Apple 로그인 구현과 외부 설정](supabase-login.md)을 참고한다. 클럽 데이터 조회·저장 화면 연결은 후속 구현 범위다.

## 키와 권한

- 권장 형식은 `sb_publishable_...`다. 현재 프로젝트에는 기존 JWT 기반 `anon` 키만 있어 호환을 허용한다. `service_role` 및 `sb_secret_...` 키는 앱에 넣지 않는다.
- 기존 JWT의 `role=anon` 검사는 설정 실수 방지용이며 서명 검증이나 인증을 대신하지 않는다. 키 유효성은 서버가 검증한다.
- 로컬 파일을 Git에서 제외해도 공개 키는 앱 번들에서 추출할 수 있다. 데이터 보호는 RLS와 서버 RPC 권한 검증에 달려 있다.
- 공개 키는 사용자 로그인 세션이 아니다. 미인증 상태에서 클럽 테이블 접근이 거부되는 것은 정상이다.
- 키를 교체하면 앱을 다시 빌드한다. 기존 배포 앱에 대한 영향 검토 없이 키를 폐기하지 않는다.

공식 참고: [Swift 초기화](https://supabase.com/docs/reference/swift/initializing), [API 키 종류](https://supabase.com/docs/guides/getting-started/api-keys).

## 검증 범위

`OurLeagueTests`에 설정 정상 로드, 누락·플레이스홀더, 잘못된 URL, 관리자 키 차단, 기존 anon 키 호환 검사를 추가했다. 기존 모델 검사와 함께 Foundation 기반 검증으로 실행할 수 있다.

2026-11-16 검증 결과:

- 사용자 승인 후 프로젝트 재개 완료: `ACTIVE_HEALTHY`.
- 실제 로컬 공개 키로 `GET /auth/v1/settings`: HTTP 200.
- 비로그인 `GET /rest/v1/clubs?select=id&limit=1`: HTTP 401 / `42501` (의도한 테이블 접근 차단).
- MCP 읽기 전용 SQL 연결 성공, `clubs` 테이블 존재, RLS 활성, anon SELECT 불가, authenticated SELECT 가능.
- 기존 마이그레이션 4개 유지. Auth 계정은 0개라 사용자 로그인·인증 후 조회는 검증하지 않았다.
- 모델·설정 계약 검사 14개 통과, 프로젝트/Info.plist 문법 검사와 Debug/Release 설정 참조 확인 통과. 이 계약 검사는 전체 iOS XCTest 실행을 대체하지 않는다.

보안 Advisor에는 authenticated 역할이 조회 가능한 테이블·뷰 12개의 GraphQL 스키마 노출 경고가 남아 있다. 이는 데이터 행의 무제한 공개를 뜻하지 않는다. 현재 로그인 사용자 조회를 위한 권한은 유지했으며, 테이블 구조 자체의 비노출이 필요하면 별도로 검토한다. [경고 설명 및 대응](https://supabase.com/docs/guides/database/database-linter?lint=0027_pg_graphql_authenticated_table_exposed).

초기에는 선택된 CLI 경로가 Command Line Tools여서 앱 빌드를 검증하지 못했다. Xcode 미설치라는 판단은 잘못되었으며, 2026-11-24에 실제 Xcode 경로를 지정해 [시뮬레이터 빌드·테스트](xcode-verification.md)를 완료했다. 같은 날 Apple 공급자 활성화도 확인했다. 실제 Apple 계정 인증과 인증된 RPC 저장은 별도 검증이 필요하다. DB 스키마와 테스트 데이터는 이 설정 단계에서 변경하지 않는다.
