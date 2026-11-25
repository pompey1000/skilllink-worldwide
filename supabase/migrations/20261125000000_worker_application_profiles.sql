begin;

create table public.worker_application_profiles (
 worker_id uuid primary key default auth.uid() references auth.users(id) on delete cascade,
 experience text not null default '' check (length(experience) <= 2000),
 resume_pdf text check (left(resume_pdf,7) = 'JVBERi0' and length(resume_pdf) <= 1398104
   and octet_length(decode(resume_pdf,'base64')) between 5 and 1048576),
 has_resume boolean generated always as (resume_pdf is not null) stored
);
alter table public.worker_application_profiles enable row level security;
revoke all on public.worker_application_profiles from public, anon, authenticated;
grant select, insert(worker_id, experience, resume_pdf), update(experience, resume_pdf, worker_id)
 on public.worker_application_profiles to authenticated;
create policy "Manage own application profile" on public.worker_application_profiles
 for all to authenticated using (worker_id = (select auth.uid())) with check (worker_id = (select auth.uid()));

create table public.application_resumes (
 application_id uuid primary key references public.company_worker_applications(id) on delete cascade,
 resume_pdf text not null
);
alter table public.application_resumes enable row level security;
revoke all on public.application_resumes from public, anon, authenticated;
grant select on public.application_resumes to authenticated;
create policy "Read resume for visible application" on public.application_resumes for select to authenticated
 using (exists (select 1 from public.company_worker_applications a where a.id = application_id));

create function public.submit_application_with_resume(
 p_opening_id uuid,p_full_name text,p_email text,p_phone text,p_city text,
 p_experience text,p_availability text,p_message text,p_consent boolean)
returns boolean language plpgsql security definer set search_path='' as $$
declare pdf text;
begin
 select resume_pdf into pdf from public.worker_application_profiles where worker_id=auth.uid();
 if pdf is null then raise exception 'Save a résumé in My Profile first'; end if;
 perform public.submit_company_worker_application(p_opening_id,p_full_name,p_email,p_phone,p_city,
   p_experience,p_availability,p_message,p_consent);
 insert into public.application_resumes(application_id,resume_pdf)
 select id,pdf from public.company_worker_applications
 where opening_id=p_opening_id and lower(email)=lower(trim(p_email));
 return true;
end $$;
revoke all on function public.submit_application_with_resume(uuid,text,text,text,text,text,text,text,boolean) from public,anon;
grant execute on function public.submit_application_with_resume(uuid,text,text,text,text,text,text,text,boolean) to authenticated;
commit;
