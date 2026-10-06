# relay.sortd.page

Passes the app's usage events on to PostHog (US cloud). The app's `POSTHOG_HOST` points
here instead of `us.i.posthog.com`, because blocking apps and DNS filters (NextDNS,
AdGuard, Pi-hole and the like) block PostHog's own address by name.

- Code: `src/index.js`, PostHog's Cloudflare Worker recipe. Nothing is logged or stored;
  cookies and Authorization headers are dropped; the caller's IP goes on as
  `X-Forwarded-For` so locations stay right.
- Deploy: `cd relay && npx wrangler deploy`. Only from a clean tree that matches the pushed
  branch (CLAUDE.md, section 5). Free tier: 100,000 requests a day.
- Check: `curl -s -o /dev/null -w '%{http_code}\n' https://relay.sortd.page/flags/?v=2` gives
  a PostHog answer (400 without a body is fine; a Cloudflare 1xxx error page is not).
- If it ever breaks, set `POSTHOG_HOST` back to `https://us.i.posthog.com` in
  `Secrets.xcconfig`; nothing else changes.
