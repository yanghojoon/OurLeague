# Supabase 데이터 모델 · PRD v0.3

적용일: 2026-10-19. 대상 프로젝트: `dwvogajwqeodwkjppdyw`.

그림으로 보기: [데이터 모델 HTML 안내](database-visual-guide.html). 기존 이관 자료는 사용자가 임의로 입력한 테스트 데이터이며, 보존이 제품 요구사항인 것은 아니다. HTML 안내의 예시 또한 실제 DB 조회가 아닌 설명용이다.

## 적용 범위

PRD의 논리 모델을 실제 Postgres 스키마, 권한 정책, 원자적 쓰기 RPC, Swift 행 모델로 반영했다. 기존 배열 기반 앱 모델은 정규화된 UUID 기반 행 모델로 교체했다. 화면·로그인 공급자 설정·게스트 웹 배포를 완료했다는 의미는 아니다. 현재 `Supabase.swift`의 publishable key는 여전히 설정용 플레이스홀더다.

## 모델과 관계

| 테이블 / 뷰 | 역할 | 주요 불변식 |
| --- | --- | --- |
| `auth.users` / `profiles` | 인증 계정과 표시 프로필 | 경기 참가자와 별도 생명주기 |
| `clubs` / `memberships` | 클럽과 계정별 소속 | `(club_id, account_id)` 유일, 클럽당 운영자 1명, 클럽별 역할·승인 독립 |
| `club_participants` | 계정 없이도 유지되는 클럽 명단 | 이름 중복 허용, 동일 클럽의 활성 계정 연결 1개 |
| `sessions` | 일정·장소·정원·상태·명단/대진 버전 | 정원 4~32, 코트 1~4, 라운드 1~12, 마감 ≤ 시작 < 종료 |
| `session_courts` | 모임별 코트 | 활성 코트 수 일치, 비활성 코트도 ID와 과거 FK 보존 |
| `session_participants` | 회원·명단 참가자·게스트의 응답 | 중복 참석 방지, 승인 참석 인원 ≤ 정원, 클럽·계정 연결 일치 |
| `matches` / `match_players` | 복식 경기와 팀 배치 | 네 명 모두 다름, 팀별 두 명, 같은 모임의 선수·코트만 연결 |
| `results` / `result_revisions` | 현재 결과와 정정/무효화 이력 | 경기당 결과 1개, 결과 버전, 변경 전후·사유·수정자·시각 |
| `participant_stats` | 클럽별 명단 참가자 전적 | 유효한 완료 결과만 승패 집계, 0경기 승률 NULL, 출전은 진행·완료·중단 포함 |
| `private.invitations` | 회원 가입 / 모임 모집 초대 | 토큰 SHA-256 해시만 저장, 만료·폐기 |
| `private.guest_sessions` | 개인 브라우저 권한 | 모집 토큰과 분리, 승인된 모임만 조회, 개별 폐기 |
| `private.command_receipts` | 요청 재시도 중복 방지 | 계정+요청 ID 유일, 요청 본문 해시 비교, 원문 토큰 미저장 |

`session_participants.club_participant_id`는 선택값이다. 연결되지 않은 게스트를 글로벌 선수로 자동 병합하지 않는다. 운영자의 `link_guest`만 기존 클럽 명단과 연결하며 동명이인을 이름으로 합치지 않는다. 게스트의 해당 모임 결과는 게스트 조회 RPC로 확인한다. 클럽 전적 뷰는 클럽 명단에 명시적으로 연결된 기록만 집계한다.

## 권한과 쓰기 경계

- 앱 계정은 테이블에 직접 INSERT/UPDATE/DELETE하지 않는다. 조회는 RLS를 통과하고 쓰기는 RPC를 호출한다.
- 승인된 소속만 해당 클럽 데이터를 읽는다. 대기·탈퇴 계정은 자기 소속 상태만 확인할 수 있다. 가입 내역 전체를 볼 수 있는 계정은 클럽 운영자다.
- 게스트는 일반 테이블 SELECT 권한이 없다. 승인 전에는 모임 안내와 자기 응답만, 승인 후에는 해당 모임의 공개 참가자 이름·코트·대진·결과만 받는다. 계정 ID·다른 클럽·과거 모임·전적은 반환하지 않는다.
- 공개 RPC는 SECURITY INVOKER다. 권한이 필요한 처리는 `private`의 고정 `search_path` SECURITY DEFINER 함수에서 매번 계정/운영자 또는 제한된 게스트 토큰을 검증한다. `private`를 PostgREST 노출 스키마에 추가하지 않는다.
- 두 전적 뷰는 `security_invoker=true`다. 기존 대문자 테이블과 `player_stats`는 클라이언트 권한을 회수하고 보관 전용으로 차단했다.
- 경기 시작·결과 저장·정원 승인은 모임 행 잠금으로 직렬화한다. 경기의 코트·선수 구성은 시작 후 변경할 수 없다. 실제 진행 중인 코트·선수 중복과 라운드 중복은 별도로 검증한다.

