// sortd.page Worker. Static pages are served straight from assets; only /api/* runs here.
//
// POST /api/beta takes the "Join the beta" form and emails it to Raj through Cloudflare
// Email Routing. Nothing is stored: the email is the only copy.
//
// Needs, in the Cloudflare dashboard:
//   - Email Routing on for sortd.page (it already forwards support@).
//   - A verified destination address. Its email goes in a secret, so it's not in git:
//       npx wrangler secret put BETA_TO
import { EmailMessage } from "cloudflare:email";

const FROM = "beta@sortd.page";
const COUNTRIES = ["Australia", "Singapore", "Malaysia", "Other"];
const EMAIL_RE = /^[^\s@]{1,64}@[^\s@]+\.[^\s@]{2,}$/;

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    if (url.pathname === "/api/beta") {
      if (request.method !== "POST") return json({ ok: false, error: "Use POST." }, 405);
      return handleBeta(request, env);
    }
    return env.ASSETS.fetch(request);
  },
};

async function handleBeta(request, env) {
  const wantsJSON = (request.headers.get("accept") || "").includes("application/json");
  const reply = (ok, error) => wantsJSON
    ? json(ok ? { ok: true } : { ok: false, error }, ok ? 200 : 400)
    : Response.redirect(new URL(ok ? "/beta-thanks" : "/beta?error=1", request.url), 303);

  // Only accept the form from our own pages.
  const origin = request.headers.get("origin");
  if (origin && new URL(origin).host !== new URL(request.url).host) return reply(false, "Please use the form on sortd.page.");

  let form;
  try { form = await request.formData(); } catch { return reply(false, "Something went wrong. Please try again."); }
  const field = (k, max) => clean(form.get(k), max);

  // Bots fill in the hidden "website" box. Pretend it worked.
  if (field("website", 200)) return reply(true);

  const email = field("email", 254).toLowerCase();
  const name = field("name", 80);
  const country = COUNTRIES.includes(field("country", 20)) ? field("country", 20) : "";
  const applePay = ["yes", "no", "not sure"].includes(field("applepay", 10)) ? field("applepay", 10) : "";
  const gmail = field("gmail", 254).toLowerCase();

  if (!EMAIL_RE.test(email)) return reply(false, "That's not an email address. Try again, we'll wait.");
  if (gmail && !EMAIL_RE.test(gmail)) return reply(false, "That doesn't look like a Gmail address.");
  if (!env.BETA_TO || !env.SEND_EMAIL) return reply(false, "Sign-ups are closed for a moment. Please email support@sortd.page.");

  const when = new Date().toISOString().replace("T", " ").slice(0, 16) + " UTC";
  const lines = [
    "New Sortd beta sign-up (expression of interest).",
    "",
    `Email:      ${email}`,
    `Name:       ${name || "-"}`,
    `Country:    ${country || "-"}`,
    `Apple Pay:  ${applePay || "-"}`,
    `Gmail:      ${gmail || "-"}`,
    "",
    `Sent:       ${when}`,
    `From:       ${request.headers.get("cf-ipcountry") || "?"} (Cloudflare's guess)`,
    "",
    "Reply to this email to write to them directly.",
    "When the beta opens, send them the TestFlight link (see docs/BetaEmails.md).",
  ];
  const subject = `Beta sign-up: ${name || email}${country ? " (" + country + ")" : ""}`;

  try {
    const raw = mime({ from: FROM, to: env.BETA_TO, replyTo: email, subject, text: lines.join("\r\n") });
    await env.SEND_EMAIL.send(new EmailMessage(FROM, env.BETA_TO, raw));
  } catch (e) {
    console.log("beta email failed", e && e.message);
    return reply(false, "We couldn't save that just now. Please try again, or email support@sortd.page.");
  }
  return reply(true);
}

// One line of plain text: no control characters (stops header injection), trimmed, capped.
function clean(v, max) {
  return String(v == null ? "" : v).replace(/[\u0000-\u001f\u007f]+/g, " ").trim().slice(0, max);
}

function json(body, status = 200) {
  return new Response(JSON.stringify(body), { status, headers: { "content-type": "application/json", "cache-control": "no-store" } });
}

function b64(s) {
  const bytes = new TextEncoder().encode(s);
  let bin = "";
  for (const b of bytes) bin += String.fromCharCode(b);
  return btoa(bin);
}

function mime({ from, to, replyTo, subject, text }) {
  const id = `<${crypto.randomUUID()}@sortd.page>`;
  return [
    `From: "Sortd beta form" <${from}>`,
    `To: <${to}>`,
    `Reply-To: <${replyTo}>`,
    `Subject: =?UTF-8?B?${b64(subject)}?=`,
    `Message-ID: ${id}`,
    `Date: ${new Date().toUTCString()}`,
    "MIME-Version: 1.0",
    "Content-Type: text/plain; charset=utf-8",
    "Content-Transfer-Encoding: base64",
    "",
    b64(text).replace(/.{76}/g, "$&\r\n"),
  ].join("\r\n");
}
