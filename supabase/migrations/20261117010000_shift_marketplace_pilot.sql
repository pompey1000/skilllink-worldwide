-- Skill Link Worldwide: shift marketplace PILOT (not activated for real staffing).
-- No employer relationship, payroll, payment, insurance or background check created here.
-- All shifts are explicitly labeled test-only until Skill Link is cleared for actual operations.

create table if not exists public.skilllink_shifts (
 id uuid primary key default gen_random_uuid(),
 company_id uuid not null references public.business_accounts(user_id),
 title text not null check (char_length(trim(title)) between 4 and 160),
 category text not null check (category in ('warehouse','housekeeping','hospital_support','other')),
 location text not null check (char_length(trim(location)) between 2 and 180),
 description text not null check (char_length(trim(description)) between 10 and 3000),
 requirements text not null default '',
 start_at timestamptz not null,
 end_at timestamptz not null,
 positions integer not null check (positions between 1 and 200),
 pay_cents integer not null check (pay_cents between 725 and 20000),
 status text not null default 'test_open' check (status in ('test_open','test_closed')),
 created_at timestamptz not null default now(),
 check (end_at > start_at),
 check (end_at <= start_at + interval '24 hours')
);
create index if not exists skilllink_shifts_start_idx on public.skilllink_shifts(start_at);

create table if not exists public.skilllink_shift_requests (
 id uuid primary key default gen_random_uuid(),
 shift_id uuid not null references public.skilllink_shifts(id) on delete cascade,
 worker_id uuid not null references auth.users(id) on delete cascade,
 worker_name text not null check (char_length(trim(worker_name)) between 2 and 160),
 status text not null default 'requested'
   check (status in ('requested','assigned','declined','withdrawn','completed')),
 requested_at timestamptz not null default now(),
 clock_in_at timestamptz,
 clock_out_at timestamptz,
 company_approved_at timestamptz,
 unique (shift_id,worker_id),
 check (clock_out_at is null or clock_in_at is not null),
 check (clock_out_at is null or clock_out_at >= clock_in_at)
);
create index if not exists skilllink_shift_requests_worker_idx on public.skilllink_shift_requests(worker_id);
create index if not exists skilllink_shift_requests_shift_idx on public.skilllink_shift_requests(shift_id);

alter table public.skilllink_shifts enable row level security;
alter table public.skilllink_shift_requests enable row level security;
revoke insert,update,delete on public.skilllink_shifts from anon,authenticated;
revoke insert,update,delete on public.skilllink_shift_requests from anon,authenticated;
grant select on public.skilllink_shifts to authenticated;
grant select on public.skilllink_shift_requests to authenticated;

drop policy if exists "Shift test listings visible to signed in users" on public.skilllink_shifts;
create policy "Shift test listings visible to signed in users" on public.skilllink_shifts
for select to authenticated using (true);
drop policy if exists "Shift requests visible to participants" on public.skilllink_shift_requests;
create policy "Shift requests visible to participants" on public.skilllink_shift_requests
for select to authenticated using (
 worker_id = (select auth.uid()) or exists (
  select 1 from public.skilllink_shifts s
  where s.id=shift_id and s.company_id=(select auth.uid())
 )
);

-- Approved company can create a TEST listing. No public production shift state exists yet.
create or replace function public.skilllink_create_test_shift(
 p_title text,p_category text,p_location text,p_description text,
 p_requirements text,p_start_at timestamptz,p_end_at timestamptz,
 p_positions integer,p_pay_cents integer
) returns uuid language plpgsql security definer set search_path='' as $$
declare v_id uuid;
begin
 if not exists(select 1 from public.business_accounts a
   where a.user_id=(select auth.uid()) and a.status='approved') then
   raise exception 'Approved company account required' using errcode='42501';
 end if;
 if p_start_at is null or p_end_at is null or
    p_start_at < now() - interval '1 day' or p_start_at > now() + interval '1 year' or
    p_end_at <= p_start_at or p_end_at > p_start_at + interval '24 hours' then
    raise exception 'Enter a valid test shift date and time';
 end if;
 insert into public.skilllink_shifts(company_id,title,category,location,description,
    requirements,start_at,end_at,positions,pay_cents)
 values((select auth.uid()),trim(p_title),p_category,trim(p_location),
   trim(p_description),left(trim(coalesce(p_requirements,'')),2000),
   p_start_at,p_end_at,p_positions,p_pay_cents)
 returning id into v_id;
 return v_id;
end $$;

