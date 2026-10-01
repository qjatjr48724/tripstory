-- 해외(Google) 장소의 정확한 지도 링크를 열기 위한 식별자/URL
alter table public.places
  add column if not exists google_place_id text;

alter table public.places
  add column if not exists maps_url text;
