// https://inbox.sortd.page/setup — "set up forwarding on your computer".
//
// The app's QR code opens /setup#a=<address>. The address is in the fragment
// (after #), which browsers never send to the server, so it doesn't appear in
// any request log. The filter file is built in the browser from that.

import { filterXml, gmailQuery } from "./filters.js";
import { ADDRESS_ALPHABET, ADDRESS_LENGTH } from "./util.js";

const SECURITY_HEADERS = {
  "content-security-policy": "default-src 'none'; script-src 'self'; style-src 'self'; img-src 'self'; base-uri 'none'; form-action 'none'; frame-ancestors 'none'",
  "referrer-policy": "no-referrer",
  "x-content-type-options": "nosniff",
  "cache-control": "public, max-age=300",
};

const esc = (s) => String(s).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;");

export function setupHtml(domain) {
  const query = gmailQuery();
  return `<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="robots" content="noindex">
<title>Sortd forwarding setup</title>
<link rel="stylesheet" href="/setup.css">
<script src="/setup.js" defer></script>
</head>
<body>
<main>
<h1>Send receipts to Sortd</h1>
<p>Your email service forwards receipts and bank alerts to your private Sortd address.
Sortd on your iPhone reads them. Our server only ever holds them encrypted, for at most 24 hours.</p>

<label for="address">Your Sortd address</label>
<input id="address" type="email" autocomplete="off" spellcheck="false" placeholder="paste it from Sortd on your iPhone">
<p class="hint" id="address-hint">Open Sortd › Forwarding inbox on your iPhone to see it.</p>

<h2>Gmail</h2>
<p class="hint">Needs Gmail on a computer. The Gmail app can't make filters.</p>
<ol>
  <li>In Gmail, open <b>Settings</b> (the gear) › <b>See all settings</b> › <b>Forwarding and POP/IMAP</b>.</li>
  <li>Click <b>Add a forwarding address</b>, paste your Sortd address, then <b>Next</b> › <b>Proceed</b>.</li>
  <li>Open Sortd on your iPhone. It shows Google's confirmation. Tap <b>Confirm</b>, or type the code into Gmail and click <b>Verify</b>.</li>
  <li>Leave "Forward a copy of incoming mail" <b>off</b>. That would send Sortd every email. The filter below sends only receipts.</li>
  <li>Make the filter, one of two ways:
    <ul>
      <li><b>Import:</b> <button id="download" type="button">Download filter file</button> then in Gmail go to
        <b>Settings</b> › <b>Filters and Blocked Addresses</b> › <b>Import filters</b>, choose the file, tick it and click <b>Create filters</b>.</li>
      <li><b>By hand:</b> in <b>Filters and Blocked Addresses</b> click <b>Create a new filter</b>. In <b>Has the words</b> paste:
        <textarea id="query" readonly rows="4">${esc(query)}</textarea>
        <button id="copy" type="button">Copy</button>
        Click <b>Create filter</b>, tick <b>Forward it to</b>, pick your Sortd address, then <b>Create filter</b>.</li>
    </ul>
  </li>
  <li>Check the filter list says <b>Forward to</b> your Sortd address. If an imported filter doesn't, click <b>edit</b> on it and tick <b>Forward it to</b>.</li>
</ol>

<h2>Outlook.com, Hotmail, Live</h2>
<ol>
  <li>In Outlook on the web, open <b>Settings</b> › <b>Mail</b> › <b>Rules</b> › <b>Add new rule</b>. Name it "Sortd receipts".</li>
  <li>Condition: <b>Subject includes</b>. Add these words one by one: receipt, invoice, order confirmation, payment received, transaction alert, refund.</li>
  <li>Action: <b>Redirect to</b> your Sortd address. (Redirect keeps the shop or bank as the sender, which Sortd needs to read it properly.)</li>
  <li>Click <b>Save</b>. For bank alerts, add a second rule with <b>From</b> set to your bank's alert address.</li>
</ol>

<h2>Turning it off</h2>
<p>Delete the filter or rule, and remove the forwarding address. In Sortd, <b>Turn Off</b> deletes the address and anything waiting for your phone.</p>
<p class="hint">Privacy: <a href="https://sortd.page/privacy">sortd.page/privacy</a> · Domain: ${esc(domain)}</p>
</main>
</body>
</html>`;
}

