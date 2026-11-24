begin;
create table public.booking_trip_locations (
 provider_id uuid primary key references auth.users on delete cascade,
 booking_id uuid unique not null references public.bookings on delete cascade,
 token uuid not null default gen_random_uuid(),
 latitude double precision check(latitude between -90 and 90),
 longitude double precision check(longitude between -180 and 180),
 updated_at timestamptz,
 ends_at timestamptz not null default now() + interval '2 hours'
);
alter table public.booking_trip_locations enable row level security;
revoke all on public.booking_trip_locations from public, anon, authenticated;

create function public.start_booking_trip(p_booking uuid) returns uuid
language plpgsql security definer set search_path='' as $$
declare session_id uuid;
begin
 perform 1 from public.bookings where id=p_booking and provider_id=auth.uid() and status='accepted' for share;
 if not found then raise exception 'An accepted booking with this provider is required'; end if;
 insert into public.booking_trip_locations(provider_id,booking_id) values(auth.uid(),p_booking)
 on conflict(provider_id) do update set booking_id=excluded.booking_id,token=excluded.token,
 latitude=null,longitude=null,updated_at=null,ends_at=excluded.ends_at returning token into session_id;
 return session_id;
end $$;

create function public.update_booking_trip(p_token uuid,p_lat double precision,p_lon double precision)
returns boolean language sql security definer set search_path='' as $$
 with changed as (update public.booking_trip_locations t set latitude=p_lat,longitude=p_lon,updated_at=now()
 where t.token=p_token and t.provider_id=auth.uid() and t.ends_at>now()
 and p_lat between -90 and 90 and p_lon between -180 and 180
 and exists(select 1 from public.bookings b where b.id=t.booking_id and b.status='accepted' and b.provider_id=auth.uid()) returning 1)
 select exists(select 1 from changed)
$$;

create function public.stop_booking_trip(p_token uuid) returns void
language sql security definer set search_path='' as $$
 delete from public.booking_trip_locations where token=p_token and provider_id=auth.uid()
$$;

create function public.read_booking_trip(p_booking uuid)
returns table(latitude double precision,longitude double precision,updated_at timestamptz)
language sql stable security definer set search_path='' as $$
 select t.latitude,t.longitude,t.updated_at from public.booking_trip_locations t
 join public.bookings b on b.id=t.booking_id and b.provider_id=t.provider_id
 where b.id=p_booking and b.customer_id=auth.uid() and b.status='accepted'
 and t.ends_at>now() and t.updated_at>now()-interval '60 seconds'
$$;

create function public.clear_closed_booking_trip() returns trigger
language plpgsql security definer set search_path='' as $$
begin
 delete from public.booking_trip_locations where booking_id=new.id;
 return new;
end $$;
create trigger clear_closed_booking_trip after update of status,provider_id,customer_id on public.bookings
 for each row when (old.status is distinct from new.status or old.provider_id is distinct from new.provider_id or old.customer_id is distinct from new.customer_id)
 execute function public.clear_closed_booking_trip();

revoke all on function public.clear_closed_booking_trip(),public.start_booking_trip(uuid),public.update_booking_trip(uuid,double precision,double precision),public.stop_booking_trip(uuid),public.read_booking_trip(uuid) from public,anon,authenticated;
grant execute on function public.start_booking_trip(uuid),public.update_booking_trip(uuid,double precision,double precision),public.stop_booking_trip(uuid),public.read_booking_trip(uuid) to authenticated;
commit;
