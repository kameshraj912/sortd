// TXT lookups over DNS-over-HTTPS (Cloudflare's own resolver, so the query
// never leaves Cloudflare). Used for DKIM keys and DMARC policies only: the
// names looked up are the sender's domain, never the user's address.

const DOH = "https://cloudflare-dns.com/dns-query";

/**
 * Returns the TXT records for `name` as strings (each record's parts joined),
 * [] when there are none, or throws on a lookup failure (so callers can tell
 * "no key" from "couldn't ask").
 */
export async function resolveTxt(name, fetcher = fetch) {
  const url = `${DOH}?name=${encodeURIComponent(name)}&type=TXT`;
  const res = await fetcher(url, { headers: { accept: "application/dns-json" } });
  if (!res.ok) throw new Error(`doh ${res.status}`);
  const body = await res.json();
  // 0 = NOERROR, 3 = NXDOMAIN (no such name: a real "no").
  if (body.Status === 3) return [];
  if (body.Status !== 0) throw new Error(`dns status ${body.Status}`);
  return (body.Answer || []).filter((a) => a.type === 16).map((a) => joinTxt(a.data));
}

/** '"v=DKIM1; k=rsa; " "p=MIIB..."' -> 'v=DKIM1; k=rsa; p=MIIB...' */
export function joinTxt(data) {
  const parts = String(data).match(/"((?:[^"\\]|\\.)*)"/g);
  if (!parts) return String(data);
  // Presentation format escapes: \" \\ and \DDD (a decimal byte).
  const unescape = (s) => s.replace(/\\(\d{3}|.)/g, (_, g) => (g.length === 3 ? String.fromCharCode(Number(g)) : g));
  return parts.map((p) => unescape(p.slice(1, -1))).join("");
}
