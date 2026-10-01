-- 초대코드 참여 = pending, 여행장 수락 후 active

-- pending 멤버도 본인 여행 SELECT 가능 (목록·대기 화면)
drop policy if exists travels_select_member on public.travels;
create policy travels_select_member on public.travels
  for select to authenticated
  using (
    public.is_travel_member(id)
    or exists (
      select 1
      from public.travel_members tm
      where tm.travel_id = travels.id
        and tm.user_id = auth.uid()
        and tm.status = 'pending'
    )
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

-- 초대코드로 참여 → pending 대기
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
  v_existing public.travel_members;
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

  select * into v_existing
  from public.travel_members
  where travel_id = v_travel.id and user_id = v_user
  limit 1;

  if v_existing.id is not null then
    if v_existing.status = 'active' then
      return v_travel;
    end if;

    -- left / kicked / pending → 다시 승인 대기
    update public.travel_members
    set status = 'pending',
        left_at = null,
        role = 'member',
        display_name_snapshot = coalesce(v_display_name, display_name_snapshot, '구성원'),
        updated_at = now()
    where id = v_existing.id;
  else
    insert into public.travel_members (
      travel_id, user_id, role, status, display_name_snapshot
    ) values (
      v_travel.id, v_user, 'member', 'pending', coalesce(v_display_name, '구성원')
    );
  end if;

  return v_travel;
end;
$$;

revoke all on function public.join_travel_by_invite(text) from public;
grant execute on function public.join_travel_by_invite(text) to authenticated;

-- 여행장: 참가 요청 수락
create or replace function public.accept_travel_join(p_member_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_target public.travel_members;
begin
  if auth.uid() is null then
    raise exception 'not authenticated';
  end if;

  select * into v_target
  from public.travel_members
  where id = p_member_id
  limit 1;

  if v_target.id is null then
    raise exception 'member not found';
  end if;

  if public.travel_member_role(v_target.travel_id) is distinct from 'owner' then
    raise exception 'only owner can accept join requests';
  end if;

  if v_target.status is distinct from 'pending' then
    raise exception 'member is not pending';
  end if;

  update public.travel_members
  set status = 'active',
      left_at = null,
      updated_at = now()
  where id = p_member_id;
end;
$$;

revoke all on function public.accept_travel_join(uuid) from public;
grant execute on function public.accept_travel_join(uuid) to authenticated;

-- 여행장: 참가 요청 거절 (행 삭제 → 재신청 가능)
create or replace function public.reject_travel_join(p_member_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_target public.travel_members;
begin
  if auth.uid() is null then
    raise exception 'not authenticated';
  end if;

  select * into v_target
  from public.travel_members
  where id = p_member_id
  limit 1;

  if v_target.id is null then
    raise exception 'member not found';
  end if;

  if public.travel_member_role(v_target.travel_id) is distinct from 'owner' then
    raise exception 'only owner can reject join requests';
  end if;

  if v_target.status is distinct from 'pending' then
    raise exception 'member is not pending';
  end if;

  delete from public.travel_members
  where id = p_member_id;
end;
$$;

revoke all on function public.reject_travel_join(uuid) from public;
grant execute on function public.reject_travel_join(uuid) to authenticated;
