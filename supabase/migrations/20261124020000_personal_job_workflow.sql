-- Sandbox booking walkthrough. These transitions do not move money.
alter table public.bookings
  add column service_address text check (char_length(service_address) between 1 and 350),
  add column test_started_at timestamptz,
  add column test_price_cents bigint;
-- Customer creates the address with the booking. Participants can read it under booking RLS.
create function public.guard_test_job_steps() returns trigger
language plpgsql set search_path = '' as $$
begin
  if tg_op = 'INSERT' then
    if new.test_started_at is not null or new.test_price_cents is not null then
      raise exception 'Start the job from the worker account';
    end if;
  elsif new.service_address is not null and new.status = 'awaiting_confirmation'
      and new.test_started_at is null then
    raise exception 'Start the test job before finishing';
  end if;
  return new;
end;
$$;
create trigger guard_test_job_steps before insert or update on public.bookings
for each row execute function public.guard_test_job_steps();

create function public.start_test_personal_job(p_booking_id uuid) returns void
language plpgsql security definer set search_path = '' as $$
declare
  job public.bookings%rowtype;
  price bigint;
begin
  select * into job from public.bookings
    where id=p_booking_id and provider_id=auth.uid() for update;
  if not found or job.status <> 'accepted' or job.service_address is null then
    raise exception 'This job is unavailable';
  end if;
  if job.test_started_at is not null then return; end if;
  select amount_cents into price from public.booking_quotes
    where booking_id=job.id and provider_id=job.provider_id and status='accepted' and currency='usd'
    order by created_at desc limit 1;
  if price is null or price <= 0 then raise exception 'The customer must approve a quote first'; end if;
  update public.bookings set test_started_at=now(), test_price_cents=price, updated_at=now()
    where id=job.id;
end;
$$;
revoke all on function public.start_test_personal_job(uuid) from public,anon;
grant execute on function public.start_test_personal_job(uuid) to authenticated;
