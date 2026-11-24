import { createClient } from "npm:@supabase/supabase-js@2";

const headers = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Access-Control-Allow-Headers": "authorization, apikey, content-type, x-client-info",
  "Content-Type": "application/json",
  "Cache-Control": "no-store",
};
const reply = (status: number, data: object) =>
  new Response(JSON.stringify(data), { status, headers });

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") return new Response(null, { headers });
  if (request.method !== "POST") return reply(405, { error: "Method not allowed" });
  const token = request.headers.get("authorization")?.match(/^Bearer (.+)$/i)?.[1];
  if (!token) return reply(401, { error: "Sign in to see your payouts." });

  try {
    const secret = Deno.env.get("STRIPE_SECRET_KEY");
    const publishableKey = Deno.env.get("STRIPE_PUBLISHABLE_KEY");
    if (!secret?.startsWith("sk_test_") || !publishableKey?.startsWith("pk_test_"))
      return reply(503, { error: "Payout testing is not configured yet." });

    const db = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
    const { data, error } = await db.auth.getUser(token);
    if (error || !data.user) return reply(401, { error: "Sign in again to see your payouts." });
    const binding = await db.from("personal_job_payout_accounts")
      .select("stripe_test_account_id").eq("user_id", data.user.id).maybeSingle();
    if (binding.error) throw new Error("Account lookup failed");
    if (!binding.data) return reply(409, { error: "Your personal-job payout account has not been connected yet." });

    // Enable only after the worker-paid Instant Payout pricing rule is set in Stripe.
    const instant = Deno.env.get("STRIPE_TEST_WORKER_PAYOUT_FEE_CONFIGURED") === "true";
    const session = await fetch("https://api.stripe.com/v1/account_sessions", {
      method: "POST",
      headers: { Authorization: "Bearer " + secret },
      body: new URLSearchParams({
        account: binding.data.stripe_test_account_id,
        "components[payouts][enabled]": "true",
        "components[payouts][features][instant_payouts]": String(instant),
        "components[payouts][features][standard_payouts]": "false",
        "components[payouts][features][edit_payout_schedule]": "false",
      }),
    });
    if (!session.ok) throw new Error("Stripe session unavailable");
    const { client_secret } = await session.json();
    if (!client_secret) throw new Error("Missing session secret");
    return reply(200, { clientSecret: client_secret, publishableKey });
  } catch {
    return reply(503, { error: "Payout details are temporarily unavailable." });
  }
});
