begin;

alter table public.company_worker_applications
 add column shared_with_skilllink boolean not null default false,
 add column has_resume boolean not null default false;

create policy "Staff can review applications shared with Skill Link"
 on public.company_worker_applications for select to authenticated
 using (shared_with_skilllink and (select public.is_skilllink_admin()));

create policy "Staff can identify openings for shared applications"
 on public.company_job_openings for select to authenticated
 using ((select public.is_skilllink_admin()));

create table public.company_application_resumes (
 application_id uuid primary key references public.company_worker_applications(id) on delete cascade,
 content text not null
);
alter table public.company_application_resumes enable row level security;
revoke all on public.company_application_resumes from public, anon, authenticated;
grant select on public.company_application_resumes to authenticated;
create policy "Company can read attachments of visible applications"
 on public.company_application_resumes for select to authenticated
 using (exists (select 1 from public.company_worker_applications a where a.id=application_id));

create function public.submit_shared_worker_application(
 p_opening_id uuid,p_full_name text,p_email text,p_phone text,p_city text,
 p_experience text,p_availability text,p_message text,p_consent boolean,p_resume text)
returns boolean language plpgsql security definer set search_path=''
as $$
declare
 pdf bytea;
 application uuid;
begin
 if p_resume is not null then
 if octet_length(p_resume)>2796204 then
  raise exception 'Choose a PDF up to 2 MB';
 end if;
 pdf:=decode(p_resume,'base64');
 if octet_length(pdf)>2097152 or substring(pdf from 1 for 5)<>decode('255044462d','hex') then
  raise exception 'Choose a valid PDF up to 2 MB';
 end if;
 end if;
 perform public.submit_company_worker_application(p_opening_id,p_full_name,p_email,p_phone,p_city,
  p_experience,p_availability,p_message,p_consent);
 update public.company_worker_applications set shared_with_skilllink=true, has_resume=(p_resume is not null)
 where opening_id=p_opening_id and lower(email)=lower(trim(p_email))
 returning id into strict application;
 if p_resume is not null then
  insert into public.company_application_resumes(application_id,content) values(application,p_resume);
 end if;
 return true;
end $$;
revoke all on function public.submit_shared_worker_application(uuid,text,text,text,text,text,text,text,boolean,text) from public;
grant execute on function public.submit_shared_worker_application(uuid,text,text,text,text,text,text,text,boolean,text) to anon,authenticated;

commit;