### 로그인 계정 RPC

`league_command(operation text, payload jsonb, request_id uuid)`를 인증된 세션에서 호출한다. 같은 요청의 재시도에는 동일한 `request_id`와 본문을 사용한다. 다른 작업/본문에 요청 ID를 재사용하면 거부한다. 날짜는 시간대가 포함된 ISO 8601 값을 보낸다.

| operation | payload의 주요 필드 |
| --- | --- |
| `save_profile` | `display_name` |
| `create_club` | `name`, 선택 `description` |
| `save_club`, `close_club`, `leave_club` | `club_id`, 수정 시 `name` / `description` |
| `request_membership` | 회원 초대 `token` |
| `approve_membership` | `club_id`, `membership_id` |
| `transfer_owner` | `club_id`, 승인된 새 운영자의 `account_id` |
| `save_participant` | `club_id`, 생성 시 `display_name`; 수정 시 `participant_id`, 선택 `label`, `is_active`, `account_id` |
| `create_session` | `club_id`, `title`, `starts_at`, `ends_at`, `attendance_deadline`, `location`, 선택 정원·코트·라운드·안내 |
| `update_session` | `session_id`, `expected_roster_version`, 변경할 일정/장소/정원/코트/라운드/안내 |
| `rename_court` | `session_id`, `court_id`, `name` |
| `respond_attendance` | `session_id`, `response`; 운영자 대리 응답에만 `club_participant_id` |
| `approve_guest` | `session_id`, `participant_id`, `approval` |
| `link_guest` | `session_id`, `participant_id`, `club_participant_id` |
| `preview_schedule` | `session_id`, `seed` |
| `confirm_schedule` | `session_id`, `expected_roster_version`, `expected_schedule_version`, `seed`, `matches`, 선택 `accept_unequal` |
| `start_match` | `match_id`, `expected_schedule_version` |
| `save_result` | `match_id`, `winner` (`a` / `b`), `expected_result_version` (최초 0), 선택 `score_a`, `score_b`; 정정 시 `reason` 필수 |
| `invalidate_result` | `match_id`, `expected_result_version`, `reason` |
| `abort_match`, `cancel_match` | `match_id` |
| `complete_session`, `cancel_session` | `session_id` |
| `revoke_invitation` | `club_id`, `invitation_id` |
| `revoke_guest` | `session_id`, `participant_id` |

`preview_schedule`은 확정하지 않은 대진, 참가 횟수, seed, 명단/대진 버전을 반환한다. 각 `matches` 항목은 `{round_index, court_id, team_a: [참석자 UUID 2개], team_b: [참석자 UUID 2개]}` 형식이다. 명단 참가자 ID가 아닌 **모임 참석자 ID**를 사용한다. 생성기는 경기 횟수가 적은 참가자를 우선하고 seed 기반으로 동률을 해소한다. 파트너/상대 반복 최적화는 P1로 포함하지 않았다.

수동 대진의 횟수 차이가 1을 넘으면 `accept_unequal=true`가 필요하다. 확정 응답의 `minimum_appearances`, `maximum_appearances`, `fairness_warning`을 화면에 표시한다. 시작 후에는 자동 미리보기 생성을 허용하지 않으며 운영자가 남은 경기만 수동 확정한다. 이미 시작·완료·중단한 경기는 유지하고 이전 미시작 대진은 취소 상태로 보존한다.

`40001`은 버전 충돌이므로 최신 상태를 다시 조회한다. `42501`은 권한 또는 토큰 거부, `23505`는 유일성/요청 ID 충돌, `23514`는 데이터 불변식 위반이다. 서버 확인 전에 UI에서 저장 완료로 표시하지 않는다.

