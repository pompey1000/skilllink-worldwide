-- Populated by trusted onboarding after verifying account ownership.
-- These Stripe balances are dedicated to personal jobs. Warehouse payroll is separate.
create table public.personal_job_payout_accounts (
  user_id uuid primary key references auth.users(id),
  stripe_test_account_id text not null unique check (stripe_test_account_id ~ '^acct_[a-zA-Z0-9]+$')
);
alter table public.personal_job_payout_accounts enable row level security;
revoke all on public.personal_job_payout_accounts from public, anon, authenticated;
grant select, insert, update, delete on public.personal_job_payout_accounts to service_role;
