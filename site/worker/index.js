// sortd.page Worker. Runs first on every request (see wrangler.jsonc).
//
// www.sortd.page gets a permanent (301) redirect to https://sortd.page, so Google sees one
// copy of each page, not two. Everything else is served straight from assets.
// http -> https is not done here: it's "Always Use HTTPS" in the Cloudflare dashboard
// (SSL/TLS -> Edge Certificates), which runs before the Worker.
//
// POST /api/beta takes the "Join the beta" form and emails it to Raj through Cloudflare
// Email Routing, with the iPhone they say they have and the device and system the browser reports. Nothing is stored: the
// email is the only copy.
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
// Where a sign-up goes next: the public link of the "Website Beta" TestFlight group (App Store
// Connect > TestFlight > Website Beta), kept apart from the invite-only "Beta" group.
// It is handed out only after a good sign-up, so it is not in any page's source. TestFlight
// lists public-link testers without a name or email, so the sign-up email is the only record
// of who joined.
const TESTFLIGHT_URL = "https://testflight.apple.com/join/p3VQ6YGk";
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
  // `next` is the TestFlight link, given only once the sign-up email has been sent.
  const reply = (ok, error, status, next) => wantsJSON
    ? json(ok ? (next ? { ok: true, next } : { ok: true }) : { ok: false, error }, status || (ok ? 200 : 400))
    : Response.redirect(ok ? (next || new URL("/beta-thanks", request.url)) : new URL("/beta?error=1", request.url), 303);

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
  // Their own answer to "Which iPhone?". Not required here, so a page cached from before the
  // question existed can still sign up; the form itself requires it.
  const iphone = /^(iPhone [\w ()]{1,30}|Not sure)$/.test(field("iphone", 40)) ? field("iphone", 40) : "";

  if (!EMAIL_RE.test(email)) return reply(false, "That's not an email. Even your spam folder would reject it.");
  if (!name) return reply(false, "What should we call you? First name is fine.");
  if (!country) return reply(false, "Pick where you live. \"Other\" counts.");
  if (!applePay) return reply(false, "Pick an Apple Pay answer. \"Not sure\" is allowed.");
  if (!env.BETA_TO || !env.SEND_EMAIL) return reply(false, "Sign-ups are closed for a moment. Please email support@sortd.page.");

  const when = new Date().toISOString().replace("T", " ").slice(0, 16) + " UTC";
  const ua = clean(request.headers.get("user-agent"), 400);
  // site.js adds the screen size, e.g. "393x852@3". Missing when the form posts without JavaScript.
  const screen = /^\d{3,4}x\d{3,4}@\d(\.\d{1,2})?$/.test(field("screen", 16)) ? field("screen", 16) : "";
  const dev = device(ua, screen);
  const lines = [
    "New Sortd beta sign-up (expression of interest).",
    "",
    `Email:      ${email}`,
    `Name:       ${name || "-"}`,
    `Country:    ${country || "-"}`,
    `Apple Pay:  ${applePay || "-"}`,
    `iPhone:     ${iphone ? iphone + " (their answer)" : "-"}`,
    "",
    `Detected:   ${dev.device}`,
    `System:     ${dev.os}`,
    `Screen:     ${screen || "-"}`,
    `Browser:    ${ua || "-"}`,
    "",
    "Form:       sortd.page/beta",
    `Sent:       ${when}`,
    `From:       ${request.headers.get("cf-ipcountry") || "?"} (Cloudflare's guess)`,
    "",
    "Reply to this email to write to them directly.",
    "They were sent straight to TestFlight after signing up. No reply needed.",
    "TestFlight shows public-link testers without names, so this email is your record of who joined.",
  ];
  const subject = `Beta sign-up: ${name || email}${country ? " (" + country + ")" : ""}`;

  try {
    const raw = mime({ from: FROM, to: env.BETA_TO, replyTo: email, subject, text: lines.join("\r\n") });
    await env.SEND_EMAIL.send(new EmailMessage(FROM, env.BETA_TO, raw));
  } catch (e) {
    console.log("beta email failed", e && e.message);
    return reply(false, "We couldn't save that just now. Please try again, or email support@sortd.page.");
  }
  return reply(true, null, 200, TESTFLIGHT_URL);
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

