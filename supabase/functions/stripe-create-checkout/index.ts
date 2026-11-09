// Skill Link Worldwide — Stripe Checkout sandbox (NOT YET DEPLOYED)
// Fail-closed: checkout cannot start until server-side booking quote verification
// and payment records/webhooks are implemented.
// This file is intentionally safe to commit: no API keys or personal data.
const json = (data: unknown, status = 200) =>
  new Response(JSON.stringify(data), {
    status,
    headers: { "content-type": "application/json", "cache-control": "no-store" },
  });

Deno.serve(async (req) => {
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);

  const key = Deno.env.get("STRIPE_SECRET_KEY");
  if (!key || !key.startsWith("sk_test_")) {
    return json({ error: "Stripe sandbox secret is not configured" }, 503);
  }

  // IMPORTANT: Never accept a price, commission, tip or worker account from
  // browser input. First verify the Supabase user's JWT, booking ownership,
  // accepted immutable server-side quote, and booking's unpaid status.
  // Then create and persist a Checkout Session, with a unique idempotency key.
  // Verify payment via a signed Stripe webhook, not the success redirect.
  // A separate secure process must handle transfers after the review period.
  return json({
    ready: false,
    message: "Stripe sandbox key detected; secure booking checkout is not enabled yet.",
    next: "Implement booking quote validation, payment persistence and webhook before enabling checkout.",
  }, 503);
});
