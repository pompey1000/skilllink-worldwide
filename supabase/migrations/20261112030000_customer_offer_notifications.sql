-- Notify customers when a worker submits an offer to their published job.
alter table public.worker_notifications drop constraint if exists worker_notifications_kind_check;
alter table public.worker_notifications add constraint worker_notifications_kind_check check(kind in ('new_job','offer_selected','new_offer'));
create or replace function public.notify_customer_new_offer() returns trigger language plpgsql security definer set search_path=public,pg_temp as $$
declare owner_id uuid; job_title text;
begin
 select j.customer_id, j.title into owner_id,job_title from public.jobs j where j.id=new.job_id;
 if owner_id is not null then
  insert into public.worker_notifications(recipient_id,kind,job_id,title,body)
  values(owner_id,'new_offer',new.job_id,'New worker offer','A worker offered $'||to_char(new.amount_cents::numeric/100,'FM999999990.00')||' for '||coalesce(job_title,'your job')||'. Open My saved service requests to review.')
  on conflict(recipient_id,kind,job_id) do update set title=excluded.title,body=excluded.body,is_read=false,created_at=now();
 end if;
 return new;
end; $$;
drop trigger if exists customer_notify_new_offer on public.job_offers;
create trigger customer_notify_new_offer after insert on public.job_offers for each row execute function public.notify_customer_new_offer();
