# soon.sortd.page — launch site

A separate one-page hype site for the beta, in the Instagram look (dark, Inter Tight, the four bars).
It is not sortd.page: that full site lives in `../site` and is deployed separately.

- `index.html`, `style.css`, `app.js` — the page, countdown and sign-up.
- The countdown date is `BETA_OPENS` in `app.js` (one line). The sneak-peek screen unblurs at the same time.
- The form posts to `https://sortd.page/api/beta` with `source=soon`; that Worker (`../site/worker/index.js`)
  allows this origin, checks Turnstile and emails the sign-up. Nothing is stored. The form asks for email,
  first name, country and Apple Pay (no Gmail field since 3 Oct 2026). Success state: "You've been Sortd."
  The footer line is "Consider it Sortd."
- Inter Tight is self-hosted in `fonts/` (SIL Open Font License), so no request goes to Google.

## Deploy (one session at a time, from a clean tree)

    cd launch && npx wrangler deploy

First time only, in Cloudflare:
1. Turnstile › the Sortd widget › Hostnames: add `soon.sortd.page`.
2. Deploy `../site` too (its Worker must allow the new origin before this form works).
