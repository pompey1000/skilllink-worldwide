// Supabase Edge Function: notify-company-application
// Trigger it with a Supabase Database Webhook on INSERT into
// public.company_worker_applications after configuring the secrets described in README.
// No applicant PII is put in the outgoing email.
import { createClient } from "npm:@supabase/supabase-js@2";

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { "content-type": "application/json" } });

Deno.serve(async (request) => {
  if (request.method !== "POST") return json({ error: "Method not allowed" }, 405);
  const webhookSecret = Deno.env.get("APPLICATION_WEBHOOK_SECRET");
  const suppliedSecret = request.headers.get("x-skilllink-webhook-secret");
  if (!webhookSecret || !suppliedSecret || suppliedSecret !== webhookSecret) {
    return json({ error: "Unauthorized" }, 401);
  }

  const url = Deno.env.get("SUPABASE_URL");
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  const resendKey = Deno.env.get("RESEND_API_KEY");
  const sender = Deno.env.get("APPLICATION_FROM_EMAIL");
  const inboxLink = "https://skilllinkworldwide.com/business-contracts.html#applicants";
  if (!url || !serviceKey || !resendKey || !sender) return json({ error: "Notification secrets not configured" }, 503);

  let payload: { type?: string; table?: string; record?: { id?: string } };
  try { payload = await request.json(); }
  catch { return json({ error: "Invalid JSON" }, 400); }
  if (payload.type !== "INSERT" || payload.table !== "company_worker_applications") {
    return json({ error: "Unsupported webhook event" }, 400);
  }
  const id = payload.record?.id;
  if (!id || !/^[a-f0-9-]{36}$/i.test(id)) return json({ error: "Missing application ID" }, 400);
  const db = createClient(url, serviceKey, { auth: { autoRefreshToken: false, persistSession: false } });

  // Always retrieve the destination from our database, never from webhook text.
  const { data: application, error: applicationError } = await db
    .from("company_worker_applications").select("id,company_id,opening_id")
    .eq("id", id).maybeSingle();
  if (applicationError || !application) return json({ error: "Application not found" }, 404);
  const { data: company } = await db.from("business_accounts")
    .select("contact_email,company_name,status").eq("user_id", application.company_id).maybeSingle();
  if (!company || company.status !== "approved" || !company.contact_email) return json({ error: "Approved company not found" }, 400);
  const { data: opening } = await db.from("company_job_openings").select("title")
    .eq("id", application.opening_id).eq("company_id", application.company_id).maybeSingle();
  if (!opening) return json({ error: "Job opening not found" }, 400);

  const { data: existing } = await db.from("company_application_notifications")
    .select("status").eq("application_id", id).maybeSingle();
  if (existing?.status === "sent") return json({ ok: true, duplicate: true });
  if (existing?.status === "processing") return json({ ok: true, queued_or_processing: true });

  // Reserve notification before sending. Failed deliveries can be retried explicitly.
  let reservation: { application_id: string } | null = null;
  if (existing?.status === "failed") {
    const result = await db.from("company_application_notifications")
      .update({ status: "processing", updated_at: new Date().toISOString() })
      .eq("application_id", id).eq("status", "failed")
      .select("application_id").maybeSingle();
    if (result.error) return json({ error: "Unable to retry notification" }, 500);
    reservation = result.data;
  } else {
    const result = await db.from("company_application_notifications")
      .upsert({ application_id: id, status: "processing", updated_at: new Date().toISOString() },
        { onConflict: "application_id", ignoreDuplicates: true })
      .select("application_id").maybeSingle();
    if (result.error) return json({ error: "Unable to reserve notification" }, 500);
    reservation = result.data;
  }
  if (!reservation) return json({ ok: true, queued_or_processing: true });

  const subject = "New worker application on Skill Link Worldwide";
  const title = opening.title.replace(/[\r\n]/g, " ").slice(0, 160);
  const plain = "A new worker application was submitted for your job opening: " + title +
    "\n\nSign in to review it privately: " + inboxLink +
    "\n\nThis is an automated notification. Do not reply with applicant personal data.";
  let message: Response;
  try {
    message = await fetch("https://api.resend.com/emails", {
      method: "POST",
      headers: {
        authorization: "Bearer " + resendKey,
        "content-type": "application/json",
        "Idempotency-Key": "skilllink-application-" + id,
      },
      body: JSON.stringify({ from: sender, to: [company.contact_email], subject, text: plain }),
    });
  } catch {
    await db.from("company_application_notifications").update({ status: "failed", updated_at: new Date().toISOString() }).eq("application_id", id);
    return json({ error: "Email provider unreachable" }, 502);
  }
  if (!message.ok) {
    await db.from("company_application_notifications").update({ status: "failed", updated_at: new Date().toISOString() }).eq("application_id", id);
    return json({ error: "Email provider rejected notification", provider_status: message.status }, 502);
  }
  await db.from("company_application_notifications")
    .update({ status: "sent", updated_at: new Date().toISOString() }).eq("application_id", id);
  return json({ ok: true });
});
