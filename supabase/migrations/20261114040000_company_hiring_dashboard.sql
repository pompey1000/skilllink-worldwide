-- Hiring dashboard: private applicant tracking stages for approved companies.
-- Installing this migration does NOT contact applicants, make a job offer, or process payments.
alter table public.company_worker_applications
 add column if not exists review_status text not null default 'new';

alter table public.company_worker_applications
 drop constraint if exists company_worker_applications_review_status_check;
alter table public.company_worker_applications
 add constraint company_worker_applications_review_status_check
 check (review_status in ('new','under_review','interview','hired','not_selected'));

create index if not exists company_worker_applications_review_idx
 on public.company_worker_applications(company_id,review_status,created_at desc);

-- Only the approved company receiving an application may update that application's tracking stage.
-- Do not grant general UPDATE rights to applicant data.
create or replace function public.set_company_application_status(p_application_id uuid,p_status text)
returns boolean
language plpgsql security definer set search_path = ''
as $$
declare v_rows integer;
begin
 if (select auth.uid()) is null then
   raise exception 'Sign in is required' using errcode='42501';
 end if;
 if p_status not in ('new','under_review','interview','hired','not_selected') or p_status is null then
   raise exception 'Invalid application status';
 end if;

 update public.company_worker_applications a
 set review_status = p_status
 where a.id = p_application_id
 and a.company_id = (select auth.uid())
 and exists (
   select 1 from public.business_accounts b
   where b.user_id = a.company_id and b.status='approved'
 );
 get diagnostics v_rows = row_count;
 return v_rows = 1;
end;
$$;
revoke all on function public.set_company_application_status(uuid,text) from public,anon;
grant execute on function public.set_company_application_status(uuid,text) to authenticated;

-- Existing RLS SELECT policy remains in place, limiting application data to its approved company.
