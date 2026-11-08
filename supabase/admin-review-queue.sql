-- Skill Link Worldwide administrative review queue (no money movement).
-- Run this in Supabase SQL Editor. Admin access is NOT automatically granted.
create table if not exists public.skilllink_admins (
 user_id uuid primary key references auth.users(id) on delete cascade,
 added_at timestamptz not null default now()
);
alter table public.skilllink_admins enable row level security;
revoke all on public.skilllink_admins from anon,authenticated;
create or replace function public.my_admin_review_queue()
returns table (booking_id uuid, job_description text, booking_status text, worker_finished_at timestamptz, review_deadline timestamptz, hours_overdue numeric)
language plpgsql security definer set search_path = ''
as $$
begin
 if auth.uid() is null or not exists (select 1 from public.skilllink_admins a where a.user_id=auth.uid()) then
   raise exception 'Administrator access required';
 end if;
 return query select b.id,b.job_description,b.status,b.worker_finished_at,
   b.worker_finished_at + interval '72 hours',
   round(extract(epoch from (now() - (b.worker_finished_at + interval '72 hours')))::numeric / 3600,1)
 from public.bookings b
 where b.status='awaiting_confirmation' and b.worker_finished_at is not null
   and now() >= b.worker_finished_at + interval '72 hours'
 order by b.worker_finished_at asc limit 100;
end; $$;
revoke all on function public.my_admin_review_queue() from public,anon;
grant execute on function public.my_admin_review_queue() to authenticated;
-- Grant administrator access separately, using a verified account UUID:
-- insert into public.skilllink_admins(user_id) values ('REPLACE_WITH_YOUR_AUTH_USER_UUID');
-- No payment release, escrow, or dispute adjudication is implemented by this script.