### 초대·게스트 RPC

1. 운영자가 `issue_invitation(target_club, target_session, expires_at)`을 호출한다. 회원 초대는 `target_session=NULL`, 모임 게스트 초대는 대상 모임 UUID다. 서버가 32바이트 난수 토큰을 한 번 반환하고 해시만 저장한다. 토큰을 분석 이벤트·로그에 넣지 않는다.
2. 방문자는 `guest_access(action: 'invite', invite_token: ...)`로 안내를 조회한다.
3. 브라우저는 CSPRNG로 별도의 32바이트 난수를 생성해 소문자 64자리 hex `browser_token`으로 안전하게 보관한다. `guest_access('submit', invite_token, browser_token, display_name, response)`를 재시도할 때 같은 브라우저 토큰을 재사용한다. 닉네임은 2~20자다.
4. 자기 상태/승인 후 모임 조회는 `guest_access(action: 'view', browser_token: ...)`다. 승인 전에는 다른 참가자 정보를 반환하지 않는다.
5. 모집 초대 재발급은 이전 모집 토큰만 폐기한다. 기존 승인 브라우저는 별도로 유지하며 운영자가 `revoke_guest`로 차단할 수 있다. 개인 세션 만료는 모임 종료 예정 시각+7일이다.

브라우저 권한 복구·개인 링크 재발급 UI, 요청 속도 제한/봇 방어, 쿠키/토큰 보관 전략은 게스트 웹/API 배포 단계에서 구현·실기기 검증해야 한다. 이 DB 반영만으로 모바일 웹이 제공되지는 않는다.

## 기존 데이터 이관

기존 `Club`, `Player`, `Club_Participants`, `GameByDay`, `Game`과 그 데이터는 삭제하지 않았다. 마이그레이션은 DB 내부에서 연결 관계를 검증하고 복사한다. 모임의 클럽이 모호하거나 경기 구성에 오류가 있으면 추측하지 않고 전체 이관을 실패시킨다.

| 기존 자료 | 보존·변환 결과 |
| --- | --- |
| 클럽 1개 | `clubs` 1개, `needs_owner` |
| 선수 14명 / 클럽 연결 14개 | 클럽별 안정적 `club_participants` 14명 |
| 날짜별 모임 1개 | `sessions` 1개, `needs_review`; 원래 날짜는 `legacy_start_date` / `legacy_end_date` |
| 경기 3개 | `matches` 3개, 선수 배치 12행 |
| 승리팀 판정 가능한 경기 2개 | 완료 결과 2건, 이관 이력 2건, 승 합계 4 / 패 합계 4 |
| 나머지 경기 1개 | 원본 점수 보존, 승패 미집계·검토 대상 |

알 수 없는 시작/종료 시각·라운드·코트는 임의 생성하지 않는다. 이관 경기의 `round_index`, `court_id`, 실제 경기 시각은 NULL이며 `legacy_id`가 있는 이관 자료에만 이 예외를 허용한다. 모임의 초기 코트는 명시적으로 `코트 미확인`이라 표시한다. 임의의 시간대로 날짜를 변환하지 않는다.

현재 Auth 계정이 0개이므로 기존 클럽에 운영자를 지정하지 않았다. 로그인 계정 생성 뒤 관리자(SQL Editor)가 실제 소유자를 확인하고 다음 비공개 함수를 실행해야 한다. 이 함수는 앱·anon·authenticated·service_role에 실행 권한이 없다.

```sql
SELECT private.assign_legacy_owner('대상 클럽 UUID'::uuid, '확인된 auth.users UUID'::uuid);
```

기존 모임을 운영 가능한 상태로 전환하려면 실제 일시·장소·마감 등 누락 정보를 확인해야 한다. 과거 기록의 운영 정보는 추측하지 말고 검토 상태를 유지해도 된다. 계정 없는 참가자를 새 계정에 연결하는 것도 별도 운영자 확인 후 수행한다.

계정 삭제 시 소유 클럽은 종료하고 남은 경기를 취소/중단한다. 운영권을 유지하려면 삭제 전에 `transfer_owner`로 인계한다. 계정 연결·프로필·소속은 제거하고 연결된 참가자 이름은 익명화하며 공동 경기와 결과는 보존한다. 실제 Auth 사용자 삭제는 인증된 서버 경로에서 Supabase Admin API로 수행해야 하며 앱에 service role 키를 넣지 않는다.

