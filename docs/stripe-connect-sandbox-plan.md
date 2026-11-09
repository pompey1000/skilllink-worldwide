# Skill Link Worldwide — Stripe Connect sandbox implementation plan

Status: DESIGN ONLY. No live payment collection or worker transfers are enabled by this file.

## Existing architecture
- Static frontend on Vercel, GitHub repository, Supabase authentication/database.
- Existing bookings: customer request -> provider accept -> provider finished -> customer confirms.
- Existing reviews are distinct from payment approval.
- Stripe Connect sandbox has a test connected account; do not use its account ID as a production worker ID.

## Payment flow (proposed, subject to Stripe terms)
1. Provider quotes a fixed job amount; customer accepts it. Store currency and amount in integer cents, and a locked quote/version on booking.
2. Customer starts Stripe-hosted Checkout using a secure server-side endpoint. The server verifies the authenticated customer, booking ownership, quote, and worker identity; never trusts a browser-supplied amount.
3. Charge the customer on the platform, using separate charges and transfers. Record Stripe checkout session/payment intent IDs and reconcile via verified Stripe webhooks, not redirect success alone.
4. On successful paid webhook, booking becomes funded. No worker transfer yet. The platform bears refund/chargeback and applicable fee responsibilities.
5. Worker marks work finished; record server timestamp. Customer may approve or dispute during 72 hours. Approval can permit earlier release if explicitly intended; otherwise release after 72 hours with no open dispute. Define clear handling for unresponsive customers and unresolved disputes.
6. A secure scheduled server process rechecks paid status, completion, elapsed time, disputes, refunds, and idempotency before creating a Stripe transfer to the worker's verified connected account. Keep commission in platform balance. Do not rely on a browser button or timer for release.
7. Worker bank payouts are a separate Stripe process; manual payout settings on connected accounts do not themselves delay the platform-to-worker transfer.
8. Tips must be recorded separately and fully allocated to the worker unless disclosed otherwise. Refunds, chargebacks, cancellations, partial payments, and failed transfers require explicit state transitions and reconciliation.

## Proposed database tables (not yet migrated)
- worker_stripe_accounts: provider_id, stripe_account_id, onboarding status, charges_enabled, payouts_enabled.
- booking_quotes: booking_id, amount_cents, currency, provider_id, accepted_at, immutable version.
- booking_payments: booking_id, checkout_session_id, payment_intent_id, charge_id, paid_amount_cents, commission_cents, tip_cents, status, timestamps.
- booking_payment_events: unique stripe_event_id, type, received_at, processed_at, result.
- booking_disputes: booking_id, reason, status, created_at, resolved_at.
- booking_transfers: booking_id, stripe_transfer_id, amount_cents, status, idempotency_key, timestamps.

## Security and deployment
- Stripe secret API keys and webhook signing secrets belong only in server-side environment variables; never GitHub files, browser JavaScript, or chat.
- Prefer Supabase Edge Functions or Vercel server functions for authenticated checkout, connected account onboarding, verified webhooks, and transfer release.
- Use Supabase row-level security for user-visible records; restrict financial writes to trusted server functions.
- All operations must be idempotent. Store event IDs and transfer IDs. Use an atomic release claim/lock to avoid double transfers.
- Start with Stripe sandbox keys and test accounts only. No live checkout until end-to-end tests, support confirmation of transfer timing, risk review, and legal/policy review.
- Stripe is not automatically an escrow service. Avoid marketing funds as escrow without appropriate authorization.

## Implementation sequence
1. Confirm where server functions and secrets will be deployed (Vercel vs Supabase).
2. Add database migration and RLS policies.
3. Add sandbox Stripe Connect onboarding function.
4. Add sandbox checkout session creation and verified webhook.
5. Add customer payment status display.
6. Add completion, 72-hour review/dispute workflow and secure transfer release job.
7. Test payment, fee, tip, refund, chargeback, duplicate webhook, failed transfer, and dispute paths.
8. Only then review live launch readiness.
