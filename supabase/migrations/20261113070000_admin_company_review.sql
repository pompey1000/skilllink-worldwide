-- Secure admin approval workflow. Run after the earlier business inquiry migrations.
-- Admins are granted manually by a trusted project owner using Supabase SQL.
create table if not exists public.skilllink_admins (
 user_id uuid primary key references auth.users(id) on delete cascade,
 created_at timestamptz not null default now()
);
alter table public.skilllink_admins enable row level security;
revoke all on public.skilllink_admins from anon, authenticated;
create or replace function public.is_skilllink_admin()
returns boolean
language sql security definer stable
set search_path = ''
as $$
 select exists(select 1 from public.skilllink_admins where user_id = (select auth.uid()));
$$;
revoke all on function public.is_skilllink_admin() from public, anon;
grant execute on function public.is_skilllink_admin() to authenticated;

create or replace function public.list_company_applications()
returns table(
 id uuid, created_at timestamptz, company_name text, contact_name text,
 contact_email text, work_location text, hiring_type text, roles_needed text,
 workers_needed integer, notes text, approval_status text, reviewed_at timestamptz
)
language plpgsql security definer
set search_path = ''
as $$
begin
 if not public.is_skilllink_admin() then
  raise exception 'Not authorized to review companies' using errcode = '42501';
 end if;
 return query
 select b.id,b.created_at,b.company_name,b.contact_name,b.contact_email,
 b.work_location,b.hiring_type,b.roles_needed,b.workers_needed,b.notes,
 b.approval_status,b.reviewed_at
 from public.business_hiring_inquiries b
 order by case b.approval_status when 'pending' then 0 else 1 end, b.created_at desc
 limit 200;
end;
$$;
revoke all on function public.list_company_applications() from public, anon;
grant execute on function public.list_company_applications() to authenticated;

create or replace function public.review_company_application(
 application_id uuid, new_status text
)
returns void language plpgsql security definer
set search_path = ''
as $$
begin
 if not public.is_skilllink_admin() then
  raise exception 'Not authorized to approve companies' using errcode = '42501';
 end if;
 if new_status not in ('approved','rejected','pending') then
  raise exception 'Invalid status';
 end if;
 update public.business_hiring_inquiries
 set approval_status = new_status,
     reviewed_at = case when new_status = 'pending' then null else now() end
 where id = application_id;
 if not found then raise exception 'Application not found'; end if;
end;
$$;
revoke all on function public.review_company_application(uuid,text) from public, anon;
grant execute on function public.review_company_application(uuid,text) to authenticated;
-- One-time admin provisioning, run manually in Supabase SQL editor after signup:
-- insert into public.skilllink_admins(user_id)
-- select id from auth.users
-- where email = 'support@skilllinkworldwide.com' and email_confirmed_at is not null
-- on conflict do nothing;
-- IMPORTANT: Keep this provisioning command out of any public website JavaScript.
