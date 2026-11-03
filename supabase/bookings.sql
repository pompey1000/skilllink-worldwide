-- Skill Link Worldwide booking requests (test mode; no payments).
create table if not exists public.bookings (
 id uuid primary key default gen_random_uuid(),
 conversation_id uuid not null references public.conversations(id) on delete cascade,
 customer_id uuid not null references auth.users(id) on delete cascade,
 provider_id uuid not null references auth.users(id) on delete cascade,
 job_description text not null check (char_length(btrim(job_description)) between 10 and 2000),
 proposed_date date,
 status text not null default 'pending' check(status in ('pending','accepted','declined','cancelled')),
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now()
);
alter table public.bookings enable row level security;
revoke all on public.bookings from anon;
grant select,insert on public.bookings to authenticated;
drop policy if exists "Booking participants view" on public.bookings;
create policy "Booking participants view" on public.bookings for select to authenticated
using ((select auth.uid()) in (customer_id,provider_id));
drop policy if exists "Customer creates booking for conversation" on public.bookings;
create policy "Customer creates booking for conversation" on public.bookings for insert to authenticated
with check(status='pending' and customer_id=(select auth.uid()) and exists(
 select 1 from public.conversations c where c.id=conversation_id
 and c.customer_id=customer_id and c.provider_id=provider_id
));
create or replace function public.respond_to_booking(p_booking_id uuid,p_action text)
returns void language plpgsql security definer set search_path = ''
as $$
begin
 if auth.uid() is null then raise exception 'Not signed in'; end if;
 if p_action not in ('accepted','declined','cancelled') then raise exception 'Invalid action'; end if;
 update public.bookings b
 set status=p_action,updated_at=now()
 where b.id=p_booking_id and b.status='pending'
 and ((p_action in ('accepted','declined') and b.provider_id=auth.uid())
 or (p_action='cancelled' and b.customer_id=auth.uid()));
 if not found then raise exception 'Booking unavailable or action not permitted'; end if;
end; $$;
revoke all on function public.respond_to_booking(uuid,text) from public,anon;
grant execute on function public.respond_to_booking(uuid,text) to authenticated;
