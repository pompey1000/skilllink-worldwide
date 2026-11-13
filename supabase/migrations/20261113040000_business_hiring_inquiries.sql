-- Business hiring inquiries: public submission, private reading.
create table if not exists public.business_hiring_inquiries (
 id uuid primary key default gen_random_uuid(),
 created_at timestamptz not null default now(),
 company_name text not null check (char_length(company_name) between 2 and 160),
 contact_name text not null check (char_length(contact_name) between 2 and 120),
 contact_email text not null check (char_length(contact_email) between 5 and 254),
 work_location text not null check (char_length(work_location) between 2 and 160),
 hiring_type text not null check (hiring_type in ('permanent','temporary','both')),
 roles_needed text not null check (char_length(roles_needed) between 5 and 1500),
 workers_needed integer check (workers_needed between 1 and 10000),
 notes text check (char_length(notes) <= 2000)
);
alter table public.business_hiring_inquiries enable row level security;
grant insert on public.business_hiring_inquiries to anon, authenticated;
revoke select, update, delete on public.business_hiring_inquiries from anon, authenticated;
drop policy if exists "Public can submit hiring inquiries" on public.business_hiring_inquiries;
create policy "Public can submit hiring inquiries" on public.business_hiring_inquiries for insert to anon, authenticated with check (true);
