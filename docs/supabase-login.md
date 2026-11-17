# Supabase Apple 로그인

구현일: 2026-11-16. PRD FR-01의 기본안인 **Apple 공급자 1개**를 사용한다. 이메일/비밀번호, 다른 소셜 공급자와 웹 OAuth는 추가하지 않았다.

## 구현 흐름

1. 앱이 `AuthStore`를 만들고 Supabase의 인증 상태 스트림을 구독한다.
2. 저장된 세션이 없으면 `LoginView`, 유효한 세션이 있으면 기존 `GameMakerView`를 표시한다. 복구 실패 시 재시도 화면을 표시하며 임의로 로그인 완료로 취급하지 않는다.
3. Apple 버튼마다 `SecRandomCopyBytes`로 32바이트 nonce를 생성한다. Apple 요청에는 SHA-256 해시를, Supabase `signInWithIdToken`에는 원본 nonce와 Apple ID token을 전달한다.
4. Apple 인증 취소는 오류로 표시하지 않는다. 토큰 누락, 로그인 실패는 화면에 안내하며 중복 Supabase 로그인 요청은 막는다.
5. 세션 저장과 자동 갱신은 기존 Supabase.swift 2.36.0 SDK에 맡긴다. Apple 플랫폼의 SDK 기본 저장소는 Keychain이다. 앱에서 토큰을 UserDefaults나 로그에 복사하지 않는다.
6. 로그아웃 확인 후 `signOut(scope: .local)`을 호출한다. 다른 기기의 세션은 종료하지 않는다. 로그인 상태가 바뀌면 기존 화면과 탐색 스택을 제거한다.

이 버전 SDK는 로그아웃 요청 전에 로컬 세션을 제거한다. 네트워크 오류가 나면 로그인 화면으로 돌아갈 수 있지만 서버의 refresh token 폐기 성공까지 보장하지 않는다. 이미 발행된 access token도 만료 전까지 유효할 수 있다. 앱은 서버 로그아웃이 실패했다는 안내를 표시한다.

## 외부 설정 — 실제 로그인 전 필수

2026-11-16 공개 `GET /auth/v1/settings` 조회 결과 Apple 공급자는 **비활성**이었다. 연결 가능한 MCP에는 Auth 공급자 설정 변경 도구가 없어 서버 설정은 변경하지 않았다. Apple Developer와 Supabase 관리 화면의 설정 및 실제 Apple 계정 동의가 필요하다.

1. [Apple Developer Identifiers](https://developer.apple.com/account/resources/identifiers/list)에서 App ID `com.hojoon.our-league`의 Sign in with Apple을 활성화한다. 현재 Xcode 프로젝트 서명 팀과 소유 App ID가 일치하는지 확인한다.
2. [프로젝트 Authentication Providers](https://supabase.com/dashboard/project/dwvogajwqeodwkjppdyw/auth/providers)의 Apple 공급자를 활성화하고, Client IDs에 `com.hojoon.our-league`를 등록한다. 기존 클라이언트 ID가 있다면 제거하지 않는다. nonce 검증은 해제하지 않는다.
3. Xcode 앱 타깃의 Signing & Capabilities와 프로비저닝을 확인한다. 프로젝트에는 `Configuration/OurLeague.entitlements`와 Debug/Release의 `CODE_SIGN_ENTITLEMENTS`, Sign in with Apple capability를 추가했다. 로컬 파일만으로 Apple 계정의 App ID 설정이나 서명 프로파일이 변경되지는 않는다.
4. 전체 Xcode의 iOS 18 이상 환경에서 빌드하고 Apple ID가 로그인된 기기로 확인한다. 빌드 환경에는 [Supabase 로컬 설정](supabase-setup.md)이 있어야 한다.

현재 구현은 네이티브 ID token 방식이다. 웹 OAuth용 Services ID, callback URL, `.p8` 키/6개월 주기 client secret 설정을 앱 코드에 추가하지 않는다. 네이티브 전용 설정은 [Supabase 공식 Apple 로그인 안내](https://supabase.com/docs/guides/auth/social-sign-in/auth-apple?platform=swift)를 따른다.

## 검증과 남은 범위

- 인증 상태/재시도/로그아웃/중복 요청/오류와 토큰 비노출/nonce 생성·해시 회귀 검사를 기존 XCTest 파일에 추가했다.
- 로컬에서는 Foundation·Combine·CryptoKit·Security 기반 계약 검사 28개가 통과했다(기존 모델·설정 검사 14개 + 인증·nonce 검사 14개). Xcode 프로젝트와 entitlement 문법, 인증 소스 5개의 타깃 포함 여부 및 Debug/Release 서명 설정 검사도 통과했다.
- 이 환경은 Command Line Tools의 Swift 5.8.1만 있어 전체 iOS 빌드, XCTest 러너, 시뮬레이터 화면 검증과 실제 Apple → Supabase 왕복 인증은 실행하지 못했다. SDK 자체의 최소 Swift 도구 버전은 5.10이다. 단순 Swift 문법 검사나 mock 검사가 실제 인증 성공을 뜻하지 않는다.
- 외부 설정 후 첫 로그인/재실행 복구/취소/오프라인 복구 재시도/로그아웃/재로그인을 실기기에서 확인하고 Supabase Auth Users와 대조한다. 서버가 토큰을 검증하며 화면 상태만으로 DB 권한을 부여하지 않는다.
- 로그인 후 진입 화면은 기존 로컬 경기 생성 프로토타입이다. 클럽 조회·가입 승인·프로필 닉네임 저장·계정 삭제는 이번 로그인 구현에 포함하지 않았다. 따라서 PRD FR-01 전체나 App Store 배포 준비가 완료된 것은 아니다. 최초 로그인만으로 기존 클럽 운영자나 명단 참가자에 자동 연결하지 않는다.

주요 파일: `OurLeague/Auth/AuthSession.swift`, `AuthStore.swift`, `SupabaseAuthService.swift`, `AppleSignInNonce.swift`, `LoginView.swift`, `OurLeague/Splash/SplashView.swift`.