/** The page's script. Embeds the same filterXml() the tests check. */
export function setupScript(domain) {
  const pattern = `^[${ADDRESS_ALPHABET}]{${ADDRESS_LENGTH}}@${domain.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")}$`;
  return `"use strict";
const filterXml = ${filterXml.toString()};
const QUERY = ${JSON.stringify(gmailQuery())};
const ADDRESS_RE = new RegExp(${JSON.stringify(pattern)});
const box = document.getElementById("address");
const hint = document.getElementById("address-hint");
const fromHash = new URLSearchParams(location.hash.slice(1)).get("a");
if (fromHash) box.value = fromHash.toLowerCase();
// Don't leave the address in the history or a bookmark.
if (location.hash) history.replaceState(null, "", location.pathname);
function address() {
  const a = box.value.trim().toLowerCase();
  if (!ADDRESS_RE.test(a)) { hint.textContent = "That isn't a Sortd address. Copy it from Sortd on your iPhone."; box.focus(); return null; }
  hint.textContent = "Open Sortd › Forwarding inbox on your iPhone to see it.";
  return a;
}
document.getElementById("download").addEventListener("click", () => {
  const a = address();
  if (!a) return;
  const blob = new Blob([filterXml(a, QUERY)], { type: "application/xml" });
  const link = document.createElement("a");
  link.href = URL.createObjectURL(blob);
  link.download = "sortd-gmail-filter.xml";
  link.click();
  setTimeout(() => URL.revokeObjectURL(link.href), 1000);
});
document.getElementById("copy").addEventListener("click", async (e) => {
  try { await navigator.clipboard.writeText(QUERY); e.target.textContent = "Copied"; }
  catch { document.getElementById("query").select(); }
});
`;
}

export const SETUP_CSS = `:root{color-scheme:light dark;--bg:#fff;--ink:#111;--muted:#666;--line:#ddd;--accent:#0a7}
@media (prefers-color-scheme:dark){:root{--bg:#111;--ink:#f2f2f2;--muted:#aaa;--line:#333}}
*{box-sizing:border-box}body{margin:0;background:var(--bg);color:var(--ink);font:17px/1.5 -apple-system,system-ui,sans-serif}
main{max-width:680px;margin:0 auto;padding:24px 16px 64px}h1{font-size:28px;margin:0 0 8px}h2{font-size:21px;margin-top:32px}
label{display:block;font-weight:600;margin-top:16px}input,textarea{width:100%;font:15px ui-monospace,Menlo,monospace;padding:10px;border:1px solid var(--line);border-radius:10px;background:transparent;color:inherit}
textarea{margin:8px 0}button{font:inherit;padding:8px 14px;border-radius:10px;border:1px solid var(--line);background:var(--ink);color:var(--bg);cursor:pointer}
.hint{color:var(--muted);font-size:15px}li{margin:8px 0}a{color:inherit}`;

export function serveSetup(path, domain) {
  if (path === "/setup" || path === "/setup/") {
    return new Response(setupHtml(domain), { headers: { ...SECURITY_HEADERS, "content-type": "text/html; charset=utf-8" } });
  }
  if (path === "/setup.js") {
    return new Response(setupScript(domain), { headers: { ...SECURITY_HEADERS, "content-type": "text/javascript; charset=utf-8" } });
  }
  if (path === "/setup.css") {
    return new Response(SETUP_CSS, { headers: { ...SECURITY_HEADERS, "content-type": "text/css; charset=utf-8" } });
  }
  return null;
}