## 마이그레이션과 검증

`supabase/migrations`의 파일 버전은 원격 `supabase_migrations.schema_migrations` 이력과 일치시켰다. 파일은 Supabase CLI로 생성했으며 실제 원격 적용은 MCP로 수행했다. 빈 DB에서도 기존 보관 테이블의 구조를 먼저 생성하도록 구성했지만, Docker/로컬 Postgres가 없어 빈 환경에서 전체 재실행하는 검증은 수행하지 않았다.

- `supabase/tests/prd_v03_regression.sql`: 실제 `authenticated` / `anon` 역할로 다중 소속·권한 격리, 직접 쓰기 거부, 대진 버전·중복·네 명 제약, 코트 병렬 진행·교차 코트 선수 충돌, 시작 후 팀 고정, 무점수 승패·정정·재시도, 중단/취소 통계, 게스트 승인·정원·만료/폐기 경계, 코트 수 변경·ID 보존, 계정 삭제·기록 보존을 검증한다. 모든 fixture는 ROLLBACK한다.
- `supabase/tests/prd_v03_schedule_properties.sql`: N=4/5/6/8/10/16/32, C=1/2/4, R=1/3/12, seed=0/42의 **126가지** 실제 RPC 생성 결과에서 슬롯 총량, 횟수 차이 ≤1, 라운드별 선수·코트 중복을 검증했다. PRD 전체 조합/여러 seed의 전수 검증을 완료한 것은 아니다.
- `supabase/tests/verify_deployment.sql`: 이관 매핑 건수, 팀 구성 일치, 보관/비공개 테이블 권한 회수와 뷰 보안 속성을 읽기 전용으로 확인한다.
- Swift 모델 3개 파일을 `swiftc`로 컴파일했다. XCTest에 추가한 6개 모델 계약 검사는 XCTest가 없는 환경에서 동일 테스트 본문을 Foundation assertion 하네스로 실행해 통과했다. 전체 Xcode 앱 빌드·시뮬레이터·XCTest 실행은 개발 환경의 Xcode 부재로 미검증이다.

실제 두 트랜잭션을 동시에 실행하는 경합 부하 테스트는 미실행이다. 모임 행 잠금, 활성 코트 유일 인덱스, 지연 제약 트리거와 순차 충돌 테스트를 검증했다. 출시 전 동시 승인·시작·결과 정정 요청 경합 검증을 추가해야 한다.

## 운영 확인

원격 적용 후 기존 데이터 매핑 수와 팀 구성을 비교하고 SQL fixture가 남지 않았는지 확인한다. 계정 생성 뒤 운영자/회원/비소속 계정으로 권한을 다시 확인한다. `stale_schedule_version`, `stale_result_version`, `session_capacity_exceeded`, `participant_already_playing`은 클라이언트에서 재조회·거부 안내로 처리해야 하는 신호다. 예기치 않은 빈 목록·권한 거부·정정 후 통계 차이가 생기면 새 쓰기 경로를 중지하고 이관/권한 검증 SQL부터 실행한다.

보안 Advisor의 기존 SECURITY DEFINER 뷰 오류와 RLS 무정책 알림은 해소됐다. 현재 남은 보안 WARN은 authenticated 역할이 12개 조회 객체의 **GraphQL 스키마 구조**를 볼 수 있다는 진단이다. 실제 행은 RLS로 격리되며 비소속 거부 테스트가 통과했다. 스키마 자체를 숨겨야 한다면 조회 API와 GraphQL 노출 정책을 함께 결정해야 한다. 성능 Advisor의 FK 인덱스 누락도 해소됐으며 새/보관 인덱스의 미사용 INFO는 현재 데이터·트래픽에서 예상되는 알림이다.

원본 테이블은 백업 파일이나 복원 실증을 대체하지 않는다. 기존 보관 데이터를 삭제하는 롤백은 제공하지 않으며 새 쓰기 데이터가 생긴 뒤에는 삭제형 다운 마이그레이션 대신 전진 수정한다. 운영 배포 전 백업/실제 복원, Auth 공급자·계정 삭제 서버 경로, 게스트 웹 및 iOS 통합 검증은 별도 출시 조건이다.
