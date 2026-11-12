-- Persistent in-app notifications for workers. No email or phone push is sent.
create table if not exists public.worker_notifications(
 id uuid primary key default gen_random_uuid(),
 recipient_id uuid not null references auth.users(id) on delete cascade,
 kind text not null check(kind in ('new_job','offer_selected')),
 job_id uuid references public.jobs(id) on delete cascade,
 title text not null,
 body text not null,
 is_read boolean not null default false,
 created_at timestamptz not null default now()
);
create index if not exists worker_notifications_recipient_idx on public.worker_notifications(recipient_id,created_at desc);
create unique index if not exists worker_notifications_unique_event on public.worker_notifications(recipient_id,kind,job_id);
alter table public.worker_notifications enable row level security;
drop policy if exists "Workers read own notifications" on public.worker_notifications;
create policy "Workers read own notifications" on public.worker_notifications for select to authenticated using(recipient_id=auth.uid());
drop policy if exists "Workers mark own notifications read" on public.worker_notifications;
create policy "Workers mark own notifications read" on public.worker_notifications for update to authenticated using(recipient_id=auth.uid()) with check(recipient_id=auth.uid());
create or replace function public.notify_published_job() returns trigger language plpgsql security definer set search_path=public,pg_temp as $$
begin
 if new.is_published=true and new.status='open' and (tg_op='INSERT' or old.is_published is distinct from true) then
  insert into public.worker_notifications(recipient_id,kind,job_id,title,body)
  select p.user_id,'new_job',new.id,'New '||coalesce(new.category,'service')||' job',coalesce(new.title,'New job')||' in '||coalesce(new.city,'your area')
  from public.provider_profiles p
  where p.user_id<>new.customer_id and lower(p.skill)=lower(new.category)
  on conflict(recipient_id,kind,job_id) do nothing;
 end if;
 return new;
end; $$;
drop trigger if exists worker_notify_job_published on public.jobs;
create trigger worker_notify_job_published after insert or update of is_published on public.jobs for each row execute function public.notify_published_job();
create or replace function public.notify_selected_offer() returns trigger language plpgsql security definer set search_path=public,pg_temp as $$
begin
 if new.status='selected' and old.status is distinct from 'selected' then
  insert into public.worker_notifications(recipient_id,kind,job_id,title,body)
  values(new.provider_id,'offer_selected',new.job_id,'You were selected!','A customer chose your $'||to_char(new.amount_cents::numeric/100,'FM999999990.00')||' offer.')
  on conflict(recipient_id,kind,job_id) do nothing;
 end if;
 return new;
end; $$;
drop trigger if exists worker_notify_offer_selected on public.job_offers;
create trigger worker_notify_offer_selected after update of status on public.job_offers for each row execute function public.notify_selected_offer();
