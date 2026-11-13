-- Business contracts and bids: company approval required, server-authorized actions.
-- Run after 20261113040000, 20261113053000, and 20261113070000 migrations.
-- No payment collection or payroll is activated by this migration.
create table if not exists public.business_contracts(
 id uuid primary key default gen_random_uuid(),
 company_application_id uuid not null references public.business_hiring_inquiries(id),
 title text not null check (char_length(title) between 5 and 160),
 description text not null check (char_length(description) between 20 and 4000),
 work_location text not null check (char_length(work_location) between 2 and 160),
 workers_needed integer not null check (workers_needed between 1 and 10000),
 budget_cents bigint check (budget_cents >= 0 and budget_cents <= 100000000000),
 status text not null default 'open' check (status in ('open','awarded','closed')),
 created_at timestamptz not null default now()
);
create table if not exists public.business_contract_bids(
 id uuid primary key default gen_random_uuid(),
 contract_id uuid not null references public.business_contracts(id),
 bidder_company_id uuid not null references public.business_hiring_inquiries(id),
 amount_cents bigint not null check (amount_cents >= 100 and amount_cents <= 100000000000),
 proposal text not null check (char_length(proposal) between 20 and 4000),
 status text not null default 'submitted' check(status in ('submitted','accepted','not_selected')),
 created_at timestamptz not null default now(),
 unique(contract_id,bidder_company_id)
);
create table if not exists public.business_contract_fees(
 contract_id uuid primary key references public.business_contracts(id),
 agreed_fee_cents bigint not null check(agreed_fee_cents >= 0 and agreed_fee_cents <= 100000000000),
 agreement_reference text not null check(char_length(agreement_reference) between 4 and 300),
 payment_status text not null default 'not_invoiced' check(payment_status in ('not_invoiced','invoiced','paid')),
 updated_at timestamptz not null default now()
);
alter table public.business_contracts enable row level security;
alter table public.business_contract_bids enable row level security;
alter table public.business_contract_fees enable row level security;
revoke all on public.business_contracts, public.business_contract_bids, public.business_contract_fees from anon,authenticated;
-- Access is only via controlled functions; authenticated email must be confirmed.
create or replace function public.skilllink_company_id()
returns uuid language sql security definer stable set search_path = ''
as $$
 select b.id from public.business_hiring_inquiries b
 join auth.users u on lower(b.contact_email)=lower(u.email)
 where u.id=(select auth.uid()) and u.email_confirmed_at is not null
 and b.approval_status='approved'
 order by b.created_at asc limit 1;
$$;
revoke all on function public.skilllink_company_id() from public,anon;
grant execute on function public.skilllink_company_id() to authenticated;

create or replace function public.list_business_contracts()
returns table(id uuid,company_name text,title text,description text,work_location text,workers_needed integer,budget_cents bigint,status text,created_at timestamptz,bid_count bigint,own_contract boolean)
language plpgsql security definer set search_path=''
as $$
begin
 return query
 select c.id,a.company_name,c.title,c.description,c.work_location,c.workers_needed,c.budget_cents,c.status,c.created_at,
  (select count(*) from public.business_contract_bids b where b.contract_id=c.id) as bid_count,
  (c.company_application_id=public.skilllink_company_id()) as own_contract
 from public.business_contracts c join public.business_hiring_inquiries a on a.id=c.company_application_id
 where a.approval_status='approved'
 order by case when c.status='open' then 0 else 1 end,c.created_at desc limit 100;
end;$$;
revoke all on function public.list_business_contracts() from public,anon;
grant execute on function public.list_business_contracts() to authenticated;

create or replace function public.post_business_contract(p_title text,p_description text,p_work_location text,p_workers_needed integer,p_budget_cents bigint default null)
returns uuid language plpgsql security definer set search_path=''
as $$
declare cid uuid; company_id uuid;
begin
 company_id:=public.skilllink_company_id();
 if company_id is null then raise exception 'Approved company account required'; end if;
 insert into public.business_contracts(company_application_id,title,description,work_location,workers_needed,budget_cents)
 values(company_id,trim(p_title),trim(p_description),trim(p_work_location),p_workers_needed,p_budget_cents) returning id into cid;
 return cid;
