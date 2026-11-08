-- Skill Link Worldwide: 72-hour customer review clock.
-- No payment processing or automatic payouts are implemented here.
alter table public.bookings add column if not exists worker_finished_at timestamptz;
create or replace function public.record_worker_finished_at()
returns trigger language plpgsql set search_path = ''
as $$
begin
  if new.status = 'awaiting_confirmation' and old.status is distinct from 'awaiting_confirmation' then
    new.worker_finished_at = now();
  end if;
  return new;
end;
$$;
drop trigger if exists booking_worker_finished_clock on public.bookings;
create trigger booking_worker_finished_clock
before update of status on public.bookings
for each row execute function public.record_worker_finished_at();
-- Historical finished bookings cannot be timed accurately from created_at.
-- They remain without a clock until a reliable completion timestamp exists.
create or replace view public.booking_review_deadlines
with (security_invoker = true)
as select id,customer_id,provider_id,status,worker_finished_at,
  worker_finished_at + interval '72 hours' as review_deadline,
  (status='awaiting_confirmation' and worker_finished_at is not null
    and now() >= worker_finished_at + interval '72 hours') as needs_review
from public.bookings;
grant select on public.booking_review_deadlines to authenticated;
