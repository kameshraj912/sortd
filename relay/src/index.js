// Passes requests on to PostHog's US cloud, unchanged, from relay.sortd.page.
// PostHog's own Cloudflare Worker recipe (posthog.com/docs/advanced/proxy/cloudflare),
// trimmed to what the iOS SDK uses. Nothing is logged or stored.
//
// - Cookies and Authorization headers are dropped before forwarding.
// - The caller's address goes on as X-Forwarded-For, so PostHog's country
//   and city stay right instead of showing Cloudflare's data centre.
// - /static/ and /array/ (SDK files and remote config) come from the asset host
//   and are cached at the edge.

const API_HOST = "us.i.posthog.com";
const ASSET_HOST = "us-assets.i.posthog.com";

export default {
  async fetch(request, env, ctx) {
    const url = new URL(request.url);
    const path = url.pathname + url.search;
    if (url.pathname.startsWith("/static/") || url.pathname.startsWith("/array/")) {
      return asset(request, path, ctx);
    }
    return forward(request, path);
  },
};

async function asset(request, path, ctx) {
  let response = await caches.default.match(request);
  if (!response) {
    response = await fetch(`https://${ASSET_HOST}${path}`);
    ctx.waitUntil(caches.default.put(request, response.clone()));
  }
  return response;
}

async function forward(request, path) {
  const headers = new Headers(request.headers);
  headers.delete("cookie");
  headers.delete("authorization");
  headers.set("X-Forwarded-For", request.headers.get("CF-Connecting-IP") || "");
  const hasBody = request.method !== "GET" && request.method !== "HEAD";
  return fetch(new Request(`https://${API_HOST}${path}`, {
    method: request.method,
    headers,
    body: hasBody ? await request.arrayBuffer() : null,
    redirect: request.redirect,
  }));
}
