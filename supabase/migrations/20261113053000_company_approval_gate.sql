-- Company approval gate. Only server-side service role can approve.
alter table public.business_hiring_inquiries
 add column if not exists approval_status text not null default 'pending'
 check (approval_status in ('pending','approved','rejected')),
 add column if not exists reviewed_at timestamptz,
 add column if not exists review_notes text;
-- Existing inquiries remain pending until manually reviewed.
-- No browser-facing approval policy is granted. The company dashboard
-- must check approved status server-side before allowing job posting or worker contact.
