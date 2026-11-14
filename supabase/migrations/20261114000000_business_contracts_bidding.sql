-- Skill Link business contract board: test-mode listings, approved-company bidding, fee ledger.
-- Apply in Supabase SQL Editor. No invoices, payments, or automatic hiring.
create table if not exists public.business_accounts (
 user_id uuid primary key references auth.users(id) on delete cascade,
 company_name text not null check(char_length(trim(company_name)) between 2 and 160),
 contact_email text not null,
 city text not null,
 status text not null default 'pending' check(status in ('pending','approved','rejected')),
 created_at timestamptz not null default now()
);
create table if not exists public.business_contracts (
 id uuid primary key default gen_random_uuid(),
 owner_id uuid not null references public.business_accounts(user_id),
 title text not null check(char_length(trim(title)) between 5 and 160),
 description text not null check(char_length(trim(description)) between 10 and 3000),
 city text not null,
 roles_needed text not null,
 workers_needed integer not null check(workers_needed between 1 and 10000),
 contract_kind text not null check(contract_kind in ('temporary','permanent','project')),
 budget_cents bigint check(budget_cents is null or budget_cents between 100 and 10000000000),
 status text not null default 'open' check(status in ('open','awarded','closed')),
 created_at timestamptz not null default now()
);
create table if not exists public.business_contract_bids (
 id uuid primary key default gen_random_uuid(),
 contract_id uuid not null references public.business_contracts(id) on delete cascade,
 bidder_id uuid not null references public.business_accounts(user_id),
 amount_cents bigint not null check(amount_cents between 100 and 10000000000),
 proposal text not null check(char_length(trim(proposal)) between 10 and 2000),
 status text not null default 'proposed' check(status in ('proposed','selected','declined')),
 created_at timestamptz not null default now(),
 unique(contract_id,bidder_id)
);
create unique index if not exists one_selected_business_bid on public.business_contract_bids(contract_id) where status='selected';
create table if not exists public.business_fee_ledger (
 id uuid primary key default gen_random_uuid(),
 contract_id uuid not null unique references public.business_contracts(id),
 winning_bid_id uuid not null unique references public.business_contract_bids(id),
 agreed_fee_cents bigint check(agreed_fee_cents is null or agreed_fee_cents >= 0),
 fee_status text not null default 'pending_agreement'
 check(fee_status in ('pending_agreement','agreed','invoiced','paid','waived')),
 created_at timestamptz not null default now(),
 notes text not null default 'No fee agreement or payment is active.'
);
alter table public.business_accounts enable row level security;
alter table public.business_contracts enable row level security;
alter table public.business_contract_bids enable row level security;
alter table public.business_fee_ledger enable row level security;

drop policy if exists "Company reads own account" on public.business_accounts;
create policy "Company reads own account" on public.business_accounts for select to authenticated using(user_id=auth.uid());
drop policy if exists "Company registers own account" on public.business_accounts;
create policy "Company registers own account" on public.business_accounts for insert to authenticated with check(user_id=auth.uid() and status='pending');

-- Contract fields are visible to approved companies, the posting owner, or a Skill Link admin.
drop policy if exists "Approved companies browse contracts" on public.business_contracts;
create policy "Approved companies browse contracts" on public.business_contracts for select to authenticated
using(owner_id=auth.uid() or public.is_skilllink_admin() or exists(select 1 from public.business_accounts a where a.user_id=auth.uid() and a.status='approved'));
drop policy if exists "Approved companies post contracts" on public.business_contracts;
create policy "Approved companies post contracts" on public.business_contracts for insert to authenticated
with check(owner_id=auth.uid() and status='open' and exists(select 1 from public.business_accounts a where a.user_id=auth.uid() and a.status='approved'));

drop policy if exists "Bid participants read bids" on public.business_contract_bids;
create policy "Bid participants read bids" on public.business_contract_bids for select to authenticated
using(bidder_id=auth.uid() or public.is_skilllink_admin() or exists(select 1 from public.business_contracts c where c.id=contract_id and c.owner_id=auth.uid()));

