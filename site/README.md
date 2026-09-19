# Sortd website

Four static pages and one stylesheet. No build step, no external scripts or fonts.

- `index.html` — home
- `privacy.html` — privacy policy (includes Google's Limited Use sentence)
- `support.html` — FAQ and contact
- `terms.html` — terms of use
- `style.css` — the only stylesheet (light and dark follow the device setting)

## Before publishing

Placeholders are filled (19 Sep 2026): made by Kameshraj Gnanaprakasam, contact
support@sortd.page. That address needs email forwarding set up at the domain registrar
(free at most registrars) so it reaches your inbox. Update "Last updated" when the policy changes.

If the app's behaviour changes (new data, new services it talks to), update `privacy.html` first.

## Publishing

Live at https://sortd.page (Cloudflare Workers static assets, free). Settings are in `wrangler.jsonc`;
`.assetsignore` keeps this README and the config off the site.

    cd site && npx wrangler deploy

After changing `style.css` or `site.js`, bump the `?v=` number in every page's links so browsers
fetch the new copy. Email to support@sortd.page is forwarded by Cloudflare Email Routing.
