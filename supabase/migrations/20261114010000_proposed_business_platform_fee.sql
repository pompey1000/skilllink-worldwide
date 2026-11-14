-- Skill Link test-mode business-contract fee proposal.
-- A 10% platform fee is PROPOSED on the winning company's bid, not agreed,
-- invoiced, owed, or collected until separately accepted under written terms.
-- No payment processor, auto-billing, or collections are enabled.
-- The $500 temp-to-permanent conversion fee is separate and not auto-applied.

alter table public.business_fee_ledger
 add column if not exists proposed_fee_bps integer,
 add column if not exists proposed_fee_cents bigint;

alter table public.business_fee_ledger
 drop constraint if exists business_fee_ledger_proposed_fee_bps_check;
alter table public.business_fee_ledger
 add constraint business_fee_ledger_proposed_fee_bps_check
 check (proposed_fee_bps is null or proposed_fee_bps between 0 and 10000);

alter table public.business_fee_ledger
 drop constraint if exists business_fee_ledger_proposed_fee_cents_check;
alter table public.business_fee_ledger
 add constraint business_fee_ledger_proposed_fee_cents_check
 check (proposed_fee_cents is null or proposed_fee_cents >= 0);

-- Recalculate server-side. Bid amounts are cents and 1000 bps means 10%.
create or replace function public.skilllink_propose_business_fee()
returns trigger language plpgsql security definer set search_path = '' as $$
declare v_bid_amount bigint;
begin
 select b.amount_cents into v_bid_amount
 from public.business_contract_bids b
 where b.id = new.winning_bid_id and b.contract_id = new.contract_id and b.status = 'selected';
 if v_bid_amount is null then raise exception 'Selected bid is required for a fee proposal'; end if;
 if new.fee_status = 'pending_agreement' then
   new.proposed_fee_bps := 1000;
   new.proposed_fee_cents := round(v_bid_amount * 0.10)::bigint;
   new.agreed_fee_cents := null;
   new.notes := '10% platform fee proposed on the selected company bid. Not agreed or payable. No billing active. Separate conversion fee is not included.';
 end if;
 return new;
end $$;

drop trigger if exists skilllink_business_fee_proposal_insert on public.business_fee_ledger;
create trigger skilllink_business_fee_proposal_insert
before insert on public.business_fee_ledger
for each row execute function public.skilllink_propose_business_fee();

-- Backfill only existing pending fee records; never overwrite agreed or paid fees.
update public.business_fee_ledger f
set proposed_fee_bps = 1000,
    proposed_fee_cents = round(b.amount_cents * 0.10)::bigint,
    notes = '10% platform fee proposed on the selected company bid. Not agreed or payable. No billing active. Separate conversion fee is not included.'
from public.business_contract_bids b
where b.id = f.winning_bid_id
  and b.contract_id = f.contract_id
  and b.status = 'selected'
  and f.fee_status = 'pending_agreement'
  and f.agreed_fee_cents is null;

-- Note: the existing admin-only record_business_contract_fee RPC remains
-- a manual agreement-recording action; this migration does not invoke it.
