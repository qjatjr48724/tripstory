# Supabase

로컬 SQL은 `migrations/`에 두고, 대시보드 SQL Editor에서 순서대로 실행하거나 CLI로 적용합니다.

## 적용 방법 (대시보드)

1. [Supabase Dashboard](https://supabase.com/dashboard) → 프로젝트 선택
2. 왼쪽 **SQL Editor** → **New query**
3. 아래 파일을 **순서대로** 붙여넣고 Run (이미 적용한 것은 건너뛰어도 됨)
   1. `migrations/20260927214705_init_schema.sql`
   2. `migrations/20260927214706_travel_rpcs.sql`
   3. `migrations/20261001013000_member_rpcs.sql` (구성원/권한)
   4. `migrations/20261001014000_leave_travel_solo_owner.sql` (혼자인 여행장 나가기)
   5. (장소/승인 등 후속 마이그레이션이 있으면 이어서)
   6. **`migrations/20261007000000_travel_links_and_storage.sql`** (10단계: 링크 테이블 + Storage)
   7. **`migrations/20261007010000_reservation_linked_expense.sql`** (예약↔비용 연결)
4. **Table Editor**에서 `profiles`, `travels`, `travel_links` 등이 보이면 성공
5. **Storage**에 `travel-media` 버킷이 생겼는지 확인

## Auth 설정 (3단계 전에)

Authentication → Providers:

- Email: 켜기 (Confirm email 권장)
- Google / Apple: 앱 스토어·키 준비되면 추가

## Storage (10단계)

`20261007000000_travel_links_and_storage.sql` 적용 시 `travel-media` 버킷이 생성됩니다.  
경로: `{travelId}/reservations/...`, `{travelId}/photos/...` (비공개, 서명 URL로 조회)
