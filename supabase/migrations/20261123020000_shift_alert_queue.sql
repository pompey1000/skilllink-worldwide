-- Dispatchers must verify current assignment and worker channel preferences before sending.
create table public.shift_alert_queue (
  request_id uuid not null references public.skilllink_shift_requests(id) on delete cascade,
  event text not null check (event in ('assigned', 'reminder')),
  channel text not null check (channel in ('sms', 'email')),
  due_at timestamptz not null,
  sent_at timestamptz,
  primary key (request_id, event, channel)
);
alter table public.shift_alert_queue enable row level security;
revoke all on public.shift_alert_queue from public, anon, authenticated;
grant select, update, delete on public.shift_alert_queue to service_role;
create index shift_alert_due_idx on public.shift_alert_queue(due_at) where sent_at is null;

create function public.queue_worker_shift_alerts() returns trigger
language plpgsql security definer set search_path = '' as $$
declare shift_start timestamptz;
begin
  if tg_op = 'UPDATE' then
    if old.status = new.status then return new; end if;
  end if;
  if new.status <> 'assigned' then
    delete from public.shift_alert_queue where request_id = new.id and sent_at is null;
    return new;
  end if;
  select start_at into strict shift_start from public.skilllink_shifts where id = new.shift_id;
  insert into public.shift_alert_queue(request_id, event, channel, due_at)
  select new.id, e.event, c.channel, e.due_at
  from (values ('assigned', now()), ('reminder', shift_start - interval '2 hours')) e(event, due_at)
  cross join (values ('sms'), ('email')) c(channel)
  where e.due_at >= now() and shift_start > now()
  on conflict (request_id, event, channel) do nothing;
  return new;
end;
$$;
revoke all on function public.queue_worker_shift_alerts() from public, anon, authenticated;
create trigger queue_worker_shift_alerts after insert or update of status on public.skilllink_shift_requests
for each row execute function public.queue_worker_shift_alerts();
