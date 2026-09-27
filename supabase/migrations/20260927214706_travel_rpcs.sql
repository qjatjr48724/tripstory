-- tripstory: 여행 생성 시 owner 멤버 + 초대코드 자동 부여
create or replace function public.create_travel(
  p_name text,
  p_start_date date,
  p_end_date date,
  p_region text,
  p_memo text default null
)
returns public.travels
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user uuid := auth.uid();
  v_travel public.travels;
  v_code text;
  v_display_name text;
  v_attempts int := 0;
begin
  if v_user is null then
    raise exception 'not authenticated';
  end if;

  if p_end_date < p_start_date then
    raise exception 'end_date must be >= start_date';
  end if;

  select display_name into v_display_name
  from public.profiles
  where id = v_user;

  loop
    v_code := public.generate_invite_code();
    v_attempts := v_attempts + 1;
    exit when not exists (
      select 1 from public.travels t
      where t.invite_code = v_code and t.status = 'active'
    ) or v_attempts > 20;
  end loop;

  insert into public.travels (
    name, start_date, end_date, region, memo,
    created_by, invite_code, status
  )
  values (
    p_name, p_start_date, p_end_date, p_region, p_memo,
    v_user, v_code, 'active'
  )
  returning * into v_travel;

  insert into public.travel_members (
    travel_id, user_id, role, status, display_name_snapshot, color_hex
  )
  values (
    v_travel.id,
    v_user,
    'owner',
    'active',
    coalesce(v_display_name, '여행장'),
    '#0D7377'
  );

  return v_travel;
end;
$$;

revoke all on function public.create_travel(text, date, date, text, text) from public;
grant execute on function public.create_travel(text, date, date, text, text) to authenticated;

-- 초대코드로 여행 참여
create or replace function public.join_travel_by_invite(p_invite_code text)
returns public.travels
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user uuid := auth.uid();
  v_travel public.travels;
  v_display_name text;
  v_existing uuid;
begin
  if v_user is null then
    raise exception 'not authenticated';
  end if;

  select * into v_travel
  from public.travels t
  where t.invite_code = p_invite_code
    and t.status = 'active'
    and (t.invite_code_expires_at is null or t.invite_code_expires_at > now())
  limit 1;

  if v_travel.id is null then
    raise exception 'invalid or expired invite code';
  end if;

  select display_name into v_display_name
  from public.profiles where id = v_user;

  select id into v_existing
  from public.travel_members
  where travel_id = v_travel.id and user_id = v_user
  limit 1;

  if v_existing is not null then
    update public.travel_members
    set status = 'active',
        left_at = null,
        updated_at = now()
    where id = v_existing;
  else
    insert into public.travel_members (
      travel_id, user_id, role, status, display_name_snapshot
    ) values (
      v_travel.id, v_user, 'member', 'active', coalesce(v_display_name, '구성원')
    );
  end if;

  return v_travel;
end;
$$;

revoke all on function public.join_travel_by_invite(text) from public;
grant execute on function public.join_travel_by_invite(text) to authenticated;
