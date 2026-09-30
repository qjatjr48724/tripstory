-- tripstory: 구성원 / 권한 RPC (5단계)
-- SQL Editor에서 실행

-- ---------------------------------------------------------------------------
-- 초대코드 재발급 (여행장)
-- ---------------------------------------------------------------------------
create or replace function public.reissue_invite_code(p_travel_id uuid)
returns public.travels
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user uuid := auth.uid();
  v_travel public.travels;
  v_code text;
  v_attempts int := 0;
begin
  if v_user is null then
    raise exception 'not authenticated';
  end if;

  if public.travel_member_role(p_travel_id) is distinct from 'owner' then
    raise exception 'only owner can reissue invite code';
  end if;

  if not public.is_travel_editable(p_travel_id) then
    raise exception 'travel is not editable';
  end if;

  loop
    v_code := public.generate_invite_code();
    v_attempts := v_attempts + 1;
    exit when not exists (
      select 1 from public.travels t
      where t.invite_code = v_code and t.status = 'active' and t.id <> p_travel_id
    ) or v_attempts > 20;
  end loop;

  update public.travels
  set invite_code = v_code,
      invite_code_expires_at = null,
      updated_at = now()
  where id = p_travel_id
  returning * into v_travel;

  return v_travel;
end;
$$;

