# Supabase

로컬 SQL은 `migrations/`에 두고, 대시보드 SQL Editor에서 순서대로 실행하거나 CLI로 적용합니다.

## 적용 방법 (대시보드)

1. [Supabase Dashboard](https://supabase.com/dashboard) → 프로젝트 선택
2. 왼쪽 **SQL Editor** → **New query**
3. 아래 파일을 **순서대로** 붙여넣고 Run
   1. `migrations/20260927214705_init_schema.sql`
   2. `migrations/20260927214706_travel_rpcs.sql`
   3. `migrations/20261001013000_member_rpcs.sql` (구성원/권한)
   4. `migrations/20261001014000_leave_travel_solo_owner.sql` (혼자인 여행장 나가기)
4. **Table Editor**에서 `profiles`, `travels` 등이 보이면 성공

## Auth 설정 (3단계 전에)

Authentication → Providers:

- Email: 켜기 (Confirm email 권장)
- Google / Apple: 앱 스토어·키 준비되면 추가

## Storage (이후 단계)

예약 이미지 / 여행 사진용 버킷은 10단계에서 추가합니다.
