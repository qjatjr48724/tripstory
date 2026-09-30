-- 혼자인 여행장은 소유권 이전 없이 나가기(여행 휴지통 이동) 가능
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

  -- 마지막 구성원(여행장 혼자)이면 여행을 휴지통으로
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