drop policy if exists "Approved businesses send bids" on public.business_contract_bids;
create policy "Approved businesses send bids" on public.business_contract_bids for insert to authenticated
with check(bidder_id=auth.uid() and status='proposed'
 and exists(select 1 from public.business_accounts a where a.user_id=auth.uid() and a.status='approved')
 and exists(select 1 from public.business_contracts c where c.id=contract_id and c.status='open' and c.owner_id<>auth.uid()));

drop policy if exists "Contract owners read fee status" on public.business_fee_ledger;
create policy "Contract owners read fee status" on public.business_fee_ledger for select to authenticated
using(public.is_skilllink_admin() or exists(select 1 from public.business_contracts c where c.id=contract_id and c.owner_id=auth.uid())
or exists(select 1 from public.business_contract_bids b where b.id=winning_bid_id and b.bidder_id=auth.uid()));

-- Approval is administrator-only and never obtainable from browser-side status changes.
create or replace function public.review_business_account(p_user_id uuid,p_status text)
returns boolean language plpgsql security definer set search_path='' as $$
begin
 if not public.is_skilllink_admin() then raise exception 'Admin only' using errcode='42501'; end if;
 if p_status not in ('approved','rejected','pending') then raise exception 'Invalid status'; end if;
 update public.business_accounts set status=p_status where user_id=p_user_id;
 return found;
end $$;
revoke all on function public.review_business_account(uuid,text) from public,anon;
grant execute on function public.review_business_account(uuid,text) to authenticated;

create or replace function public.list_business_accounts_for_admin()
returns table(user_id uuid,company_name text,contact_email text,city text,status text,created_at timestamptz)
language plpgsql security definer set search_path='' as $$
begin
 if not public.is_skilllink_admin() then raise exception 'Admin only' using errcode='42501'; end if;
 return query select a.user_id,a.company_name,a.contact_email,a.city,a.status,a.created_at
 from public.business_accounts a order by a.created_at desc limit 200;
end $$;
revoke all on function public.list_business_accounts_for_admin() from public,anon;
grant execute on function public.list_business_accounts_for_admin() to authenticated;

-- The posting company alone selects a bid; records a pending (unagreed) platform fee.
create or replace function public.select_business_contract_bid(p_bid_id uuid)
returns boolean language plpgsql security definer set search_path='' as $$
declare v_contract_id uuid;v_bid public.business_contract_bids%rowtype;v_contract public.business_contracts%rowtype;
begin
 select b.contract_id into v_contract_id from public.business_contract_bids b where b.id=p_bid_id;
 if not found then raise exception 'Bid not found'; end if;
 select * into v_contract from public.business_contracts c where c.id=v_contract_id for update;
 if not found or v_contract.owner_id<>auth.uid() then raise exception 'Not authorized' using errcode='42501'; end if;
 if v_contract.status<>'open' then raise exception 'Contract already closed'; end if;
 select * into v_bid from public.business_contract_bids b where b.id=p_bid_id for update;
 if not found or v_bid.status<>'proposed' then raise exception 'Bid unavailable'; end if;
 update public.business_contract_bids set status=case when id=p_bid_id then 'selected' else 'declined' end
 where contract_id=v_contract_id and status='proposed';
 update public.business_contracts set status='awarded' where id=v_contract_id;
 insert into public.business_fee_ledger(contract_id,winning_bid_id) values(v_contract_id,p_bid_id);
 return true;
end $$;
revoke all on function public.select_business_contract_bid(uuid) from public,anon;
grant execute on function public.select_business_contract_bid(uuid) to authenticated;

-- Financial records can only be configured by an admin after an actual fee agreement.
create or replace function public.record_business_contract_fee(p_contract_id uuid,p_fee_cents bigint,p_notes text)
returns boolean language plpgsql security definer set search_path='' as $$
begin
 if not public.is_skilllink_admin() then raise exception 'Admin only' using errcode='42501'; end if;
 if p_fee_cents is null or p_fee_cents<0 or p_fee_cents>10000000000 then raise exception 'Invalid fee'; end if;
 update public.business_fee_ledger set agreed_fee_cents=p_fee_cents,fee_status='agreed',notes=left(coalesce(p_notes,''),1000)
 where contract_id=p_contract_id and fee_status='pending_agreement';
 return found;
end $$;
revoke all on function public.record_business_contract_fee(uuid,bigint,text) from public,anon;
grant execute on function public.record_business_contract_fee(uuid,bigint,text) to authenticated;
