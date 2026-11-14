-- Worker application links and private company applicant inbox.
-- Apply manually in Supabase SQL Editor; does NOT configure email delivery, payroll or payments.
-- Opening links are intended to be shared only by approved business accounts.
create table if not exists public.company_job_openings (
 id uuid primary key default gen_random_uuid(),
 company_id uuid not null references public.business_accounts(user_id) on delete cascade,
 title text not null check (char_length(trim(title)) between 4 and 160),
 location text not null check (char_length(trim(location)) between 2 and 160),
 description text not null check (char_length(trim(description)) between 10 and 3000),
 status text not null default 'open' check (status in ('open','closed')),
 created_at timestamptz not null default now()
);
create index if not exists company_job_openings_owner_idx on public.company_job_openings(company_id,created_at desc);

create table if not exists public.company_worker_applications (
 id uuid primary key default gen_random_uuid(),
 opening_id uuid not null references public.company_job_openings(id) on delete cascade,
 company_id uuid not null references public.business_accounts(user_id) on delete cascade,
 full_name text not null check (char_length(trim(full_name)) between 2 and 160),
 email text not null check (char_length(trim(email)) between 5 and 254),
 phone text not null check (char_length(trim(phone)) between 7 and 40),
 city text not null check (char_length(trim(city)) between 2 and 160),
 experience text not null check (char_length(trim(experience)) between 3 and 2000),
 availability text not null check (char_length(trim(availability)) between 2 and 250),
 message text not null default '',
 shared_with_company_at timestamptz not null default now(),
 created_at timestamptz not null default now()
);
create index if not exists company_worker_applications_owner_idx on public.company_worker_applications(company_id,created_at desc);
create unique index if not exists company_worker_applications_one_email_per_opening
 on public.company_worker_applications(opening_id,lower(email));

alter table public.company_job_openings enable row level security;
alter table public.company_worker_applications enable row level security;

drop policy if exists "Approved company manages own openings" on public.company_job_openings;
create policy "Approved company manages own openings" on public.company_job_openings
 for all to authenticated
 using (company_id=(select auth.uid()) and exists(
   select 1 from public.business_accounts a
   where a.user_id=(select auth.uid()) and a.status='approved'))
 with check (company_id=(select auth.uid()) and exists(
   select 1 from public.business_accounts a
   where a.user_id=(select auth.uid()) and a.status='approved'));

drop policy if exists "Approved company views its applicants" on public.company_worker_applications;
create policy "Approved company views its applicants" on public.company_worker_applications
 for select to authenticated
 using (company_id=(select auth.uid()) and exists(
   select 1 from public.business_accounts a
   where a.user_id=(select auth.uid()) and a.status='approved'));

-- Never allow the browser to insert applications directly or browse private applicant data.
revoke all on public.company_worker_applications from anon,authenticated;
grant select on public.company_worker_applications to authenticated;
grant select,insert,update on public.company_job_openings to authenticated;

create or replace function public.get_company_job_for_application(p_opening_id uuid)
returns table (title text,location text,description text,company_name text)
language sql stable security definer set search_path=''
as $$
 select j.title,j.location,j.description,a.company_name
 from public.company_job_openings j
 join public.business_accounts a on a.user_id=j.company_id
 where j.id=p_opening_id and j.status='open' and a.status='approved'
 limit 1;
$$;
revoke all on function public.get_company_job_for_application(uuid) from public;
grant execute on function public.get_company_job_for_application(uuid) to anon,authenticated;

create or replace function public.submit_company_worker_application(
 p_opening_id uuid,p_full_name text,p_email text,p_phone text,
 p_city text,p_experience text,p_availability text,p_message text,p_consent boolean)
returns boolean language plpgsql security definer set search_path=''
as $$
declare v_company_id uuid;
begin
 if p_consent is distinct from true then
  raise exception 'Consent to share this application with the named company is required';
 end if;
 select j.company_id into v_company_id
 from public.company_job_openings j
 join public.business_accounts a on a.user_id=j.company_id
 where j.id=p_opening_id and j.status='open' and a.status='approved';
 if v_company_id is null then raise exception 'This application link is no longer accepting applications'; end if;
 if char_length(trim(coalesce(p_full_name,''))) not between 2 and 160
 or char_length(trim(coalesce(p_email,''))) not between 5 and 254
 or trim(coalesce(p_email,'')) !~* '^[A-Z0-9._%+\-]+@[A-Z0-9.\-]+\.[A-Z]{2,}$'
 or char_length(trim(coalesce(p_phone,''))) not between 7 and 40
 or char_length(trim(coalesce(p_city,''))) not between 2 and 160
 or char_length(trim(coalesce(p_experience,''))) not between 3 and 2000
 or char_length(trim(coalesce(p_availability,''))) not between 2 and 250
 or char_length(coalesce(p_message,'')) > 2000 then
  raise exception 'Please check your application fields and try again';
 end if;
 insert into public.company_worker_applications
 (opening_id,company_id,full_name,email,phone,city,experience,availability,message)
 values (p_opening_id,v_company_id,trim(p_full_name),lower(trim(p_email)),
 trim(p_phone),trim(p_city),trim(p_experience),trim(p_availability),trim(coalesce(p_message,'')));
 return true;
exception when unique_violation then
 raise exception 'An application using this email address has already been submitted for this opening';
end $$;
revoke all on function public.submit_company_worker_application(uuid,text,text,text,text,text,text,text,boolean) from public;
grant execute on function public.submit_company_worker_application(uuid,text,text,text,text,text,text,text,boolean) to anon,authenticated;

-- Prior to broad rollout: add CAPTCHA or other rate limiting, abuse monitoring,
-- a written privacy/retention policy, and tested company email notifications if needed.
