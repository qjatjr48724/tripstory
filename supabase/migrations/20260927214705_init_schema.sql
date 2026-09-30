-- tripstory 초기 스키마
-- 제안서 17절 데이터 모델링 + RLS + 권한 헬퍼
-- Supabase Dashboard → SQL Editor 에서 실행하거나
-- `npx supabase db push` (CLI 연동 시) 로 적용한다.

-- ---------------------------------------------------------------------------
-- Extensions
-- ---------------------------------------------------------------------------
create extension if not exists "pgcrypto";

-- ---------------------------------------------------------------------------
-- Enums
-- ---------------------------------------------------------------------------
do $$ begin
  create type public.travel_status as enum ('active', 'completed', 'trashed');
exception when duplicate_object then null;
end $$;

do $$ begin
  create type public.member_role as enum ('member', 'treasurer', 'owner');
exception when duplicate_object then null;
end $$;

do $$ begin
  create type public.member_status as enum ('active', 'left', 'kicked');
exception when duplicate_object then null;
end $$;

do $$ begin
  create type public.expense_category as enum (
    'food', 'transport', 'lodging', 'sightseeing', 'shopping', 'prep', 'other'
  );
exception when duplicate_object then null;
end $$;

do $$ begin
  create type public.payment_method as enum ('cash', 'card', 'mobile', 'other');
exception when duplicate_object then null;
end $$;

do $$ begin
  create type public.split_type as enum ('equal', 'custom');
exception when duplicate_object then null;
end $$;

do $$ begin
  create type public.expense_settlement_status as enum ('in_progress', 'completed');
exception when duplicate_object then null;
end $$;

do $$ begin
  create type public.fx_source as enum ('payment_time', 'settlement_time', 'manual');
exception when duplicate_object then null;
end $$;

do $$ begin
  create type public.reservation_type as enum ('transport', 'lodging', 'other');
exception when duplicate_object then null;
end $$;

do $$ begin
  create type public.notification_type as enum (
    'schedule_start',
    'reservation_start',
    'settlement_request',
    'settlement_done',
    'travel_invite',
    'ownership_transfer',
    'travel_complete_soon'
  );
exception when duplicate_object then null;
end $$;

-- ---------------------------------------------------------------------------
-- profiles (auth.users 확장)
-- ---------------------------------------------------------------------------
create table if not exists public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  display_name text not null,
  avatar_url text,
  contact text,
  bio text,
  -- 계정 전역 알림 on/off (카테고리별)
  notify_schedule_start boolean not null default true,
  notify_reservation_start boolean not null default true,
  notify_settlement boolean not null default true,
  notify_invite boolean not null default true,
  notify_ownership_transfer boolean not null default true,
  notify_travel_complete_soon boolean not null default true,
  deleted_at timestamptz,
  recovery_until timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- ---------------------------------------------------------------------------
-- travels
-- ---------------------------------------------------------------------------
create table if not exists public.travels (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  start_date date not null,
  end_date date not null,
  region text not null,
  memo text,
  status public.travel_status not null default 'active',
  invite_code text,
  invite_code_expires_at timestamptz,
  completed_at timestamptz,
  trashed_at timestamptz,
  trash_purge_at timestamptz,
  created_by uuid references public.profiles (id) on delete set null,
  version integer not null default 1,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint travels_date_range check (end_date >= start_date),
  constraint travels_invite_code_len check (
    invite_code is null or char_length(invite_code) = 6
  )
);

-- now() 는 IMMUTABLE이 아니므로 인덱스 predicate에 넣을 수 없다.
-- 만료는 join_travel_by_invite 등 쿼리에서 검사한다.
create unique index if not exists travels_invite_code_active_uidx
  on public.travels (invite_code)
  where invite_code is not null
    and status = 'active';

create index if not exists travels_status_idx on public.travels (status);

-- ---------------------------------------------------------------------------
-- travel_members
-- ---------------------------------------------------------------------------
create table if not exists public.travel_members (
  id uuid primary key default gen_random_uuid(),
  travel_id uuid not null references public.travels (id) on delete cascade,
  user_id uuid references public.profiles (id) on delete set null,
  role public.member_role not null default 'member',
  status public.member_status not null default 'active',
  display_name_snapshot text not null,
  color_hex text not null default '#0D7377',
  -- 가입 시점 프로필 공개 설정 스냅샷 (소급 미적용)
  show_contact boolean not null default false,
  show_bio boolean not null default false,
  joined_at timestamptz not null default now(),
  left_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint travel_members_one_active_user unique (travel_id, user_id)
);