revoke all on function public.reissue_invite_code(uuid) from public;
grant execute on function public.reissue_invite_code(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- 총무 지정 / 해제 (여행장)
-- p_member_id 가 null 이면 총무 해제(기존 총무 → 구성원)
-- ---------------------------------------------------------------------------
create or replace function public.assign_treasurer(
  p_travel_id uuid,
  p_member_id uuid default null
)
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

  if public.travel_member_role(p_travel_id) is distinct from 'owner' then
    raise exception 'only owner can assign treasurer';
  end if;

  if not public.is_travel_editable(p_travel_id) then
    raise exception 'travel is not editable';
  end if;

  -- 기존 총무 → 구성원
  update public.travel_members
  set role = 'member', updated_at = now()
  where travel_id = p_travel_id
    and role = 'treasurer'
    and status = 'active';

  if p_member_id is null then
    return;
  end if;

  select * into v_target
  from public.travel_members
  where id = p_member_id
    and travel_id = p_travel_id
    and status = 'active';

  if v_target.id is null then
    raise exception 'member not found';
  end if;

  if v_target.role = 'owner' then
    raise exception 'cannot assign owner as treasurer';
  end if;

  update public.travel_members
  set role = 'treasurer', updated_at = now()
  where id = p_member_id;
end;
$$;

revoke all on function public.assign_treasurer(uuid, uuid) from public;
grant execute on function public.assign_treasurer(uuid, uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- 강제 퇴장 (여행장)
-- ---------------------------------------------------------------------------
create or replace function public.kick_member(
  p_travel_id uuid,
  p_member_id uuid
)
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

  if public.travel_member_role(p_travel_id) is distinct from 'owner' then
    raise exception 'only owner can kick member';
  end if;

  if not public.is_travel_editable(p_travel_id) then
    raise exception 'travel is not editable';
  end if;

  select * into v_target
  from public.travel_members
  where id = p_member_id
    and travel_id = p_travel_id
    and status = 'active';

  if v_target.id is null then
    raise exception 'member not found';
  end if;

  if v_target.role = 'owner' then
    raise exception 'cannot kick owner';
  end if;

  if v_target.user_id = auth.uid() then
    raise exception 'cannot kick yourself';
  end if;

  update public.travel_members
  set status = 'kicked',
      left_at = now(),
      updated_at = now()
  where id = p_member_id;

  -- 진행 중 여행장 이전 요청 취소
  update public.ownership_transfer_requests
  set status = 'cancelled', updated_at = now()
  where travel_id = p_travel_id
    and status = 'pending'
    and (from_member_id = p_member_id or to_member_id = p_member_id);
end;
$$;

revoke all on function public.kick_member(uuid, uuid) from public;
grant execute on function public.kick_member(uuid, uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- 자발적 나가기
-- 여행장은 다른 구성원이 있으면 이전 후 나가기.
-- 혼자이면 나가면서 여행을 휴지통으로 옮긴다.
-- ---------------------------------------------------------------------------
create or replace function public.leave_travel(p_travel_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_me public.travel_members;
  v_other_count int;
begin
  if auth.uid() is null then
    raise exception 'not authenticated';
  end if;

  select * into v_me
  from public.travel_members
  where travel_id = p_travel_id
    and user_id = auth.uid()
    and status = 'active';

  if v_me.id is null then
    raise exception 'not a member';
  end if;

  if not public.is_travel_editable(p_travel_id) then
    raise exception 'travel is not editable';
  end if;

  select count(*) into v_other_count
  from public.travel_members
  where travel_id = p_travel_id
    and status = 'active'
    and id <> v_me.id;

  if v_me.role = 'owner' and v_other_count > 0 then
    raise exception 'owner must transfer ownership before leaving';
  end if;

  update public.travel_members
  set status = 'left',
      left_at = now(),
      updated_at = now()
  where id = v_me.id;

  update public.ownership_transfer_requests
  set status = 'cancelled', updated_at = now()
  where travel_id = p_travel_id
    and status = 'pending'
    and (from_member_id = v_me.id or to_member_id = v_me.id);

  if v_other_count = 0 then
    update public.travels
    set status = 'trashed',
        trashed_at = now(),
        trash_purge_at = now() + interval '7 days',
        invite_code = null,
        invite_code_expires_at = null,
        updated_at = now()
    where id = p_travel_id;
  end if;
end;
$$;

revoke all on function public.leave_travel(uuid) from public;
grant execute on function public.leave_travel(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- 여행장 이전 요청
-- ---------------------------------------------------------------------------
create or replace function public.request_ownership_transfer(
  p_travel_id uuid,
  p_to_member_id uuid
)
returns public.ownership_transfer_requests
language plpgsql
security definer
set search_path = public
as $$
declare
  v_from public.travel_members;
  v_to public.travel_members;
  v_req public.ownership_transfer_requests;
begin
  if auth.uid() is null then
    raise exception 'not authenticated';
  end if;

  if public.travel_member_role(p_travel_id) is distinct from 'owner' then
    raise exception 'only owner can request ownership transfer';
  end if;

  if not public.is_travel_editable(p_travel_id) then
    raise exception 'travel is not editable';
  end if;

  select * into v_from
  from public.travel_members
  where travel_id = p_travel_id
    and user_id = auth.uid()
    and status = 'active'
    and role = 'owner';

  select * into v_to
  from public.travel_members
  where id = p_to_member_id
    and travel_id = p_travel_id
    and status = 'active';

  if v_to.id is null then
    raise exception 'member not found';
  end if;

  if v_to.id = v_from.id then
    raise exception 'cannot transfer to yourself';
  end if;

  -- 기존 pending 취소
  update public.ownership_transfer_requests
  set status = 'cancelled', updated_at = now()
  where travel_id = p_travel_id and status = 'pending';

  insert into public.ownership_transfer_requests (
    travel_id, from_member_id, to_member_id,
    from_accepted, to_accepted, status
  )
  values (
    p_travel_id, v_from.id, v_to.id,
    true, false, 'pending'
  )
  returning * into v_req;

  return v_req;
end;
$$;

revoke all on function public.request_ownership_transfer(uuid, uuid) from public;
grant execute on function public.request_ownership_transfer(uuid, uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- 여행장 이전 수락 / 거절
-- ---------------------------------------------------------------------------
create or replace function public.respond_ownership_transfer(
  p_request_id uuid,
  p_accept boolean
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_req public.ownership_transfer_requests;
  v_me_id uuid;
begin
  if auth.uid() is null then
    raise exception 'not authenticated';
  end if;

  select * into v_req
  from public.ownership_transfer_requests
  where id = p_request_id and status = 'pending';

  if v_req.id is null then
    raise exception 'request not found';
  end if;

  v_me_id := public.my_member_id(v_req.travel_id);

  if v_me_id is distinct from v_req.to_member_id then
    raise exception 'only target member can respond';
  end if;

  if not p_accept then
    update public.ownership_transfer_requests
    set status = 'cancelled',
        to_accepted = false,
        updated_at = now()
    where id = p_request_id;
    return;
  end if;

  if not public.is_travel_editable(v_req.travel_id) then
    raise exception 'travel is not editable';
  end if;

  -- 역할 교체: 새 여행장 / 기존 여행장 → 구성원
  update public.travel_members
  set role = 'member', updated_at = now()
  where id = v_req.from_member_id;

  update public.travel_members
  set role = 'owner', updated_at = now()
  where id = v_req.to_member_id;

  update public.ownership_transfer_requests
  set status = 'accepted',
      to_accepted = true,
      updated_at = now()
  where id = p_request_id;
end;
$$;

revoke all on function public.respond_ownership_transfer(uuid, boolean) from public;
grant execute on function public.respond_ownership_transfer(uuid, boolean) to authenticated;

-- ---------------------------------------------------------------------------
-- 여행장 이전 요청 취소 (요청자=현재 여행장)
-- ---------------------------------------------------------------------------
create or replace function public.cancel_ownership_transfer(p_request_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_req public.ownership_transfer_requests;
  v_me_id uuid;
begin
  if auth.uid() is null then
    raise exception 'not authenticated';
  end if;

  select * into v_req
  from public.ownership_transfer_requests
  where id = p_request_id and status = 'pending';

  if v_req.id is null then
    raise exception 'request not found';
  end if;

  v_me_id := public.my_member_id(v_req.travel_id);

  if v_me_id is distinct from v_req.from_member_id then
    raise exception 'only requester can cancel';
  end if;

  update public.ownership_transfer_requests
  set status = 'cancelled', updated_at = now()
  where id = p_request_id;
end;
$$;

revoke all on function public.cancel_ownership_transfer(uuid) from public;
grant execute on function public.cancel_ownership_transfer(uuid) to authenticated;
