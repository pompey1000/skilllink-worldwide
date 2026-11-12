-- Atomic, customer-authorized selection of one worker offer.
create or replace function public.select_job_offer(p_offer_id uuid)
returns boolean
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
 v_job_id uuid;
 v_customer_id uuid;
 v_status text;
 v_published boolean;
 v_offer_status text;
begin
 select job_id into v_job_id from public.job_offers where id=p_offer_id;
 if v_job_id is null then return false; end if;
 select customer_id,status,is_published into v_customer_id,v_status,v_published
 from public.jobs where id=v_job_id for update;
 if v_customer_id is distinct from auth.uid() or v_status<>'open' or not v_published then return false; end if;
 select status into v_offer_status from public.job_offers where id=p_offer_id and job_id=v_job_id for update;
 if v_offer_status<>'proposed' then return false; end if;
 if exists(select 1 from public.job_offers where job_id=v_job_id and status='selected') then return false; end if;
 update public.job_offers set status='declined' where job_id=v_job_id and status='proposed' and id<>p_offer_id;
 update public.job_offers set status='selected' where id=p_offer_id;
 update public.jobs set is_published=false where id=v_job_id;
 return true;
end;
$$;
revoke all on function public.select_job_offer(uuid) from public, anon;
grant execute on function public.select_job_offer(uuid) to authenticated;