-- Worker requests a TEST shift; this does not confirm a job or pay.
create or replace function public.skilllink_request_test_shift(p_shift_id uuid,p_worker_name text)
returns boolean language plpgsql security definer set search_path='' as $$
declare v_shift public.skilllink_shifts%rowtype;
begin
 if (select auth.uid()) is null then raise exception 'Sign in first' using errcode='42501'; end if;
 select * into v_shift from public.skilllink_shifts where id=p_shift_id for update;
 if not found or v_shift.status<>'test_open' or v_shift.start_at <= now()
 then raise exception 'This test shift is not open'; end if;
 if v_shift.company_id=(select auth.uid()) then raise exception 'Your company cannot apply to its own shift'; end if;
 insert into public.skilllink_shift_requests(shift_id,worker_id,worker_name)
 values(p_shift_id,(select auth.uid()),trim(p_worker_name));
 return true;
exception when unique_violation then raise exception 'You have already requested this shift';
end $$;

-- Company alone assigns from requests, subject to position capacity.
create or replace function public.skilllink_assign_test_worker(p_request_id uuid,p_accept boolean)
returns boolean language plpgsql security definer set search_path='' as $$
declare v_req public.skilllink_shift_requests%rowtype;
declare v_shift public.skilllink_shifts%rowtype;
declare v_count integer;
begin
 select * into v_req from public.skilllink_shift_requests where id=p_request_id for update;
 if not found then raise exception 'Request not found'; end if;
 select * into v_shift from public.skilllink_shifts where id=v_req.shift_id for update;
 if v_shift.company_id is distinct from (select auth.uid()) then
   raise exception 'Company account required' using errcode='42501'; end if;
 if v_req.status <> 'requested' or v_shift.status <> 'test_open'
 then raise exception 'Request is no longer available'; end if;
 if p_accept then
  select count(*) into v_count from public.skilllink_shift_requests
  where shift_id=v_req.shift_id and status in ('assigned','completed');
  if v_count >= v_shift.positions then raise exception 'All test positions are filled'; end if;
 end if;
 update public.skilllink_shift_requests set status=case when p_accept then 'assigned' else 'declined' end
 where id=p_request_id;
 return true;
end $$;

-- Test clock events record server timestamps, not GPS location or payment.
create or replace function public.skilllink_test_clock(p_request_id uuid,p_clock_in boolean)
returns boolean language plpgsql security definer set search_path='' as $$
declare v_req public.skilllink_shift_requests%rowtype;
declare v_shift public.skilllink_shifts%rowtype;
begin
 select * into v_req from public.skilllink_shift_requests where id=p_request_id for update;
 if not found or v_req.worker_id is distinct from (select auth.uid()) or v_req.status<>'assigned'
 then raise exception 'Assigned worker only' using errcode='42501'; end if;
 select * into v_shift from public.skilllink_shifts where id=v_req.shift_id;
 if p_clock_in then
  if v_req.clock_in_at is not null or now() < v_shift.start_at - interval '2 hours'
   or now() > v_shift.end_at + interval '2 hours'
  then raise exception 'Clock-in is unavailable at this time'; end if;
  update public.skilllink_shift_requests set clock_in_at=now() where id=p_request_id;
 else
  if v_req.clock_in_at is null or v_req.clock_out_at is not null then
   raise exception 'You need to clock in first'; end if;
  update public.skilllink_shift_requests set clock_out_at=now() where id=p_request_id;
 end if;
 return true;
end $$;

-- Company approval of recorded TEST hours; does not trigger payroll.
create or replace function public.skilllink_approve_test_hours(p_request_id uuid)
returns boolean language plpgsql security definer set search_path='' as $$
declare v_req public.skilllink_shift_requests%rowtype;
begin
 select * into v_req from public.skilllink_shift_requests where id=p_request_id for update;
 if not found or not exists (
  select 1 from public.skilllink_shifts s where s.id=v_req.shift_id
  and s.company_id=(select auth.uid())) then
  raise exception 'Request belongs to a different company' using errcode='42501'; end if;
 if v_req.status<>'assigned' or v_req.clock_in_at is null
   or v_req.clock_out_at is null then raise exception 'Completed clock-in and clock-out required'; end if;
 update public.skilllink_shift_requests
 set status='completed',company_approved_at=now() where id=p_request_id;
 return true;
end $$;

revoke all on function public.skilllink_create_test_shift(text,text,text,text,text,timestamptz,timestamptz,integer,integer) from public,anon;
revoke all on function public.skilllink_request_test_shift(uuid,text) from public,anon;
revoke all on function public.skilllink_assign_test_worker(uuid,boolean) from public,anon;
revoke all on function public.skilllink_test_clock(uuid,boolean) from public,anon;
revoke all on function public.skilllink_approve_test_hours(uuid) from public,anon;
grant execute on function public.skilllink_create_test_shift(text,text,text,text,text,timestamptz,timestamptz,integer,integer) to authenticated;
grant execute on function public.skilllink_request_test_shift(uuid,text) to authenticated;
grant execute on function public.skilllink_assign_test_worker(uuid,boolean) to authenticated;
grant execute on function public.skilllink_test_clock(uuid,boolean) to authenticated;
grant execute on function public.skilllink_approve_test_hours(uuid) to authenticated;
