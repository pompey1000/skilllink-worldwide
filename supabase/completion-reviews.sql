-- Skill Link Worldwide completion and reviews (test mode; no payments)
alter table public.bookings add column if not exists completed_at timestamptz;
alter table public.bookings drop constraint if exists bookings_status_check;
alter table public.bookings add constraint bookings_status_check check (status in ('pending','accepted','declined','cancelled','awaiting_confirmation','completed'));
create or replace function public.complete_booking_step(p_booking_id uuid,p_action text)
returns void language plpgsql security definer set search_path = ''
as $$
begin
 if auth.uid() is null then raise exception 'Not signed in'; end if;
 if p_action = 'worker_finished' then
   update public.bookings b set status='awaiting_confirmation',updated_at=now()
   where b.id=p_booking_id and b.provider_id=auth.uid() and b.status='accepted';
 elsif p_action = 'customer_confirmed' then
   update public.bookings b set status='completed',completed_at=now(),updated_at=now()
   where b.id=p_booking_id and b.customer_id=auth.uid() and b.status='awaiting_confirmation';
 else
   raise exception 'Invalid completion action';
 end if;
 if not found then raise exception 'Booking unavailable or action not permitted'; end if;
end; $$;
revoke all on function public.complete_booking_step(uuid,text) from public,anon;
grant execute on function public.complete_booking_step(uuid,text) to authenticated;

create table if not exists public.reviews (
 id uuid primary key default gen_random_uuid(),
 booking_id uuid not null unique references public.bookings(id) on delete cascade,
 customer_id uuid not null references auth.users(id) on delete cascade,
 provider_id uuid not null references auth.users(id) on delete cascade,
 rating integer not null check (rating between 1 and 5),
 comment text check (char_length(comment) <= 1000),
 created_at timestamptz not null default now()
);
alter table public.reviews enable row level security;
revoke all on public.reviews from anon;
grant select,insert on public.reviews to authenticated;
drop policy if exists "Authenticated users read reviews" on public.reviews;
create policy "Authenticated users read reviews" on public.reviews for select to authenticated using (true);
drop policy if exists "Customers review completed bookings" on public.reviews;
create policy "Customers review completed bookings" on public.reviews for insert to authenticated
with check (
 customer_id = (select auth.uid())
 and exists (select 1 from public.bookings b where b.id=booking_id
 and b.customer_id=customer_id and b.provider_id=provider_id and b.status='completed')
);
