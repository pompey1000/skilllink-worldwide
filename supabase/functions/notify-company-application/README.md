# Skill Link company application email notifications (not deployed)

This Edge Function sends a **non-sensitive email alert** to the verified company contact email when a worker submits an application. The worker's name, email, phone, and application answers stay in the restricted Skill Link applicant inbox; the email contains only the job title and sign-in link.

## Requirements

1. Run `supabase/migrations/20261114030000_company_application_notifications.sql` in Supabase SQL Editor.
2. Verify a sender domain in [Resend](https://resend.com/domains) and obtain a Resend API key.
3. In Supabase **Edge Functions → Secrets**, configure:
   - `RESEND_API_KEY`: your private email API key (never share it in chat or GitHub).
   - `APPLICATION_FROM_EMAIL`: a sender on the verified domain, for example `Skill Link <notifications@YOUR-VERIFIED-DOMAIN>`.
   - `APPLICATION_WEBHOOK_SECRET`: a long random value you generate and keep secret.
   - `SUPABASE_URL` and `SUPABASE_SERVICE_ROLE_KEY` should be injected by Supabase; do not put these in the repository.
4. Deploy `supabase/functions/notify-company-application/index.ts` as an Edge Function named `notify-company-application`. For database webhooks, **turn off Verify JWT** for this function; the code requires the separate webhook secret.
5. In Supabase **Database → Webhooks**, create a webhook:
   - Table: `public.company_worker_applications`
   - Event: **INSERT**
   - Method: **POST**
   - URL: `https://iiaskaknyfenglihfrpo.supabase.co/functions/v1/notify-company-application`
   - HTTP header `x-skilllink-webhook-secret`: the exact same `APPLICATION_WEBHOOK_SECRET` value.
   - Content-Type: application/json.
6. Test with a new application for an approved company, and confirm the alert email arrives and the company's private Applicant Inbox has the record.
7. Check `company_application_notifications` statuses in SQL Editor if delivery needs troubleshooting. Marking an email as sent means provider accepted it, **not** that the recipient opened it.

**Keep the system in test mode until email notifications, worker privacy rules, retention policy, anti-spam controls, and company identity checks have been tested.** Do not enable billing, worker fees, or payroll through this feature.
