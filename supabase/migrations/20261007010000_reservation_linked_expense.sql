-- 예약 비용 ↔ 비용 장부 연결
-- 대시보드 SQL Editor에서 실행하세요.

alter table public.reservations
  add column if not exists linked_expense_id uuid
    references public.expenses (id) on delete set null;

create index if not exists reservations_linked_expense_idx
  on public.reservations (linked_expense_id);
