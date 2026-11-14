-- Internal-only delivery status for application email notifications.
create table if not exists public.company_application_notifications (
 application_id uuid primary key references public.company_worker_applications(id) on delete cascade,
 status text not null check (status in ('processing','sent','failed')),
 updated_at timestamptz not null default now()
);
alter table public.company_application_notifications enable row level security;
revoke all on public.company_application_notifications from anon, authenticated;
-- Service role only. Do not create a public RLS policy.
