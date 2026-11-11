
import { createClient } from "npm:@supabase/supabase-js@2";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, apikey, content-type, x-client-info",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Content-Type": "application/json",
};

const respond = (status: number, body: unknown) =>
  new Response(JSON.stringify(body), {
    status,
    headers: cors,
  });

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response(null, { status: 204, headers: cors });
  }

  if (req.method !== "POST") {
    return respond(405, { error: "Method not allowed" });
  }

  try {
    const authorization = req.headers.get("Authorization");

    if (!authorization?.startsWith("Bearer ")) {
      return respond(401, { error: "Sign in required" });
    }

    const url = Deno.env.get("SUPABASE_URL");
    const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
    const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");

    if (!url || !anonKey || !serviceKey) {
      return respond(500, { error: "Server configuration missing" });
    }

    const authClient = createClient(url, anonKey);
    const token = authorization.slice(7);

    const { data: authData, error: authError } =
      await authClient.auth.getUser(token);

    if (authError || !authData.user) {
      return respond(401, { error: "Invalid session" });
    }

    const body = await req.json().catch(() => null);
    const quoteId = body?.quote_id;

    if (
      typeof quoteId !== "string" ||
      !/^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(quoteId)
    ) {
      return respond(400, { error: "Valid quote_id required" });
    }

    const admin = createClient(url, serviceKey);

    const { data: quote, error: quoteError } = await admin
      .from("booking_quotes")
      .select("id, booking_id, provider_id, amount_cents, currency, status")
      .eq("id", quoteId)
      .single();

    if (quoteError || !quote) {
      return respond(404, { error: "Quote not found" });
    }

    const { data: booking, error: bookingError } = await admin
      .from("bookings")
      .select("id, customer_id, provider_id, status")
      .eq("id", quote.booking_id)
      .single();

    if (bookingError || !booking) {
      return respond(404, { error: "Booking not found" });
    }

    if (booking.customer_id !== authData.user.id) {
      return respond(403, { error: "Not your booking" });
    }

    if (booking.provider_id !== quote.provider_id) {
      return respond(409, { error: "Provider mismatch" });
    }

    if (quote.status !== "proposed") {
      return respond(409, { error: "Quote is not pending approval" });
    }

    if (
      quote.currency !== "usd" ||
      !Number.isSafeInteger(Number(quote.amount_cents)) ||
      Number(quote.amount_cents) <= 0
    ) {
      return respond(409, { error: "Invalid quote amount" });
    }

    // Approval must be completed by a database transaction
    // that rechecks booking and quote state atomically.
    return respond(503, {
      error: "Approval temporarily unavailable",
      message: "Secure approval transaction not configured yet",
    });
  } catch {
    return respond(500, { error: "Unable to process approval" });
  }
});