end;$$;
revoke all on function public.post_business_contract(text,text,text,integer,bigint) from public,anon;
grant execute on function public.post_business_contract(text,text,text,integer,bigint) to authenticated;

create or replace function public.submit_business_contract_bid(p_contract_id uuid,p_amount_cents bigint,p_proposal text)
returns uuid language plpgsql security definer set search_path=''
as $$
declare company_id uuid; cid uuid;bidid uuid;
begin
 company_id:=public.skilllink_company_id();
 if company_id is null then raise exception 'Approved company account required'; end if;
 select c.id into cid from public.business_contracts c
 join public.business_hiring_inquiries a on a.id=c.company_application_id
 where c.id=p_contract_id and c.status='open'
 and a.approval_status='approved' and c.company_application_id<>company_id
 for update of c;
 if cid is null then raise exception 'Contract not open for bidding'; end if;
 insert into public.business_contract_bids(contract_id,bidder_company_id,amount_cents,proposal)
 values(cid,company_id,p_amount_cents,trim(p_proposal)) returning id into bidid;
 return bidid;
end;$$;
revoke all on function public.submit_business_contract_bid(uuid,bigint,text) from public,anon;
grant execute on function public.submit_business_contract_bid(uuid,bigint,text) to authenticated;

create or replace function public.list_business_contract_bids(p_contract_id uuid)
returns table(id uuid,bidder_company text,amount_cents bigint,proposal text,status text,created_at timestamptz)
language plpgsql security definer set search_path=''
as $$
begin
 if not exists(select 1 from public.business_contracts c where c.id=p_contract_id
 and (c.company_application_id=public.skilllink_company_id() or public.is_skilllink_admin())) then
 raise exception 'Only contract owner or Skill Link administrator can review bids'; end if;
 return query select b.id,a.company_name,b.amount_cents,b.proposal,b.status,b.created_at
 from public.business_contract_bids b join public.business_hiring_inquiries a on a.id=b.bidder_company_id
 where b.contract_id=p_contract_id order by b.created_at desc;
end;$$;
revoke all on function public.list_business_contract_bids(uuid) from public,anon;
grant execute on function public.list_business_contract_bids(uuid) to authenticated;

create or replace function public.award_business_contract_bid(p_bid_id uuid)
returns void language plpgsql security definer set search_path=''
as $$
declare cid uuid; owner_id uuid; cs text;
begin
 select c.id,c.company_application_id,c.status into cid,owner_id,cs
 from public.business_contract_bids b join public.business_contracts c on c.id=b.contract_id
 where b.id=p_bid_id for update of c;
 if cid is null or cs<>'open' then raise exception 'Contract is not open'; end if;
 if owner_id is distinct from public.skilllink_company_id() and not public.is_skilllink_admin()
 then raise exception 'Only contract owner or Skill Link administrator can award'; end if;
 update public.business_contract_bids set status=case when id=p_bid_id then 'accepted' else 'not_selected' end where contract_id=cid;
 update public.business_contracts set status='awarded' where id=cid;
end;$$;
revoke all on function public.award_business_contract_bid(uuid) from public,anon;
grant execute on function public.award_business_contract_bid(uuid) to authenticated;

-- Fee tracking is admin-only and must cite the separately agreed written fee terms.
create or replace function public.record_business_contract_fee(p_contract_id uuid,p_fee_cents bigint,p_agreement_reference text)
returns void language plpgsql security definer set search_path=''
as $$
begin
 if not public.is_skilllink_admin() then raise exception 'Admin approval required'; end if;
 if not exists(select 1 from public.business_contracts where id=p_contract_id and status='awarded') then
 raise exception 'Only awarded contracts can record agreed fees';end if;
 insert into public.business_contract_fees(contract_id,agreed_fee_cents,agreement_reference)
 values(p_contract_id,p_fee_cents,trim(p_agreement_reference))
 on conflict(contract_id) do update set
 agreed_fee_cents=excluded.agreed_fee_cents,
 agreement_reference=excluded.agreement_reference,updated_at=now();
end;$$;
revoke all on function public.record_business_contract_fee(uuid,bigint,text) from public,anon;
grant execute on function public.record_business_contract_fee(uuid,bigint,text) to authenticated;
