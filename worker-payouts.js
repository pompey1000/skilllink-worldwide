const status = document.querySelector("#status");
try {
  const db = window.supabase.createClient(
    "https://iiaskaknyfenglihfrpo.supabase.co",
    "sb_publishable_W21KLGIbvYUAQuE4Sgvs9A_pKK5SaWT"
  );
  async function createSession() {
    const { data, error } = await db.functions.invoke("worker-payout-session", { body: {} });
    if (error) {
      const details = await error.context?.json?.().catch(() => null);
      throw new Error(details?.error || "Payout details are currently unavailable.");
    }
    return data;
  }
  const { data: { session } } = await db.auth.getSession();
  if (!session) throw new Error("Sign in through your account to see payout details.");
  const first = await createSession();
  let firstSecret = first.clientSecret;
  const { loadConnectAndInitialize } = await import("https://esm.sh/@stripe/connect-js@3.3.0");
  const connect = loadConnectAndInitialize({
    publishableKey: first.publishableKey,
    fetchClientSecret: async () => {
      if (!firstSecret) return (await createSession()).clientSecret;
      const secret = firstSecret;
      firstSecret = null;
      return secret;
    },
  });
  const payouts = connect.create("payouts");
  payouts.setOnLoadError(() => { status.textContent = "Payout details could not load. Refresh to retry."; });
  document.querySelector("#payouts").appendChild(payouts);
  status.textContent = "";
  db.auth.onAuthStateChange((_event, current) => {
    if (current?.user.id !== session.user.id) {
      document.querySelector("#payouts").replaceChildren();
      connect.logout();
      status.textContent = "Reload to view the current account.";
    }
  });
} catch (error) {
  status.textContent = error.message;
}
