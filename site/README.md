# Sortd website

Seven static pages, one stylesheet and one small script. No build step, no external fonts. The only
external script is Cloudflare Turnstile on the beta form.

- `index.html` — home
- `privacy.html` — privacy policy (Gmail receipts were removed 2 Oct 2026; Google sign-in is identity only, so no Limited Use sentence)
- `support.html` — FAQ and contact
- `terms.html` — terms of use
- `beta.html`, `beta-thanks.html` — beta sign-up form and thank-you page
- `404.html` — page not found
- `site.js` — theme switch, feature tabs, beta form, scroll reveals and the easter eggs
- `style.css` — the only stylesheet (light and dark follow the device setting)

## Before publishing

Placeholders are filled (19 Sep 2026): made by Kameshraj Gnanaprakasam, contact
support@sortd.page. That address needs email forwarding set up at the domain registrar
(free at most registrars) so it reaches your inbox. Update "Last updated" when the policy changes.

If the app's behaviour changes (new data, new services it talks to), update `privacy.html` first.
Every page's footer carries the sign-off "Consider it Sortd." ("You've been Sortd." is only for the sign-up
thank-you screens.) `img/gmail-light.jpg` and `img/gmail-dark.jpg` are no longer used by any page.

## Publishing

Live at https://sortd.page (Cloudflare Workers static assets, free). Settings are in `wrangler.jsonc`;
`.assetsignore` keeps this README and the config off the site.

    cd site && npx wrangler deploy

After changing `style.css` or `site.js`, bump the `?v=` number in every page's links so browsers
fetch the new copy. The same goes for the logo images (`favicon.png`, `apple-touch-icon.png`,
`icon-256.png`, `og.png`): images are cached for 7 days, so a changed logo needs a new `?v=` too. Email to support@sortd.page is forwarded by Cloudflare Email Routing.

The old launch page soon.sortd.page now sends everyone here (see `../launch/README.md`).
