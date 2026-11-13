-- Skill Link Worldwide: direct job applications foundation.
-- Schema only: no job board is live until frontend and storage are deployed.
create table public.employer_profiles (
 id uuid primary key default gen_random_uuid(),
 owner_id uuid not null references auth.users(id) on delete cascade,
 company_name text not null check (char_length(btrim(company_name)) between 2 and 160),
 description text,
 created_at timestamptz not null default now(),
 unique(id,owner_id)
);
create table public.job_posts (
 id uuid primary key default gen_random_uuid(),
 employer_id uuid not null references public.employer_profiles(id) on delete cascade,
 title text not null check (char_length(btrim(title)) between 3 and 160),
 description text not null check (char_length(btrim(description)) between 20 and 10000),
 location text not null,
 employment_type text not null check (employment_type in ('full_time','part_time','temporary','contract')),
 status text not null default 'draft' check (status in ('draft','published','closed')),
 created_at timestamptz not null default now()
);
create table public.job_applications (
 id uuid primary key default gen_random_uuid(),
 job_id uuid not null references public.job_posts(id) on delete cascade,
 applicant_id uuid not null references auth.users(id) on delete cascade,
 cover_note text check (char_length(cover_note) <= 5000),
 resume_path text,
 status text not null default 'submitted' check (status in ('submitted','reviewing','interview','rejected','hired','withdrawn')),
 created_at timestamptz not null default now(),
 unique(job_id,applicant_id)
);
create index job_posts_public_idx on public.job_posts(status,created_at desc);
create index job_applications_job_idx on public.job_applications(job_id,created_at desc);
alter table public.employer_profiles enable row level security;
alter table public.job_posts enable row level security;
alter table public.job_applications enable row level security;
grant select,insert,update on public.employer_profiles,public.job_posts,public.job_applications to authenticated;
grant select on public.job_posts to anon;
create policy "Employers manage their own profile" on public.employer_profiles
 for all to authenticated using(owner_id=(select auth.uid())) with check(owner_id=(select auth.uid()));
create policy "Public views published jobs" on public.job_posts for select to anon,authenticated
 using(status='published' or exists(select 1 from public.employer_profiles e where e.id=employer_id and e.owner_id=(select auth.uid())));
create policy "Employer creates jobs" on public.job_posts for insert to authenticated
 with check(exists(select 1 from public.employer_profiles e where e.id=employer_id and e.owner_id=(select auth.uid())));
create policy "Employer updates own jobs" on public.job_posts for update to authenticated
 using(exists(select 1 from public.employer_profiles e where e.id=employer_id and e.owner_id=(select auth.uid())))
 with check(exists(select 1 from public.employer_profiles e where e.id=employer_id and e.owner_id=(select auth.uid())));
create policy "Applicant and employer see applications" on public.job_applications for select to authenticated
 using(applicant_id=(select auth.uid()) or exists(select 1 from public.job_posts j join public.employer_profiles e on e.id=j.employer_id where j.id=job_id and e.owner_id=(select auth.uid())));
create policy "Applicants apply to published jobs" on public.job_applications for insert to authenticated
 with check(applicant_id=(select auth.uid()) and status='submitted' and resume_path is null and exists(select 1 from public.job_posts j where j.id=job_id and j.status='published'));
-- Keep application status and resume references server-managed until secure functions exist.
-- No direct update policy for applications.
-- Resume uploads require private Supabase Storage bucket + authenticated path policies.