// The phone and system a sign-up came from, read from the browser's User-Agent header (what
// the browser tells every website) and the screen size site.js sends with the form. It is the
// device the form was filled in on, which may not be the iPhone they install on. Limits:
//   - Safari never names the iPhone model. Only Instagram's and Facebook's in-app browsers do.
//     For the rest, the screen size narrows it to the few iPhones that share that screen.
//     Display Zoom ("Larger Text") makes an iPhone report a smaller screen, so it can mislead.
//   - From iOS 26 Safari freezes the "OS 18_6" part, so Safari's own version (Version/26.1)
//     is the guide to the iOS version. Other browsers on iOS 26 only show the frozen number.
//   - An iPad in Safari says it is a Mac.
const IPHONES = {
  "iPhone12,1": "iPhone 11", "iPhone12,3": "iPhone 11 Pro", "iPhone12,5": "iPhone 11 Pro Max", "iPhone12,8": "iPhone SE (2nd generation)",
  "iPhone13,1": "iPhone 12 mini", "iPhone13,2": "iPhone 12", "iPhone13,3": "iPhone 12 Pro", "iPhone13,4": "iPhone 12 Pro Max",
  "iPhone14,4": "iPhone 13 mini", "iPhone14,5": "iPhone 13", "iPhone14,2": "iPhone 13 Pro", "iPhone14,3": "iPhone 13 Pro Max",
  "iPhone14,6": "iPhone SE (3rd generation)", "iPhone14,7": "iPhone 14", "iPhone14,8": "iPhone 14 Plus",
  "iPhone15,2": "iPhone 14 Pro", "iPhone15,3": "iPhone 14 Pro Max", "iPhone15,4": "iPhone 15", "iPhone15,5": "iPhone 15 Plus",
  "iPhone16,1": "iPhone 15 Pro", "iPhone16,2": "iPhone 15 Pro Max",
  "iPhone17,3": "iPhone 16", "iPhone17,4": "iPhone 16 Plus", "iPhone17,1": "iPhone 16 Pro", "iPhone17,2": "iPhone 16 Pro Max", "iPhone17,5": "iPhone 16e",
  "iPhone18,3": "iPhone 17", "iPhone18,1": "iPhone 17 Pro", "iPhone18,2": "iPhone 17 Pro Max", "iPhone18,4": "iPhone Air",
};
// Screen size in points (portrait) and pixel ratio -> the iPhones with that screen.
// Keep in step with GROUPS in site.js, which uses the same table to order the "Which iPhone?" list.
const SCREENS = {
  "375x667@2": "iPhone SE (2nd or 3rd generation)",
  "414x896@2": "iPhone 11",
  "375x812@3": "iPhone 11 Pro, 12 mini or 13 mini",
  "414x896@3": "iPhone 11 Pro Max",
  "390x844@3": "iPhone 12, 12 Pro, 13, 13 Pro, 14, 16e or 17e",
  "428x926@3": "iPhone 12 Pro Max, 13 Pro Max or 14 Plus",
  "393x852@3": "iPhone 14 Pro, 15, 15 Pro or 16",
  "430x932@3": "iPhone 14 Pro Max, 15 Plus, 15 Pro Max or 16 Plus",
  "402x874@3": "iPhone 16 Pro, 17, 17 Pro or 18 Pro",
  "440x956@3": "iPhone 16 Pro Max, 17 Pro Max or 18 Pro Max",
  "420x912@3": "iPhone Air",
};

function device(ua, screen) {
  if (!ua) return { device: "-", os: "-" };
  const dots = (v) => v.replace(/_/g, ".");
  // In-app browsers that give the model code and the real iOS version.
  const ig = ua.match(/Instagram [\d.]+ \((\w+,\d+); iOS ([\d_.]+)/);
  const fbModel = ua.match(/FBDV\/(\w+,\d+)/), fbOS = ua.match(/FBSV\/([\d.]+)/);
  const model = ig ? ig[1] : fbModel ? fbModel[1] : "";
  const realOS = ig ? dots(ig[2]) : fbModel && fbOS ? fbOS[1] : "";

  if (/iPhone|iPad|iPod/.test(ua)) {
    const kind = /iPad/.test(ua) ? "iPad" : /iPod/.test(ua) ? "iPod touch" : "iPhone";
    let name = `${kind} (the browser doesn't say which model)`;
    if (model) name = `${IPHONES[model] || kind} (${model})`;
    else if (kind === "iPhone" && SCREENS[screen]) name = `${SCREENS[screen]}, or a newer iPhone with the same screen`;
    const token = ua.match(/ OS (\d+)_(\d+)(?:_(\d+))?/);
    const safari = ua.match(/Version\/(\d+)\.(\d+)/);
    let os = "iOS, version not given";
    if (realOS) os = `iOS ${realOS}`;
    else if (safari && +safari[1] >= 26) os = `iOS ${safari[1]}.${safari[2]} (going by the Safari version)`;
    else if (token) {
      const v = token.slice(1).filter(Boolean).join(".");
      // No Safari version to go by and the number is at the frozen value: could be anything newer.
      const frozen = !safari && +token[1] === 18 && +token[2] >= 6;
      os = frozen ? `iOS ${v} or newer (the browser hides it)` : `iOS ${v}`;
    }
    return { device: name, os };
  }
  if (/Android/.test(ua)) return { device: "Android phone or tablet", os: "Android" };
  if (/Macintosh/.test(ua)) return { device: "Mac (or an iPad in Safari)", os: "macOS or iPadOS" };
  if (/Windows/.test(ua)) return { device: "Windows PC", os: "Windows" };
  return { device: "Not sure, see Browser below", os: "-" };
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
