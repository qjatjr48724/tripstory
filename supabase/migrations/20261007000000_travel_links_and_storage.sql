-- 10단계: 여행 링크 테이블 + 예약/사진 Storage 버킷
-- 대시보드 SQL Editor에서 이 파일을 실행한 뒤 앱을 사용하세요.

-- ---------------------------------------------------------------------------
-- travel_links
-- ---------------------------------------------------------------------------
create table if not exists public.travel_links (
  id uuid primary key default gen_random_uuid(),
  travel_id uuid not null references public.travels (id) on delete cascade,
  title text not null,
  url text not null,
  memo text,
  created_by_member_id uuid references public.travel_members (id) on delete set null,
  version integer not null default 1,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists travel_links_travel_idx on public.travel_links (travel_id);

drop trigger if exists travel_links_set_updated_at on public.travel_links;
create trigger travel_links_set_updated_at
  before update on public.travel_links
  for each row execute function public.set_updated_at();

alter table public.travel_links enable row level security;

grant select, insert, update, delete on public.travel_links to authenticated;

drop policy if exists travel_links_all_member on public.travel_links;
create policy travel_links_all_member on public.travel_links
  for all to authenticated
  using (public.is_travel_member(travel_id))
  with check (
    public.is_travel_member(travel_id)
    and public.is_travel_editable(travel_id)
  );

-- ---------------------------------------------------------------------------
-- Storage: travel-media (경로: {travelId}/reservations|photos/...)
-- ---------------------------------------------------------------------------
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'travel-media',
  'travel-media',
  false,
  5242880,
  array['image/jpeg', 'image/png', 'image/webp', 'image/heic']
)
on conflict (id) do update set
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists travel_media_select_member on storage.objects;
create policy travel_media_select_member on storage.objects
  for select to authenticated
  using (
    bucket_id = 'travel-media'
    and public.is_travel_member((string_to_array(name, '/'))[1]::uuid)
  );

drop policy if exists travel_media_insert_member on storage.objects;
create policy travel_media_insert_member on storage.objects
  for insert to authenticated
  with check (
    bucket_id = 'travel-media'
    and public.is_travel_member((string_to_array(name, '/'))[1]::uuid)
    and public.is_travel_editable((string_to_array(name, '/'))[1]::uuid)
  );

drop policy if exists travel_media_update_member on storage.objects;
create policy travel_media_update_member on storage.objects
  for update to authenticated
  using (
    bucket_id = 'travel-media'
    and public.is_travel_member((string_to_array(name, '/'))[1]::uuid)
    and public.is_travel_editable((string_to_array(name, '/'))[1]::uuid)
  )
  with check (
    bucket_id = 'travel-media'
    and public.is_travel_member((string_to_array(name, '/'))[1]::uuid)
    and public.is_travel_editable((string_to_array(name, '/'))[1]::uuid)
  );

drop policy if exists travel_media_delete_member on storage.objects;
create policy travel_media_delete_member on storage.objects
  for delete to authenticated
  using (
    bucket_id = 'travel-media'
    and public.is_travel_member((string_to_array(name, '/'))[1]::uuid)
    and public.is_travel_editable((string_to_array(name, '/'))[1]::uuid)
  );
