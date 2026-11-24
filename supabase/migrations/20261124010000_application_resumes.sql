begin;
alter table public.skilllink_shift_requests add column experience text check (length(experience)<=2000);
create table public.application_resumes (
 id uuid primary key default gen_random_uuid(),
 application_id uuid unique references public.company_worker_applications on delete cascade,
 request_id uuid unique references public.skilllink_shift_requests on delete cascade,
 check (num_nonnulls(application_id,request_id)=1),
 pdf text not null check (
  length(pdf) between 8 and 2796204 and
  octet_length(decode(pdf,'base64')) between 5 and 2097152 and
  substring(decode(pdf,'base64') from 1 for 5)=decode('255044462d','hex')
 )
);
alter table public.application_resumes enable row level security;
revoke all on public.application_resumes from public,anon,authenticated;
grant select on public.application_resumes to authenticated;
create policy employer_reads_submitted_resume on public.application_resumes
 for select to authenticated using (
 exists(select 1 from public.business_accounts b where b.user_id=(select auth.uid()) and b.status='approved')
 and (exists(select 1 from public.company_worker_applications a where a.id=application_id and a.company_id=(select auth.uid()))
 or exists(select 1 from public.skilllink_shift_requests r join public.skilllink_shifts s on s.id=r.shift_id
 where r.id=request_id and s.company_id=(select auth.uid())))
 );

create function public.submit_company_application_with_resume(
 p_opening_id uuid,p_full_name text,p_email text,p_phone text,p_city text,p_experience text,
 p_availability text,p_message text,p_consent boolean,p_pdf text)
returns boolean language plpgsql security definer set search_path='' as $$
begin
 perform public.submit_company_worker_application(p_opening_id,p_full_name,p_email,p_phone,p_city,p_experience,p_availability,p_message,p_consent);
 insert into public.application_resumes(application_id,pdf)
 values ((select id from public.company_worker_applications where opening_id=p_opening_id and lower(email)=lower(trim(p_email))),p_pdf);
 return true;
end $$;
revoke all on function public.submit_company_application_with_resume(uuid,text,text,text,text,text,text,text,boolean,text) from public;
grant execute on function public.submit_company_application_with_resume(uuid,text,text,text,text,text,text,text,boolean,text) to anon,authenticated;

create function public.request_shift_with_experience(p_shift_id uuid,p_worker_name text,p_experience text,p_pdf text)
returns boolean language plpgsql security definer set search_path='' as $$
declare v_id uuid;
begin
 perform public.skilllink_request_test_shift(p_shift_id,p_worker_name);
 update public.skilllink_shift_requests set experience=nullif(trim(p_experience),'')
 where shift_id=p_shift_id and worker_id=(select auth.uid()) returning id into strict v_id;
 if p_pdf is not null then
  insert into public.application_resumes(request_id,pdf) values(v_id,p_pdf);
 end if;
 return true;
end $$;
revoke all on function public.request_shift_with_experience(uuid,text,text,text) from public,anon;
grant execute on function public.request_shift_with_experience(uuid,text,text,text) to authenticated;
commit;
