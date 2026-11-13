-- Stripe Sandbox payment foundation. Apply only after review.
-- Financial records are server-managed. No payment is activated by this migration.
create table if not exists public.worker_stripe_accounts (
 provider_id uuid primary key references auth.users(id) on delete cascade,
 stripe_account_id text unique not null,
 charges_enabled boolean not null default false,
 payouts_enabled boolean not null default false,
 onboarding_complete boolean not null default false,
 updated_at timestamptz not null default now()
);
create table if not exists public.booking_quotes (
 id uuid primary key default gen_random_uuid(),
 booking_id uuid not null references public.bookings(id) on delete cascade,
 provider_id uuid not null references auth.users(id),
 amount_cents bigint not null check (amount_cents > 0),
 currency text not null default 'usd' check (currency = 'usd'),
 version integer not null default 1 check (version > 0),
 customer_accepted_at timestamptz,
 created_at timestamptz not null default now(),
 unique (booking_id, version)
);
create table if not exists public.booking_payments (
 booking_id uuid primary key references public.bookings(id) on delete cascade,
 quote_id uuid not null unique references public.booking_quotes(id),
 checkout_session_id text unique,
 payment_intent_id text unique,
 charge_id text unique,
 amount_cents bigint not null check (amount_cents > 0),
 platform_fee_cents bigint not null check (platform_fee_cents >= 0),
 tip_cents bigint not null default 0 check (tip_cents >= 0),
 currency text not null default 'usd' check (currency = 'usd'),
 status text not null default 'awaiting_payment'
  check (status in ('awaiting_payment','checkout_open','paid','refunded','partially_refunded','disputed','failed')),
 paid_at timestamptz,
 updated_at timestamptz not null default now(),
 check (platform_fee_cents <= amount_cents)
);
create table if not exists public.booking_payment_events (
 stripe_event_id text primary key,
 event_type text not null,
 received_at timestamptz not null default now(),
 processed_at timestamptz,
 processing_result text
);
create table if not exists public.booking_payment_disputes (
 id uuid primary key default gen_random_uuid(),
 booking_id uuid not null references public.bookings(id) on delete cascade,
 opened_by uuid references auth.users(id),
 reason text not null,
 status text not null default 'open' check (status in ('open','resolved','rejected')),
 created_at timestamptz not null default now(),
 resolved_at timestamptz
);
create table if not exists public.booking_transfers (
 booking_id uuid primary key references public.bookings(id) on delete cascade,
 stripe_transfer_id text unique,
 amount_cents bigint not null check (amount_cents > 0),
 status text not null default 'pending' check (status in ('pending','processing','transferred','failed','reversed')),
 idempotency_key text not null unique,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now()
);
-- Default-deny client access: only privileged server code may read/write financial tables.
alter table public.worker_stripe_accounts enable row level security;
alter table public.booking_quotes enable row level security;
alter table public.booking_payments enable row level security;
alter table public.booking_payment_events enable row level security;
alter table public.booking_payment_disputes enable row level security;
alter table public.booking_transfers enable row level security;
revoke all on public.worker_stripe_accounts, public.booking_quotes,
 public.booking_payments, public.booking_payment_events,
 public.booking_payment_disputes, public.booking_transfers from anon, authenticated;
