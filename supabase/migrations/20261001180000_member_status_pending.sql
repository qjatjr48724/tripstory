-- 참가 승인 대기 상태
alter type public.member_status add value if not exists 'pending';
