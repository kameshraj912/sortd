// sortd.page Worker. Runs first on every request (see wrangler.jsonc).
//
// www.sortd.page gets a permanent (301) redirect to https://sortd.page, so Google sees one
// copy of each page, not two. Everything else is served straight from assets.
// http -> https is not done here: it's "Always Use HTTPS" in the Cloudflare dashboard
// (SSL/TLS -> Edge Certificates), which runs before the Worker.
//
// POST /api/beta takes the "Join the beta" form and emails it to Raj through Cloudflare
// Email Routing. Nothing is stored: the email is the only copy.
//
// Needs, in the Cloudflare dashboard:
//   - Email Routing on for sortd.page (it already forwards support@).
//   - A verified destination address. Its email goes in a secret, so it's not in git:
//       npx wrangler secret put BETA_TO
//   - A Turnstile widget (dashboard -> Turnstile). Its SITE key goes in beta.html
//     (data-sitekey, it's public); its SECRET key goes in a secret, like BETA_TO:
//       npx wrangler secret put TURNSTILE_SECRET
import { EmailMessage } from "cloudflare:email";

const FROM = "beta@sortd.page";
const COUNTRIES = ["Australia", "Singapore", "Malaysia", "Other"];
const EMAIL_RE = /^[^\s@]{1,64}@[^\s@]+\.[^\s@]{2,}$/;
// Turnstile: the token must come from this form on these hosts.
const TURNSTILE_ACTION = "beta-signup";
const TURNSTILE_HOSTS = ["sortd.page", "www.sortd.page"];

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    if (url.hostname === "www.sortd.page") {
      return Response.redirect(`https://sortd.page${url.pathname}${url.search}`, 301);
    }
    // The app's "Learn more" links: /help#app-lock and friends live on the support page
    // (the browser keeps the #part), and /changelog is its "What's new" section.
    if (url.pathname === "/help") return Response.redirect("https://sortd.page/support", 301);
    if (url.pathname === "/changelog") return Response.redirect("https://sortd.page/support#whats-new", 301);
    if (url.pathname === "/api/beta") {
      if (request.method !== "POST") return json({ ok: false, error: "Use POST." }, 405);
      return handleBeta(request, env);
    }
    return env.ASSETS.fetch(request);
  },
};

async function handleBeta(request, env) {
  const wantsJSON = (request.headers.get("accept") || "").includes("application/json");
  const reply = (ok, error, status) => wantsJSON
    ? json(ok ? { ok: true } : { ok: false, error }, status || (ok ? 200 : 400))
    : Response.redirect(new URL(ok ? "/beta-thanks" : "/beta?error=1", request.url), 303);

  // Only accept the form from our own pages.
  // Some browsers send "Origin: null", which isn't a URL; treat anything unparseable as foreign.
  const origin = request.headers.get("origin");
  if (origin) {
    let host = "";
    try { host = new URL(origin).host; } catch {}
    if (host !== new URL(request.url).host) return reply(false, "Please use the form on sortd.page.");
  }

  // Flood guard: one IP can't script the form to bomb the inbox. 5/min, then 429.
  // Guarded so the Worker still runs if the binding isn't configured (e.g. local dev).
  if (env.BETA_LIMIT) {
    const ip = request.headers.get("cf-connecting-ip") || "unknown";
    const { success } = await env.BETA_LIMIT.limit({ key: ip });
    if (!success) return reply(false, "Too many sign-ups from your network. Give it a minute and try again.", 429);
  }

  let form;
  try { form = await request.formData(); } catch { return reply(false, "Something went wrong. Please try again."); }
  const field = (k, max) => clean(form.get(k), max);

  // Bots fill in the hidden "website" box. Pretend it worked.
  if (field("website", 200)) return reply(true);

  // Turnstile: proves a real browser solved Cloudflare's challenge. Stops scripted
  // floods regardless of IP - the layer per-IP rate limits can't provide. Fails
  // closed: with no secret configured, sign-ups stop rather than go unchecked.
  if (!env.TURNSTILE_SECRET) return reply(false, "Sign-ups are closed for a moment. Please email support@sortd.page.");
  const passed = await verifyTurnstile(field("cf-turnstile-response", 2048), env.TURNSTILE_SECRET, request.headers.get("cf-connecting-ip"));
  if (!passed) return reply(false, "Please tick the “I’m human” box and try again.");

  const email = field("email", 254).toLowerCase();
  const name = field("name", 80);
  const country = COUNTRIES.includes(field("country", 20)) ? field("country", 20) : "";
  const applePay = ["yes", "no", "not sure"].includes(field("applepay", 10)) ? field("applepay", 10) : "";

  if (!EMAIL_RE.test(email)) return reply(false, "That's not an email. Even your spam folder would reject it.");
  if (!name) return reply(false, "What should we call you? First name is fine.");
  if (!country) return reply(false, "Pick where you live. \"Other\" counts.");
  if (!applePay) return reply(false, "Pick an Apple Pay answer. \"Not sure\" is allowed.");
  if (!env.BETA_TO || !env.SEND_EMAIL) return reply(false, "Sign-ups are closed for a moment. Please email support@sortd.page.");

  const when = new Date().toISOString().replace("T", " ").slice(0, 16) + " UTC";
  const lines = [
    "New Sortd beta sign-up (expression of interest).",
    "",
    `Email:      ${email}`,
    `Name:       ${name || "-"}`,
    `Country:    ${country || "-"}`,
    `Apple Pay:  ${applePay || "-"}`,
    "",
    "Form:       sortd.page/beta",
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

// Turnstile server-side check. Cloudflare returns { success: true } only for a valid,
// unused token that matches our secret. We also require it to come from the beta form
// (action) on our own site (hostname), so a token solved elsewhere can't be reused here.
// Anything else (missing, reused, forged, wrong form or site) blocks. Error codes are
// logged (never the token or secret): "invalid-input-secret" means the stored secret
// doesn't belong to this widget.
async function verifyTurnstile(token, secret, ip) {
  if (!token) return false;
  const body = new FormData();
  body.set("secret", secret);
  body.set("response", token);
  if (ip) body.set("remoteip", ip);
  try {
    const r = await fetch("https://challenges.cloudflare.com/turnstile/v0/siteverify", { method: "POST", body });
    const data = await r.json();
    if (data.success !== true) {
      console.log("turnstile rejected", JSON.stringify(data["error-codes"] || []));
      return false;
    }
    if (data.action !== TURNSTILE_ACTION || !TURNSTILE_HOSTS.includes(data.hostname)) {
      console.log("turnstile wrong action or host", data.action, data.hostname);
      return false;
    }
    return true;
  } catch (e) {
    console.log("turnstile verify failed", e && e.message);
    return false;
  }
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