create index if not exists travel_members_travel_idx
  on public.travel_members (travel_id);
create index if not exists travel_members_user_idx
  on public.travel_members (user_id);

-- 여행당 active owner 1명
create unique index if not exists travel_members_one_owner_uidx
  on public.travel_members (travel_id)
  where role = 'owner' and status = 'active';

-- ---------------------------------------------------------------------------
-- places (장소 후보) — 작성자는 member id로 보존
-- ---------------------------------------------------------------------------
create table if not exists public.places (
  id uuid primary key default gen_random_uuid(),
  travel_id uuid not null references public.travels (id) on delete cascade,
  created_by_member_id uuid not null references public.travel_members (id) on delete restrict,
  name text not null,
  address text,
  country_code text,
  latitude double precision,
  longitude double precision,
  memo text,
  version integer not null default 1,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists places_travel_idx on public.places (travel_id);

-- ---------------------------------------------------------------------------
-- schedules
-- ---------------------------------------------------------------------------
create table if not exists public.schedules (
  id uuid primary key default gen_random_uuid(),
  travel_id uuid not null references public.travels (id) on delete cascade,
  place_id uuid references public.places (id) on delete set null,
  schedule_date date not null,
  start_time time,
  sort_order integer not null default 0,
  title text not null,
  memo text,
  is_visited boolean not null default false,
  version integer not null default 1,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists schedules_travel_date_idx
  on public.schedules (travel_id, schedule_date, sort_order);

-- ---------------------------------------------------------------------------
-- plan_b (일정당 최대 2개)
-- ---------------------------------------------------------------------------
create table if not exists public.plan_b (
  id uuid primary key default gen_random_uuid(),
  schedule_id uuid not null references public.schedules (id) on delete cascade,
  place_id uuid not null references public.places (id) on delete cascade,
  slot smallint not null check (slot in (1, 2)),
  created_at timestamptz not null default now(),
  constraint plan_b_schedule_slot unique (schedule_id, slot)
);

-- ---------------------------------------------------------------------------
-- expenses
-- ---------------------------------------------------------------------------
create table if not exists public.expenses (
  id uuid primary key default gen_random_uuid(),
  travel_id uuid not null references public.travels (id) on delete cascade,
  category public.expense_category not null default 'other',
  description text,
  amount integer not null check (amount >= 0),
  currency text not null default 'KRW',
  payer_member_id uuid not null references public.travel_members (id) on delete restrict,
  payment_method public.payment_method not null default 'card',
  paid_at timestamptz not null default now(),
  split_type public.split_type not null default 'equal',
  exclude_from_settlement boolean not null default false,
  settlement_status public.expense_settlement_status not null default 'in_progress',
  -- 환율 스냅샷 (거래 당시 값 보존)
  fx_to_krw numeric(18, 6),
  fx_source public.fx_source not null default 'payment_time',
  fx_rate_date date,
  undistributed_remainder integer not null default 0 check (undistributed_remainder >= 0),
  version integer not null default 1,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists expenses_travel_idx on public.expenses (travel_id);

-- ---------------------------------------------------------------------------
-- expense_participants
-- ---------------------------------------------------------------------------
create table if not exists public.expense_participants (
  id uuid primary key default gen_random_uuid(),
  expense_id uuid not null references public.expenses (id) on delete cascade,
  member_id uuid not null references public.travel_members (id) on delete restrict,
  share_amount integer not null default 0 check (share_amount >= 0),
  created_at timestamptz not null default now(),
  constraint expense_participants_unique unique (expense_id, member_id)
);

-- ---------------------------------------------------------------------------
-- settlements (송금 / 수령)
-- ---------------------------------------------------------------------------
create table if not exists public.settlements (
  id uuid primary key default gen_random_uuid(),
  travel_id uuid not null references public.travels (id) on delete cascade,
  from_member_id uuid not null references public.travel_members (id) on delete restrict,
  to_member_id uuid not null references public.travel_members (id) on delete restrict,
  amount integer not null check (amount > 0),
  currency text not null default 'KRW',
  sent_confirmed boolean not null default false,
  received_confirmed boolean not null default false,
  sent_at timestamptz,
  received_at timestamptz,
  sent_by_proxy_member_id uuid references public.travel_members (id) on delete set null,
  received_by_proxy_member_id uuid references public.travel_members (id) on delete set null,
  version integer not null default 1,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint settlements_not_self check (from_member_id <> to_member_id)
);

create index if not exists settlements_travel_idx on public.settlements (travel_id);

-- ---------------------------------------------------------------------------
-- reservations
-- ---------------------------------------------------------------------------
create table if not exists public.reservations (
  id uuid primary key default gen_random_uuid(),
  travel_id uuid not null references public.travels (id) on delete cascade,
  type public.reservation_type not null,
  title text not null,
  booker_member_id uuid references public.travel_members (id) on delete set null,
  confirmation_number text,
  cost_amount integer,
  cost_currency text default 'KRW',
  starts_at timestamptz,
  confirmation_url text,
  memo text,
  -- lodging extras
  lodging_address text,
  lodging_room_info text,
  version integer not null default 1,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists reservations_travel_idx on public.reservations (travel_id);

-- ---------------------------------------------------------------------------
-- reservation_images
-- ---------------------------------------------------------------------------
create table if not exists public.reservation_images (
  id uuid primary key default gen_random_uuid(),
  reservation_id uuid not null references public.reservations (id) on delete cascade,
  storage_path text not null,
  created_by_member_id uuid references public.travel_members (id) on delete set null,
  created_at timestamptz not null default now()
);

-- ---------------------------------------------------------------------------
-- travel_photos
-- ---------------------------------------------------------------------------
create table if not exists public.travel_photos (
  id uuid primary key default gen_random_uuid(),
  travel_id uuid not null references public.travels (id) on delete cascade,
  storage_path text not null,
  title text,
  memo text,
  uploaded_by_member_id uuid references public.travel_members (id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists travel_photos_travel_idx on public.travel_photos (travel_id);

-- ---------------------------------------------------------------------------
-- backups (여행당 최대 3개는 앱/트리거에서 강제)
-- ---------------------------------------------------------------------------
create table if not exists public.backups (
  id uuid primary key default gen_random_uuid(),
  travel_id uuid not null references public.travels (id) on delete cascade,
  name text not null,
  snapshot jsonb not null,
  created_by uuid references public.profiles (id) on delete set null,
  created_at timestamptz not null default now()
);

create index if not exists backups_travel_created_idx
  on public.backups (travel_id, created_at desc);

-- ---------------------------------------------------------------------------
-- ownership_transfer_requests
-- ---------------------------------------------------------------------------
create table if not exists public.ownership_transfer_requests (
  id uuid primary key default gen_random_uuid(),
  travel_id uuid not null references public.travels (id) on delete cascade,
  from_member_id uuid not null references public.travel_members (id) on delete cascade,
  to_member_id uuid not null references public.travel_members (id) on delete cascade,
  from_accepted boolean not null default true,
  to_accepted boolean not null default false,
  status text not null default 'pending' check (status in ('pending', 'accepted', 'cancelled')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- ---------------------------------------------------------------------------
-- notifications
-- ---------------------------------------------------------------------------
create table if not exists public.notifications (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles (id) on delete cascade,
  travel_id uuid references public.travels (id) on delete cascade,
  type public.notification_type not null,
  title text not null,
  body text,
  payload jsonb,
  scheduled_for timestamptz,
  sent_at timestamptz,
  read_at timestamptz,
  created_at timestamptz not null default now()
);

create index if not exists notifications_user_idx
  on public.notifications (user_id, created_at desc);

-- ---------------------------------------------------------------------------
-- exchange_rates (하루 1회 갱신 캐시)
-- ---------------------------------------------------------------------------
create table if not exists public.exchange_rates (
  id uuid primary key default gen_random_uuid(),
  base_currency text not null default 'KRW',
  quote_currency text not null,
  rate numeric(18, 6) not null,
  rate_date date not null,
  source text not null default 'koreaexim',
  created_at timestamptz not null default now(),
  constraint exchange_rates_unique unique (base_currency, quote_currency, rate_date)
);

-- ---------------------------------------------------------------------------
-- updated_at helper
-- ---------------------------------------------------------------------------
create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists profiles_set_updated_at on public.profiles;
create trigger profiles_set_updated_at
  before update on public.profiles
  for each row execute function public.set_updated_at();

drop trigger if exists travels_set_updated_at on public.travels;
create trigger travels_set_updated_at
  before update on public.travels
  for each row execute function public.set_updated_at();

drop trigger if exists travel_members_set_updated_at on public.travel_members;
create trigger travel_members_set_updated_at
  before update on public.travel_members
  for each row execute function public.set_updated_at();

drop trigger if exists places_set_updated_at on public.places;
create trigger places_set_updated_at
  before update on public.places
  for each row execute function public.set_updated_at();

drop trigger if exists schedules_set_updated_at on public.schedules;
create trigger schedules_set_updated_at
  before update on public.schedules
  for each row execute function public.set_updated_at();

drop trigger if exists expenses_set_updated_at on public.expenses;
create trigger expenses_set_updated_at
  before update on public.expenses
  for each row execute function public.set_updated_at();

drop trigger if exists settlements_set_updated_at on public.settlements;
create trigger settlements_set_updated_at
  before update on public.settlements
  for each row execute function public.set_updated_at();

drop trigger if exists reservations_set_updated_at on public.reservations;
create trigger reservations_set_updated_at
  before update on public.reservations
  for each row execute function public.set_updated_at();

drop trigger if exists travel_photos_set_updated_at on public.travel_photos;
create trigger travel_photos_set_updated_at
  before update on public.travel_photos
  for each row execute function public.set_updated_at();

-- ---------------------------------------------------------------------------
-- 회원가입 시 프로필 자동 생성
-- ---------------------------------------------------------------------------
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.profiles (id, display_name)
  values (
    new.id,
    coalesce(
      new.raw_user_meta_data ->> 'display_name',
      new.raw_user_meta_data ->> 'full_name',
      new.raw_user_meta_data ->> 'name',
      split_part(new.email, '@', 1),
      '여행자'
    )
  )
  on conflict (id) do nothing;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- ---------------------------------------------------------------------------
-- 초대코드 생성 (6자리, 대소문자+숫자)
-- ---------------------------------------------------------------------------
create or replace function public.generate_invite_code()
returns text
language plpgsql
as $$
declare
  chars text := 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';
  result text := '';
  i int;
begin
  for i in 1..6 loop
    result := result || substr(chars, 1 + floor(random() * 62)::int, 1);
  end loop;
  return result;
end;
$$;

-- ---------------------------------------------------------------------------
-- RLS 헬퍼 (security definer로 순환 정책 방지)
-- ---------------------------------------------------------------------------
create or replace function public.is_travel_member(p_travel_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.travel_members tm
    where tm.travel_id = p_travel_id
      and tm.user_id = auth.uid()
      and tm.status = 'active'
  );
$$;

create or replace function public.travel_member_role(p_travel_id uuid)
returns public.member_role
language sql
stable
security definer
set search_path = public
as $$
  select tm.role
  from public.travel_members tm
  where tm.travel_id = p_travel_id
    and tm.user_id = auth.uid()
    and tm.status = 'active'
  limit 1;
$$;

create or replace function public.is_travel_editable(p_travel_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.travels t
    where t.id = p_travel_id
      and t.status = 'active'
  );
$$;

create or replace function public.my_member_id(p_travel_id uuid)
returns uuid
language sql
stable
security definer
set search_path = public
as $$
  select tm.id
  from public.travel_members tm
  where tm.travel_id = p_travel_id
    and tm.user_id = auth.uid()
    and tm.status = 'active'
  limit 1;
$$;

-- ---------------------------------------------------------------------------
-- RLS enable
-- ---------------------------------------------------------------------------
alter table public.profiles enable row level security;
alter table public.travels enable row level security;
alter table public.travel_members enable row level security;
alter table public.places enable row level security;
alter table public.schedules enable row level security;
alter table public.plan_b enable row level security;
alter table public.expenses enable row level security;
alter table public.expense_participants enable row level security;
alter table public.settlements enable row level security;
alter table public.reservations enable row level security;
alter table public.reservation_images enable row level security;
alter table public.travel_photos enable row level security;
alter table public.backups enable row level security;
alter table public.ownership_transfer_requests enable row level security;
alter table public.notifications enable row level security;
alter table public.exchange_rates enable row level security;

-- ---------------------------------------------------------------------------
-- Grants (Automatically expose 끈 경우 수동 부여 필요)
-- ---------------------------------------------------------------------------
grant usage on schema public to anon, authenticated;

grant select, update on public.profiles to authenticated;
grant select, insert, update, delete on public.travels to authenticated;
grant select, insert, update, delete on public.travel_members to authenticated;
grant select, insert, update, delete on public.places to authenticated;
grant select, insert, update, delete on public.schedules to authenticated;
grant select, insert, update, delete on public.plan_b to authenticated;
grant select, insert, update, delete on public.expenses to authenticated;
grant select, insert, update, delete on public.expense_participants to authenticated;
grant select, insert, update, delete on public.settlements to authenticated;
grant select, insert, update, delete on public.reservations to authenticated;
grant select, insert, update, delete on public.reservation_images to authenticated;
grant select, insert, update, delete on public.travel_photos to authenticated;
grant select, insert, update, delete on public.backups to authenticated;
grant select, insert, update, delete on public.ownership_transfer_requests to authenticated;
grant select, update on public.notifications to authenticated;
grant select on public.exchange_rates to authenticated, anon;

-- ---------------------------------------------------------------------------
-- Policies: profiles
-- ---------------------------------------------------------------------------
drop policy if exists profiles_select_self_or_fellow on public.profiles;
create policy profiles_select_self_or_fellow on public.profiles
  for select to authenticated
  using (
    id = auth.uid()
    or exists (
      select 1
      from public.travel_members me
      join public.travel_members other
        on other.travel_id = me.travel_id
       and other.status = 'active'
      where me.user_id = auth.uid()
        and me.status = 'active'
        and other.user_id = profiles.id
    )
  );

drop policy if exists profiles_update_self on public.profiles;
create policy profiles_update_self on public.profiles
  for update to authenticated
  using (id = auth.uid())
  with check (id = auth.uid());

-- ---------------------------------------------------------------------------
-- Policies: travels
-- ---------------------------------------------------------------------------
drop policy if exists travels_select_member on public.travels;
create policy travels_select_member on public.travels
  for select to authenticated
  using (
    public.is_travel_member(id)
    or (
      status = 'trashed'
      and exists (
        select 1 from public.travel_members tm
        where tm.travel_id = travels.id
          and tm.user_id = auth.uid()
          and tm.role = 'owner'
      )
    )
  );

drop policy if exists travels_insert_authenticated on public.travels;
create policy travels_insert_authenticated on public.travels
  for insert to authenticated
  with check (created_by = auth.uid());

drop policy if exists travels_update_member on public.travels;
create policy travels_update_member on public.travels
  for update to authenticated
  using (public.is_travel_member(id))
  with check (public.is_travel_member(id));

drop policy if exists travels_delete_owner on public.travels;
create policy travels_delete_owner on public.travels
  for delete to authenticated
  using (public.travel_member_role(id) = 'owner');

-- ---------------------------------------------------------------------------
-- Policies: travel_members
-- ---------------------------------------------------------------------------
drop policy if exists travel_members_select on public.travel_members;
create policy travel_members_select on public.travel_members
  for select to authenticated
  using (public.is_travel_member(travel_id) or user_id = auth.uid());

drop policy if exists travel_members_insert on public.travel_members;
create policy travel_members_insert on public.travel_members
  for insert to authenticated
  with check (
    -- 생성자가 본인을 owner로 넣거나, 초대코드 참여(앱 RPC에서 처리) 시
    user_id = auth.uid()
    or public.travel_member_role(travel_id) = 'owner'
  );

drop policy if exists travel_members_update on public.travel_members;
create policy travel_members_update on public.travel_members
  for update to authenticated
  using (
    user_id = auth.uid()
    or public.travel_member_role(travel_id) = 'owner'
  )
  with check (
    user_id = auth.uid()
    or public.travel_member_role(travel_id) = 'owner'
  );

-- ---------------------------------------------------------------------------
-- Policies: places / schedules / plan_b (구성원이면 조회, 편집은 active만)
-- ---------------------------------------------------------------------------
drop policy if exists places_all_member on public.places;
create policy places_all_member on public.places
  for all to authenticated
  using (public.is_travel_member(travel_id))
  with check (
    public.is_travel_member(travel_id)
    and public.is_travel_editable(travel_id)
  );

drop policy if exists schedules_all_member on public.schedules;
create policy schedules_all_member on public.schedules
  for all to authenticated
  using (public.is_travel_member(travel_id))
  with check (
    public.is_travel_member(travel_id)
    and public.is_travel_editable(travel_id)
  );

drop policy if exists plan_b_all_member on public.plan_b;
create policy plan_b_all_member on public.plan_b
  for all to authenticated
  using (
    exists (
      select 1 from public.schedules s
      where s.id = plan_b.schedule_id
        and public.is_travel_member(s.travel_id)
    )
  )
  with check (
    exists (
      select 1 from public.schedules s
      where s.id = plan_b.schedule_id
        and public.is_travel_member(s.travel_id)
        and public.is_travel_editable(s.travel_id)
    )
  );

-- ---------------------------------------------------------------------------
-- Policies: expenses / participants / settlements
-- ---------------------------------------------------------------------------
drop policy if exists expenses_all_member on public.expenses;
create policy expenses_all_member on public.expenses
  for all to authenticated
  using (public.is_travel_member(travel_id))
  with check (
    public.is_travel_member(travel_id)
    and public.is_travel_editable(travel_id)
  );

drop policy if exists expense_participants_all_member on public.expense_participants;
create policy expense_participants_all_member on public.expense_participants
  for all to authenticated
  using (
    exists (
      select 1 from public.expenses e
      where e.id = expense_participants.expense_id
        and public.is_travel_member(e.travel_id)
    )
  )
  with check (
    exists (
      select 1 from public.expenses e
      where e.id = expense_participants.expense_id
        and public.is_travel_member(e.travel_id)
        and public.is_travel_editable(e.travel_id)
    )
  );

drop policy if exists settlements_all_member on public.settlements;
create policy settlements_all_member on public.settlements
  for all to authenticated
  using (public.is_travel_member(travel_id))
  with check (
    public.is_travel_member(travel_id)
    and public.is_travel_editable(travel_id)
  );

-- ---------------------------------------------------------------------------
-- Policies: reservations / images / photos / backups
-- ---------------------------------------------------------------------------
drop policy if exists reservations_all_member on public.reservations;
create policy reservations_all_member on public.reservations
  for all to authenticated
  using (public.is_travel_member(travel_id))
  with check (
    public.is_travel_member(travel_id)
    and public.is_travel_editable(travel_id)
  );

drop policy if exists reservation_images_all_member on public.reservation_images;
create policy reservation_images_all_member on public.reservation_images
  for all to authenticated
  using (
    exists (
      select 1 from public.reservations r
      where r.id = reservation_images.reservation_id
        and public.is_travel_member(r.travel_id)
    )
  )
  with check (
    exists (
      select 1 from public.reservations r
      where r.id = reservation_images.reservation_id
        and public.is_travel_member(r.travel_id)
        and public.is_travel_editable(r.travel_id)
    )
  );

drop policy if exists travel_photos_all_member on public.travel_photos;
create policy travel_photos_all_member on public.travel_photos
  for all to authenticated
  using (public.is_travel_member(travel_id))
  with check (
    public.is_travel_member(travel_id)
    and public.is_travel_editable(travel_id)
  );

drop policy if exists backups_member_select on public.backups;
create policy backups_member_select on public.backups
  for select to authenticated
  using (public.is_travel_member(travel_id));

drop policy if exists backups_owner_write on public.backups;
create policy backups_owner_write on public.backups
  for all to authenticated
  using (public.travel_member_role(travel_id) = 'owner')
  with check (
    public.travel_member_role(travel_id) = 'owner'
    and public.is_travel_editable(travel_id)
  );

-- ---------------------------------------------------------------------------
-- Policies: ownership transfer / notifications / rates
-- ---------------------------------------------------------------------------
drop policy if exists ownership_transfer_member on public.ownership_transfer_requests;
create policy ownership_transfer_member on public.ownership_transfer_requests
  for all to authenticated
  using (public.is_travel_member(travel_id))
  with check (public.is_travel_member(travel_id));

drop policy if exists notifications_own on public.notifications;
create policy notifications_own on public.notifications
  for select to authenticated
  using (user_id = auth.uid());

drop policy if exists notifications_update_own on public.notifications;
create policy notifications_update_own on public.notifications
  for update to authenticated
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

drop policy if exists exchange_rates_read on public.exchange_rates;
create policy exchange_rates_read on public.exchange_rates
  for select to authenticated, anon
  using (true);
