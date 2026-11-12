-- Customer-controlled public job board and competing worker offers.
alter table public.jobs add column if not exists is_published boolean not null default false;
create table if not exists public.job_offers (
 id uuid primary key default gen_random_uuid(),
 job_id uuid not null references public.jobs(id) on delete cascade,
 provider_id uuid not null references auth.users(id) on delete cascade,
 amount_cents bigint not null check(amount_cents between 100 and 100000000),
 message text not null default '' check(char_length(message)<=1000),
 status text not null default 'proposed' check(status in ('proposed','selected','declined','withdrawn')),
 created_at timestamptz not null default now(),
 unique(job_id,provider_id)
);
create index if not exists job_offers_job_idx on public.job_offers(job_id);
alter table public.jobs enable row level security;
alter table public.job_offers enable row level security;
drop policy if exists "Workers can browse published open jobs" on public.jobs;
create policy "Workers can browse published open jobs" on public.jobs for select to authenticated
 using (is_published=true and status='open' and customer_id<>auth.uid() and exists(select 1 from public.provider_profiles p where p.user_id=auth.uid()));
drop policy if exists "Customers publish own jobs" on public.jobs;
create policy "Customers publish own jobs" on public.jobs for update to authenticated using(customer_id=auth.uid()) with check(customer_id=auth.uid());
drop policy if exists "Workers offer on published jobs" on public.job_offers;
create policy "Workers offer on published jobs" on public.job_offers for insert to authenticated
 with check(provider_id=auth.uid() and status='proposed' and exists(select 1 from public.provider_profiles p where p.user_id=auth.uid()) and exists(select 1 from public.jobs j where j.id=job_id and j.is_published=true and j.status='open' and j.customer_id<>auth.uid()));
drop policy if exists "Participants view offers" on public.job_offers;
create policy "Participants view offers" on public.job_offers for select to authenticated
 using(provider_id=auth.uid() or exists(select 1 from public.jobs j where j.id=job_id and j.customer_id=auth.uid()));
-- Selecting an offer must be implemented in an authenticated server function
-- that atomically validates ownership, locks the job, and declines other offers.
